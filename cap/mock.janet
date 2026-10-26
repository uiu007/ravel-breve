# cap/mock.janet —— 能力层：确定性 mock provider（离线测试 / 无密钥降级）
#
# 注册键 `:llm/mock`：`(messages opts) → 取块函数`。
# 回复内容 = RB_MOCK_REPLY，缺省「回声：<最后一条消息>」；按**字符**切成 4 块
# 逐块吐出，因此 @Chunk / @Done 的时序在离线测试里完全可复现，且不切坏 UTF-8。

(defn cap/chars
  "按 UTF-8 边界把字符串切成字符数组（Janet 的 string/slice 是字节切片）。"
  [s]
  (def bs (string/bytes s))
  (def n (length bs))
  (def out @[])
  (var i 0)
  (while (< i n)
    (def b (get bs i))
    (def w (cond
             (< b 0x80) 1
             (and (>= b 0xC0) (< b 0xE0)) 2
             (and (>= b 0xE0) (< b 0xF0)) 3
             (and (>= b 0xF0) (< b 0xF8)) 4
             1))
    (array/push out (string/slice s i (min n (+ i w))))
    (set i (+ i w)))
  out)

(defn cap/mock-chunks
  "切成至多 4 块（每块至少 1 个字符）。"
  [s]
  (def cs (cap/chars s))
  (def n (length cs))
  (if (= n 0)
    @[]
    (do
      (def size (max 1 (math/ceil (/ n 4))))
      (def out @[])
      (var i 0)
      (while (< i n)
        (def j (min n (+ i size)))
        (array/push out (string/join (tuple/slice cs i j) ""))
        (set i j))
      out)))

(defn cap/mock-parse-tool
  "RB_MOCK_TOOL = 工具名，或 工具名:{json参数}；返回一条调用或 nil。"
  []
  (def spec (os/getenv "RB_MOCK_TOOL"))
  (if (nil? spec)
    nil
    (do
      (def i (string/find ":" spec))
      (if (nil? i)
        @{:id "call_mock" :name spec :arguments @{}
          :raw @{"id" "call_mock" "type" "function"
                 "function" @{"name" spec "arguments" "{}"}}}
        (do
          (def name (string/slice spec 0 i))
          (def argstr (string/slice spec (inc i)))
          (def j (protect ((rb/cap-get :json/decode) argstr)))
          (def args (if (get j 0) (get j 1) argstr))
          @{:id "call_mock" :name name :arguments args
            :raw @{"id" "call_mock" "type" "function"
                   "function" @{"name" name "arguments" argstr}}})))))

(defn cap/mock-list-at
  "把环境变量当成逗号分隔的列表，取第 `idx` 项（越界 = 最后一项；空/未设 = nil）。
   REQ-70 用它模拟「第一次响应该被截断、第二次正常」这类确定序列。"
  [name idx]
  (def v (os/getenv name))
  (when (and v (not (empty? v)))
    (def items (string/split "," v))
    (when (> (length items) 0)
      (def i (min (max 0 idx) (- (length items) 1)))
      (def s (string/trim (items i)))
      (if (empty? s) nil s))))

(defn cap/mock-turn-idx
  "本请求是这一轮的第几次（按 user 消息数减一算；续写会追加一条 user 消息，于是递增）。"
  [messages]
  (var n 0)
  (each m messages (when (= (get m :role) "user") (++ n)))
  (max 0 (- n 1)))

(defn cap/mock-finish
  "REQ-70 / REQ-71：收尾块。`RB_MOCK_FINISH` = 逗号序列（如 `length,stop`）；
   `RB_MOCK_EMPTY` = 逗号序列的 0/1。`:out` = 这次响应的正文 tokens（mock 用字符数），
   `:max` = 这次请求实际拿到的额度——两者一起才能判「额度真的用完了」。"
  [messages chars calls budget]
  (def idx (cap/mock-turn-idx messages))
  (def empty? (= "1" (cap/mock-list-at "RB_MOCK_EMPTY" idx)))
  (def reason (or (cap/mock-list-at "RB_MOCK_FINISH" idx) "stop"))
  (def n (if empty? 0 chars))
  @{:finish reason
    :chars n
    :calls calls
    :out n
    :max (budget :max-tokens)})

(defn cap/mock-chat-tools
  "工具模式：会话里还没有 role=tool 的消息 → 先给一次工具调用，否则给文本。"
  [messages opts text budget]
  (def spec (cap/mock-parse-tool))
  (def has-tool-result
    (do
      (var hit false)
      (each m messages (when (= (get m :role) "tool") (set hit true)))
      hit))
  (if (and spec (not has-tool-result))
    (do
      (var step 0)
      (fn []
        (cond
          (= step 0)
          (do (set step 1)
              # REQ-70：先交收尾块（截断/空转要靠它判）
              (cap/mock-finish messages 0 1 budget))

          (= step 1)
          (do (set step 2)
              # 工具批也带用量（P2）：真实 provider 通常把 usage 放在最后一帧，
              # mock 这里显式给，好让离线测试能断言「每次 provider 请求都记了」
              @{:tool-calls (tuple ;[(cap/mock-parse-tool)])
                :usage @{:prompt-tokens 1 :completion-tokens 1 :total-tokens 2}})

          nil)))
    (do
      (def chunks (cap/mock-chunks text))
      (def n (length chunks))
      # P2：mock 也报用量（确定性：按 UTF-8 字符数算，离线可断言）
      (def prompt-tokens
        (do
          (var t 0)
          (each m messages (set t (+ t (length (cap/chars (get m :content ""))))))
          t))
      (def completion-tokens (length (cap/chars text)))
      (var i 0)
      (fn []
        (cond
          (< i n)
          (do
            (def c (chunks i))
            (++ i)
            c)

          (= i n)
          (do
            (++ i)
            # REQ-70：收尾块先出，用量块后出（顺序与 cap/oai.janet 一致）
            (cap/mock-finish messages (length (cap/chars text)) 0 budget))

          (= i (inc n))
          (do
            (++ i)
            @{:usage @{:prompt-tokens prompt-tokens
                       :completion-tokens completion-tokens
                       :total-tokens (+ prompt-tokens completion-tokens)}})

          nil)))))

(defn cap/mock-chat
  [messages opts]
  (def last-msg (if (empty? messages) @{:content ""} (last messages)))
  (def echo (string "回声：" (get last-msg :content "")))
  (var text (string (or (os/getenv "RB_MOCK_REPLY") echo)))
  # REQ-70：`RB_MOCK_EMPTY` 命中的那一次响应返回**空正文**（模拟「推理吃光预算」）
  (when (= "1" (cap/mock-list-at "RB_MOCK_EMPTY" (cap/mock-turn-idx messages)))
    (set text ""))
  # REQ-71：mock 也要走同一套预算（`RB_MAX_TOKENS` 小到离谱时能测「额度用完」）
  # REQ-72：mock 也打 `BUDGET|` 行，于是「est 随语言变」不用联网就能看
  (def budget (cap/llm-budget messages opts))
  (when (os/getenv "RB_DEBUG_BUDGET") (eprintf "BUDGET| %q" budget))
  (cap/mock-chat-tools messages opts text budget))

(rb/cap-put :llm/mock cap/mock-chat)
