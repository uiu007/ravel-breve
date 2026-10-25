# rb/tools.janet —— 工具调用（REQ-48）
#
# 工具是**工作区里的表项**（`名字 → { :desc , :fn }`），与字典、钩子、栈同寿命。
# 模型侧契约：
#   `send` 时把工具表转成 provider 的 `tools`；
#   模型返回 `tool_calls` 时 ① 发 `@Toolcall`（载荷 `Call Stream`）
#   ② 本轮未完成 ③ 工具结果以 role "tool" 追加 ④ 自动重发，**同一个流**继续吐文本。
#
# 自动执行是 `@Toolcall` 上的**默认钩子**（与 REQ-18 的 `@RoundDone` 默认钩子同构）：
# `@off @Toolcall` 之后流停在 `:tool`（待外部动作），本轮不算完成。

(defn rb/tool-get
  "按名字取工具表项；不存在返回 nil。"
  [name]
  (get ((rb/ws) :tools) name))

(defn rb/tool-register!
  "注册/覆盖一个工具（REQ-48 的 `deftool`）。"
  [name desc fn]
  (put ((rb/ws) :tools) name @{:desc desc :fn fn})
  nil)

(defn rb/tool-defs
  "工具表 → provider 的 `tools` 数组；表空则为 nil（请求里不带该字段）。"
  []
  (def t ((rb/ws) :tools))
  (if (empty? t)
    nil
    (do
      (def out @[])
      (each name (sort (keys t))
        (def d (get t name))
        (array/push out
                    @{:type "function"
                      :function @{:name name
                                  :description (d :desc)
                                  :parameters @{:type "object"
                                                :additionalProperties true}}}))
      (tuple ;out))))

(defn rb/tool-run
  "调用工具本体：`args` 压栈 → 运引号 → 取栈顶为结果，栈回到调用前深度。
   未注册 / 本体失败 → 60（编排级，REQ-48）。"
  [name args]
  (def d (rb/tool-get name))
  (when (nil? d)
    (rb/raise (rb/exit-table :orchestration-base)
              (string "未注册的工具：" name "（先 deftool 注册，REQ-48）")))
  (def body (d :fn))
  (when (not (function? body))
    (rb/raise (rb/exit-table :orchestration-base)
              (string "工具的体必须是引号：" name)))
  (def d0 (length (rb/stack)))
  (rb/push args)
  (def p (protect (body)))
  (def ok (get p 0))
  (def v (get p 1))
  (def top (if (> (length (rb/stack)) d0) (array/peek (rb/stack)) nil))
  (rb/stack-truncate d0)
  (if ok
    top
    (rb/raise (rb/exit-table :orchestration-base)
              (string "工具失败：" name "：" (rb/error-msg v)))))

(defn rb/tool-encode
  "工具结果 → 追加进会话的 `tool` 消息内容（JSON 文本，经能力层）。"
  [v]
  (def enc (rb/cap-get :json/encode))
  (if (nil? enc)
    (string v)
    (enc v)))

(defn rb/tool-call-new
  "把 provider 交来的一条调用规整成内部结构。"
  [a call]
  @{:kind :tool-call
    :id (or (get call :id) "")
    :name (string (get call :name))
    :arguments (get call :arguments)
    :raw (get call :raw)
    :agent a
    :done false})

(defn rb/default-toolcall-hook
  "默认 `@Toolcall` 钩子：**自动执行**工具并把结果追加进会话。
   载荷 `Call Stream` → 栈顶是 `Call`。"
  []
  (def call (rb/pop))
  (when (= (call :kind) :tool-call)
    (def a (rb/agent-ensure (call :agent)))
    (def v (rb/tool-run (call :name) (call :arguments)))
    (rb/agent-append! a @{:role "tool"
                           :content (rb/tool-encode v)
                           :tool-call-id (call :id)})
    (put call :done true))
  nil)

# 装进工作区的默认钩子（REQ-48；`@off @Toolcall` 后不起作用）
(set rb/default-toolcall rb/default-toolcall-hook)

(defn rb/tool-loop
  "把一个 provider 取块函数包成**工具感知**的取块函数（REQ-48 ④）。
   provider 返回 table = 一次工具调用批：追加 `assistant` 消息 → 发 `@Toolcall`
   → 钩子执行工具并追加 `tool` 消息 → **同一个流**接着取下一批文本。
   有任何调用未被处理（`@off @Toolcall`）→ 把流冻在 `:tool`。"
  [a it0 opts stream]
  (var it it0)
  (fn []
    (var go true)
    (var out nil)
    (while go
      (def v (it))
      (cond
        (nil? v)
        (set go false)

        (string? v)
        (do (set out v) (set go false))

        # P2：纯用量元信息块原样透传（stream-next! 记下来、继续取，不发 @Chunk）。
        # 注意：带 `:tool-calls` 的批要先执行工具，所以这个分支必须排在它后面判。
        (and (table? v) (get v :usage) (not (get v :tool-calls)))
        (do (set out v) (set go false))

        (table? v)
        (do
          (def calls (get v :tool-calls))
          (when (not (and calls (> (length calls) 0)))
            (rb/raise (rb/exit-table :orchestration-base)
                      (string "provider 返回的块既不是文本也不是工具调用："
                              (string/format "%q" v))))
          # 一条 assistant 消息承载这一批调用（OpenAI 兼容格式）
          (rb/agent-append! a @{:role "assistant" :content ""
                                 :tool-calls (tuple ;(map (fn [c] (or (get c :raw) c)) calls))})
          (var blocked false)
          (each raw calls
            (def call (rb/tool-call-new a raw))
            (rb/emit "@Toolcall" [call stream])
            (unless (call :done) (set blocked true)))
          (if blocked
            (do
              (when stream (put stream :state :tool))
              (set go false))
            (do
              (set it (rb/llm-chat (rb/messages-of a) opts))
              (when (not (function? it))
                (rb/raise (rb/exit-table :orchestration-base)
                          (string "provider 必须返回取块函数，得到 " (type it))))
              # P2：这一批若带用量，先把它交出去（流记账后再来取下一批文本）
              (when (get v :usage)
                (set out @{:usage (get v :usage)})
                (set go false)))))

        (rb/raise (rb/exit-table :orchestration-base)
                  (string "provider 的块类型未知：" (type v)))))
    out))

(set rb/tool-hooks
     @{:defs rb/tool-defs
       :wrap (fn [a it opts stream]
               (rb/tool-loop a it opts stream))})
