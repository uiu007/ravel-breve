# rb/output.janet —— 值 → 文本（核心侧最简渲染）
#
# 注意（边界，REQ-37 / 附录 D）：核心**不含 JSON 解析实现**。
# 这里只做「可读文本」，JSON 编解码由能力层 cap/json.janet 提供。
#
# 渲染规则（D-32）：
#   - 字符串 → `"…"`，只对 `\\` `"` 与不可打印 ASCII 转义；**高位字节原样输出**
#     （中文不该被印成 `\xE9\x97\xAE`）。
#   - 容器（tuple / array / table / struct）逐个递归，形态与 Janet 字面量一致，
#     因此渲染结果是可回读的。
#   - 其他标量（数 / 关键字 / 布尔 / nil / 函数 / fiber …）交给 `%q`。

(defn rb/render-string
  "把字符串渲染为带引号的单行文本（高位字节不转义）。"
  [s]
  (def b @"\"")
  (each c s
    (cond
      (= c 34) (buffer/push-string b "\\\"")
      (= c 92) (buffer/push-string b "\\\\")
      (= c 10) (buffer/push-string b "\\n")
      (= c 13) (buffer/push-string b "\\r")
      (= c 9) (buffer/push-string b "\\t")
      (< c 32) (buffer/push-string b (string/format "\\x%02x" c))
      (buffer/push-byte b c)))
  (buffer/push-byte b 34)
  (string b))

(defn rb/render
  "把一个值渲染为单行文本（Janet 可回读字面量；字符串保留 UTF-8）。"
  [x]
  (cond
    (string? x) (rb/render-string x)
    (tuple? x) (string "(" (string/join (map rb/render x) " ") ")")
    (array? x) (string "@[" (string/join (map rb/render x) " ") "]")
    (or (table? x) (struct? x))
    (let [body (string/join
                 (map (fn [k] (string (rb/render k) " " (rb/render (get x k))))
                      (sort (keys x)))
                 " ")]
      (string (if (table? x) "@{" "{") body "}"))
    (string/format "%q" x)))

(defn rb/render-list
  "把序列逐元素渲染为文本数组（REQ-28：show 逐元素打印）。"
  [xs]
  (map rb/render xs))
