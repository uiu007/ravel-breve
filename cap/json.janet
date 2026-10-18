# cap/json.janet —— 能力层：JSON 编码（**不属于核心**，REQ-37 / 附录 D）
#
# M0 占位实现：只做编码（--serve 的 NDJSON 输出用），不做解析。
# M2/M6 由 provider 替换（同进程 spork/json 或外部进程），协议不变。
# 删除本文件（make core-only）后核心仍可完成「切词 → 反转 → 栈求值 → 会话编排」。

(defn cap/json/escape
  [s]
  (def b @"")
  (buffer/push-string b "\"")
  (each c s
    (cond
      (= c 34) (buffer/push-string b "\\\"")
      (= c 92) (buffer/push-string b "\\\\")
      (= c 10) (buffer/push-string b "\\n")
      (= c 13) (buffer/push-string b "\\r")
      (= c 9) (buffer/push-string b "\\t")
      (< c 32) (buffer/push-string b (string/format "\\u%04x" c))
      (buffer/push-byte b c)))
  (buffer/push-string b "\"")
  (string b))

(defn cap/json/encode
  [x]
  (cond
    (nil? x) "null"
    (= x true) "true"
    (= x false) "false"
    (number? x) (if (= x (math/floor x))
                  (string/format "%.0f" x)
                  (string/format "%g" x))
    (string? x) (cap/json/escape x)
    (or (keyword? x) (symbol? x)) (cap/json/escape (string x))
    (or (array? x) (tuple? x))
    (string "[" (string/join (map cap/json/encode x) ",") "]")
    (or (table? x) (struct? x))
    (let [pairs (map (fn [k] [k (get x k)]) (keys x))
          sorted (sort pairs (fn [a b] (< (string (a 0)) (string (b 0)))))]
      (string "{" (string/join
                    (map (fn [p] (string (cap/json/escape (string (p 0)))
                                         ":" (cap/json/encode (p 1))))
                         sorted)
                    ",") "}"))
    (cap/json/escape (string x))))

# 自我注册（§4.11）：核心只通过 rb/cap 取用，不认识本文件
(rb/cap-put :json/encode cap/json/encode)
