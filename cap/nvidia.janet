# cap/nvidia.janet —— 能力层：NVIDIA NIM（OpenAI 兼容 /chat/completions）
#
# 注册键 `:llm/nvidia`：`(messages opts) → 取块函数`。
# 流式：请求 `stream: true`，解析 SSE 的 `data: {…}` 行，只取
# `choices[0].delta.content`；空增量/心跳行跳过；`[DONE]` 结束。
# 错误体（例如 404 的 `{"status":404,"detail":"…"}`）转成方言层错误（60）。

(defn cap/nv-body
  [messages opts]
  (def enc (rb/cap-get :json/encode))
  (when (nil? enc)
    (rb/raise (rb/exit-table :orchestration-base) "能力层未提供 :json/encode"))
  (enc @{:model (opts :model)
         :messages messages
         :stream true
         # D-54：温度与上限也走「工作区配置 > 环境变量 > 缺省」
         :temperature (or (opts :temperature) (cap/llm-temperature))
         :max_tokens (or (opts :max-tokens) (cap/llm-max-tokens))
         :top_p 1
         # REQ-48：工具表非空才带 `tools`（空表 = 纯文本对话）
         :tools (when (and (opts :tools) (> (length (opts :tools)) 0)) (opts :tools))}))

(defn cap/nv-chunk-content
  "从一条 SSE 载荷里取增量文本；取不到返回 nil。"
  [dec payload]
  (def j (protect (dec payload)))
  (if (not (get j 0))
    nil
    (let [obj (get j 1)]
      (when (dictionary? obj)
        (def detail (get obj "detail"))
        (when detail
          (rb/raise (rb/exit-table :orchestration-base)
                    (string "NVIDIA 接口报错：" (string detail))))
        (def err (get obj "error"))
        (when err
          (rb/raise (rb/exit-table :orchestration-base)
                    (string "NVIDIA 接口报错：" (string (if (dictionary? err) (or (get err "message") err) err)))))
        (def choices (get obj "choices"))
        (when (and choices (> (length choices) 0))
          (def delta (get (choices 0) "delta"))
          (when (dictionary? delta)
            (def c (get delta "content"))
            (when (and (string? c) (not (empty? c))) c)))))))

(defn cap/nv-tool-deltas
  "从一条 SSE 载荷里取 `choices[0].delta.tool_calls`（增量片段）；没有则 nil。"
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

(defn cap/nv-chat
  "messages opts → 取块函数"
  [messages opts]
  (def key (cap/nv-key))
  (when (nil? key)
    (rb/raise (rb/exit-table :orchestration-base)
              "未找到 NVIDIA 密钥（设 NVIDIA_API_KEY，或写 secrets/nvidia.key）"))
  (def enc (rb/cap-get :json/encode))
  (def dec (rb/cap-get :json/decode))
  (when (or (nil? enc) (nil? dec))
    (rb/raise (rb/exit-table :orchestration-base) "能力层未提供 JSON 编解码（cap/json）"))
  (def post (rb/cap-get :http/post-lines))
  (when (nil? post)
    (rb/raise (rb/exit-table :orchestration-base) "能力层未提供 :http/post-lines（cap/http）"))
  (when (os/getenv "RB_DEBUG_BODY") (eprintf "BODY| %s" (cap/nv-body messages opts)))
  (def lines (post (or (opts :endpoint) (cap/llm-endpoint))
                   @{"Authorization" (string "Bearer " key)
                     "Content-Type" "application/json"
                     "Accept" "text/event-stream"}
                   (cap/nv-body messages opts)))
  # 工具调用的增量累积（REQ-48）：index → {:id , :name , :args}
  (def acc @{})
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
              (each tc (or (cap/nv-tool-deltas dec payload) [])
                (def idx (or (get tc "index") 0))
                (def cur (or (get acc idx) @{:id "" :name "" :args ""}))
                (when (get tc "id") (put cur :id (string (get tc "id"))))
                (def f (get tc "function"))
                (when (dictionary? f)
                  (when (get f "name") (put cur :name (string (get f "name"))))
                  (when (get f "arguments")
                    (put cur :args (string (cur :args) (get f "arguments")))))
                (put acc idx cur))
              (def c (cap/nv-chunk-content dec payload))
              (when c (set out c) (set go false)))))
        (string/has-prefix? ":" line) nil                # SSE 注释/心跳
        (or (string/has-prefix? "event:" line) (string/has-prefix? "id:" line)) nil
        # 非 SSE 的行：要么是错误体（整段 JSON），要么是无 JSON 的纯文本错误页
        # （例如 404 的 `404 page not found`）。两种都报 60，不许静默返回空回复（D-56）。
        (do
          (def j (protect (dec line)))
          (def obj (when (get j 0) (get j 1)))
          (when (dictionary? obj)
            (def detail (or (get obj "detail") (get obj "error") (get obj "message")))
            (when detail
              (rb/raise (rb/exit-table :orchestration-base)
                        (string "NVIDIA 接口报错："
                                (string (if (dictionary? detail)
                                          (or (get detail "message") detail)
                                          detail)))))
            (def status (get obj "status"))
            (when status
              (rb/raise (rb/exit-table :orchestration-base)
                        (string "NVIDIA 接口报错：HTTP " status
                                (if (get obj "title") (string " " (get obj "title")) "")))))
          (when (not (dictionary? obj))
            (rb/raise (rb/exit-table :orchestration-base)
                      (string "NVIDIA 接口返回非 SSE 内容："
                              (string/slice line 0 (min 200 (length line)))))))))
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
      out))
  pull)

(rb/cap-put :llm/nvidia cap/nv-chat)
