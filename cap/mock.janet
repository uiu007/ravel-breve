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

(defn cap/mock-chat-tools
  "工具模式：会话里还没有 role=tool 的消息 → 先给一次工具调用，否则给文本。"
  [messages opts text]
  (def spec (cap/mock-parse-tool))
  (def has-tool-result
    (do
      (var hit false)
      (each m messages (when (= (get m :role) "tool") (set hit true)))
      hit))
  (if (and spec (not has-tool-result))
    (do
      (var sent false)
      (fn []
        (cond
          (not sent)
          (do (set sent true)
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
            @{:usage @{:prompt-tokens prompt-tokens
                       :completion-tokens completion-tokens
                       :total-tokens (+ prompt-tokens completion-tokens)}})

          nil)))))

(defn cap/mock-chat
  [messages opts]
  (def last-msg (if (empty? messages) @{:content ""} (last messages)))
  (def echo (string "回声：" (get last-msg :content "")))
  (def text (string (or (os/getenv "RB_MOCK_REPLY") echo)))
  (cap/mock-chat-tools messages opts text))

(rb/cap-put :llm/mock cap/mock-chat)
