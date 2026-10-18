# rb/output.janet —— 值 → 文本（核心侧最简渲染）
#
# 注意（边界，REQ-37 / 附录 D）：核心**不含 JSON 解析实现**。
# 这里只做「可读文本」，JSON 编解码由能力层 cap/json.janet 提供。
# M0 阶段 rb/render 采用 Janet 可回读字面量（%q），M2 起 -e/--serve 的
# 机器可读输出改走 cap/json（见 docs/CONFORMANCE.md）。

(defn rb/render
  "把一个值渲染为单行文本（M0：Janet 可回读字面量）。"
  [x]
  (string/format "%q" x))

(defn rb/render-list
  "把序列逐元素渲染为文本数组（REQ-28：show 逐元素打印）。"
  [xs]
  (map rb/render xs))
