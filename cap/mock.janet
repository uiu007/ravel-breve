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

(defn cap/mock-chat
  [messages opts]
  (def last-msg (if (empty? messages) @{:content ""} (last messages)))
  (def echo (string "回声：" (get last-msg :content "")))
  (def text (string (or (os/getenv "RB_MOCK_REPLY") echo)))
  (def chunks (cap/mock-chunks text))
  (var i 0)
  (fn []
    (when (< i (length chunks))
      (def c (chunks i))
      (++ i)
      c)))

(rb/cap-put :llm/mock cap/mock-chat)
