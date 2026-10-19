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

# ---- 解码（M2）----------------------------------------------------------
#
# 小型 JSON 解析器；仍在**能力层**，核心不含 JSON 实现（附录 D）。
# 对象 → table（字符串键）；数组 → array。

(defn cap/json/bad
  [msg]
  (error (string "JSON 解析失败：" msg)))

(defn cap/json/skip-ws
  [s i]
  (var j i)
  (while (and (< j (length s))
              (let [c (s j)] (or (= c 32) (= c 9) (= c 10) (= c 13))))
    (++ j))
  j)

(defn cap/json/parse-string
  [s i]
  (var j (inc i))
  (def b @"")
  (var done false)
  (while (not done)
    (when (>= j (length s)) (cap/json/bad "字符串未闭合"))
    (def c (s j))
    (cond
      (= c 34) (set done true)
      (= c 92) (do
                 (++ j)
                 (when (>= j (length s)) (cap/json/bad "转义未闭合"))
                 (def e (s j))
                 (cond
                   (= e 34) (buffer/push-byte b 34)
                   (= e 92) (buffer/push-byte b 92)
                   (= e 47) (buffer/push-byte b 47)
                   (= e 98) (buffer/push-byte b 8)
                   (= e 102) (buffer/push-byte b 12)
                   (= e 110) (buffer/push-byte b 10)
                   (= e 114) (buffer/push-byte b 13)
                   (= e 116) (buffer/push-byte b 9)
                   (= e 117) (do
                              (def hex (string/slice s (inc j) (+ j 5)))
                              (when (not= 4 (length hex)) (cap/json/bad "\\u 需要 4 位十六进制"))
                              (def cp (scan-number (string "0x" hex)))
                              (when (nil? cp) (cap/json/bad (string "非法 \\u：" hex)))
                              (cond
                                (< cp 128) (buffer/push-byte b cp)
                                (< cp 2048) (buffer/push-string
                                              b (string/from-bytes
                                                   (bor 0xC0 (brshift cp 6))
                                                   (bor 0x80 (band cp 0x3F))))
                                (buffer/push-string
                                  b (string/from-bytes
                                       (bor 0xE0 (brshift cp 12))
                                       (bor 0x80 (band (brshift cp 6) 0x3F))
                                       (bor 0x80 (band cp 0x3F)))))
                              (set j (+ j 4)))
                   (cap/json/bad (string "非法转义 \\" (string/from-bytes e))))
                 (++ j))
      (do (buffer/push-byte b c) (++ j))))
  [(string b) (inc j)])

(defn cap/json/parse-number
  [s i]
  (var j i)
  (while (and (< j (length s))
              (let [c (s j)]
                (or (and (>= c 48) (<= c 57))
                    (= c 45) (= c 43) (= c 46) (= c 101) (= c 69))))
    (++ j))
  (def txt (string/slice s i j))
  (def n (scan-number txt))
  (when (nil? n) (cap/json/bad (string "非法数字：" txt)))
  [n j])

(var cap/json/parse-value nil)

(defn cap/json/parse-array
  [s i]
  (var j (inc i))
  (def out @[])
  (set j (cap/json/skip-ws s j))
  (if (and (< j (length s)) (= (s j) 93))
    [out (inc j)]
    (do
      (var done false)
      (while (not done)
        (def [v k] (cap/json/parse-value s j))
        (array/push out v)
        (set j (cap/json/skip-ws s k))
        (when (>= j (length s)) (cap/json/bad "数组未闭合"))
        (def c (s j))
        (cond
          (= c 44) (set j (cap/json/skip-ws s (inc j)))
          (= c 93) (do (set j (inc j)) (set done true))
          (cap/json/bad "数组内期望 , 或 ]")))
      [out j])))

(defn cap/json/parse-object
  [s i]
  (var j (inc i))
  (def out @{})
  (set j (cap/json/skip-ws s j))
  (if (and (< j (length s)) (= (s j) 125))
    [out (inc j)]
    (do
      (var done false)
      (while (not done)
        (set j (cap/json/skip-ws s j))
        (when (or (>= j (length s)) (not= (s j) 34))
          (cap/json/bad "对象键必须是字符串"))
        (def [k k2] (cap/json/parse-string s j))
        (set j (cap/json/skip-ws s k2))
        (when (or (>= j (length s)) (not= (s j) 58)) (cap/json/bad "对象键后期望 :"))
        (set j (cap/json/skip-ws s (inc j)))
        (def [v k3] (cap/json/parse-value s j))
        (put out k v)
        (set j (cap/json/skip-ws s k3))
        (when (>= j (length s)) (cap/json/bad "对象未闭合"))
        (def c (s j))
        (cond
          (= c 44) (set j (cap/json/skip-ws s (inc j)))
          (= c 125) (do (set j (inc j)) (set done true))
          (cap/json/bad "对象内期望 , 或 }")))
      [out j])))

(set cap/json/parse-value
     (fn [s i]
       (var i (cap/json/skip-ws s i))
       (when (>= i (length s)) (cap/json/bad "意外的结束"))
       (def c (s i))
       (cond
         (= c 34) (cap/json/parse-string s i)
         (= c 123) (cap/json/parse-object s i)
         (= c 91) (cap/json/parse-array s i)
         (= c 116) (do
                     (unless (= "true" (string/slice s i (+ i 4))) (cap/json/bad "期望 true"))
                     [true (+ i 4)])
         (= c 102) (do
                     (unless (= "false" (string/slice s i (+ i 5))) (cap/json/bad "期望 false"))
                     [false (+ i 5)])
         (= c 110) (do
                     (unless (= "null" (string/slice s i (+ i 4))) (cap/json/bad "期望 null"))
                     [nil (+ i 4)])
         (cap/json/parse-number s i))))

(defn cap/json/decode
  [s]
  (def [v i] (cap/json/parse-value s 0))
  (def j (cap/json/skip-ws s i))
  (when (not= j (length s)) (cap/json/bad "尾部有残余内容"))
  v)

(rb/cap-put :json/decode cap/json/decode)
