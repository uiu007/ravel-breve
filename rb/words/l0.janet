# rb/words/l0.janet —— L0 核心栈 / 组合子
#
# 实现体在 rb/runtime.janet（栈原语与 fiber-local 数据栈同居一处）。
# 本文件只补齐别名与说明，使「层」在目录结构上可见。

(defn rb/call
  "L0：apply 的别名（弹引号并求值）。"
  []
  (rb/apply))
