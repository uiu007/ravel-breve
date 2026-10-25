# cap/oai.janet —— 能力层：OpenAI 兼容 /chat/completions 的 SSE 取块循环
#
# 一个 provider 只提供三样：**端点、请求头、请求体**；剩下的解析都在这里（D-64）。
# 共用的解析规则：
#   `data: {…}` 行 → 取 `choices[0].delta.content` 当文本块；
#   `choices[0].delta.tool_calls` → 增量片段，按 `index` 累积（REQ-48）；
#   `choices: []` 的收尾帧带 `usage` → 取块函数在取尽前先吐一个元信息块（REQ-55）；
#   空行 / 注释行 / `event:` / `id:` → 跳过；`[DONE]` → 结束。
# 错误体（JSON 的 `detail`/`error`/`message`，或纯文本错误页）→ 一律 60（D-56）。

(defn cap/oai-error-text
  "从错误体里取人类可读文本；取不到返回 nil。"
  [obj]
  (when (dictionary? obj)
    (def d (or (get obj "detail") (get obj "error") (get obj "message")))
    (when d
      (if (dictionary? d)
        (or (get d "message") (string d))
        (string d)))))

(defn cap/oai-text
  "一条 SSE 载荷 → 增量文本；没有文本返回 nil。错误体直接抛 60。"
  [dec payload label]
  (def j (protect (dec payload)))
  (when (get j 0)
    (def obj (get j 1))
    (when (dictionary? obj)
      (def err (cap/oai-error-text obj))
      (when err
        (rb/raise (rb/exit-table :orchestration-base)
                  (string label " 接口报错：" err)))
      (def choices (get obj "choices"))
      (when (and choices (> (length choices) 0))
        (def delta (get (choices 0) "delta"))
        (when (dictionary? delta)
          (def c (get delta "content"))
          (when (and (string? c) (not (empty? c))) c))))))

(defn cap/oai-tool-deltas
  "一条 SSE 载荷 → `choices[0].delta.tool_calls`（增量片段）；没有则 nil。"
  [dec payload]
  (def j (protect (dec payload)))
  (when (get j 0)
    (def obj (get j 1))
    (when (dictionary? obj)
      (def choices (get obj "choices"))
      (when (and choices (> (length choices) 0))
        (def delta (get (choices 0) "delta"))
        (when (dictionary? delta)
          (def tcs (get delta "tool_calls"))
          (when (and tcs (> (length tcs) 0)) tcs))))))

(defn cap/oai-pull
  "`lines` = 行源（`(fn [] → String|nil)`）；`dec` = JSON 解码；`label` = provider 名。
   返回取块函数（文本 / 工具批 / 用量块 / nil）。"
  [lines dec label]
  # 工具调用的增量累积（REQ-48）：index → {:id , :name , :args}
  (def acc @{})
  # P2：OpenAI 兼容的 usage 帧（通常是 `choices: []` 的最后一帧）
  (var usage nil)
  (var usage-sent false)
  (defn pull []
    (var go true)
    (var out nil)
    (while go
      (def line (lines))
      (when (os/getenv "RB_DEBUG_SSE") (eprintf "SSE| %s" (if (nil? line) "<eof>" line)))
      (cond
        (nil? line) (set go false)                       # 流结束
        (empty? line) nil                                # SSE 空行
        (string/has-prefix? "data:" line)                # SSE 数据行
        (do
          (def payload (string/trim (string/slice line 5)))
          (cond
            (empty? payload) nil
            (= payload "[DONE]") (set go false)
            (do
              (def j (protect (dec payload)))
              (when (get j 0)
                (def obj (get j 1))
                (when (dictionary? obj)
                  (def u (get obj "usage"))
                  (when (dictionary? u) (set usage u))))
              (each tc (or (cap/oai-tool-deltas dec payload) [])
                (def idx (or (get tc "index") 0))
                (def cur (or (get acc idx) @{:id "" :name "" :args ""}))
                (when (get tc "id") (put cur :id (string (get tc "id"))))
                (def f (get tc "function"))
                (when (dictionary? f)
                  (when (get f "name") (put cur :name (string (get f "name"))))
                  (when (get f "arguments")
                    (put cur :args (string (cur :args) (get f "arguments")))))
                (put acc idx cur))
              (def c (cap/oai-text dec payload label))
              (when c (set out c) (set go false)))))
        (string/has-prefix? ":" line) nil                # SSE 注释/心跳
        (or (string/has-prefix? "event:" line) (string/has-prefix? "id:" line)) nil
        # 非 SSE 的行：要么是错误体（整段 JSON），要么是无 JSON 的纯文本错误页
        # （例如 404 的 `404 page not found`）。两种都报 60，不许静默返回空回复（D-56）。
        (do
          (def j (protect (dec line)))
          (def obj (when (get j 0) (get j 1)))
          (def err (cap/oai-error-text obj))
          (when err
            (rb/raise (rb/exit-table :orchestration-base)
                      (string label " 接口报错：" err)))
          (when (dictionary? obj)
            (def status (get obj "status"))
            (when status
              (rb/raise (rb/exit-table :orchestration-base)
                        (string label " 接口报错：HTTP " status
                                (if (get obj "title") (string " " (get obj "title")) "")))))
          (when (not (dictionary? obj))
            (rb/raise (rb/exit-table :orchestration-base)
                      (string label " 接口返回非 SSE 内容："
                              (string/slice line 0 (min 200 (length line)))))))))
    (if (and usage (not usage-sent))
      (do (set usage-sent true) @{:usage usage})
      (if (and (nil? out) (not (empty? acc)))
        (do
          (def calls @[])
          (each idx (sort (keys acc))
            (def cur (get acc idx))
            (def a (protect (dec (cur :args))))
            (array/push calls
                        @{:id (cur :id)
                          :name (cur :name)
                          :arguments (if (get a 0) (get a 1) (cur :args))
                          :raw @{"id" (cur :id)
                                 "type" "function"
                                 "function" @{"name" (cur :name)
                                              "arguments" (cur :args)}}}))
          @{:tool-calls (tuple ;calls)})
        out)))
  pull)
