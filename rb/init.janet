# rb/init.janet —— 装载期自检（规格边界的可执行守卫）
#
# 目的：让「核心词表不含什么」成为**可勾选、可验收**的边界（§5 / §4.9.6 / 附录 D）。
# 这里只做告警式自检（不中断装载），真正的验收在 tests/conformance/。

(def rb/forbidden-words
  # 会话就地编辑词（REQ-12 / §5）
  ["insert" "remove" "move"
   # 来源树词汇（REQ-14 / §5）
   "agents" "focus" "tree" "AgentTree"
   # 明确不实现的 Forth 特性（§4.9.6）
   "immediate" ">r" "r>" "create" "does>" "!" "@"
   # 宿主 / 插值语法（§5）
   "<<" ">>" "$" "(" ")"])

(defn rb/validate
  []
  (each name rb/forbidden-words
    (when (or (not (nil? (get rb/rename name))) (rb/dict? name))
      (eprintf "ravel: 规格违背：词表出现禁用词 %s（§5 / §4.9.6）\n" name)))
  (eachp [k v] rb/rename
    (when (nil? (rb/env-get v))
      (eprintf "ravel: 内部错误：换名表 %s → %s 无实现\n" k v))))

(rb/validate)
