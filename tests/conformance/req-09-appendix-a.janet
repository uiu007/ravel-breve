# tests/conformance/req-09-appendix-a.janet —— 附录 A 词表覆盖（REQ-06 / REQ-09）
#
# 目的：**规格里列出的词，实现里就得认得**（不认识 = 报 20「未知的词」）。
# 栈效应不在这里验（各层的验收在别的文件），这里只验「这个词存在」。
#
# 判据：`eval-exit` ≠ 20。空栈会让 0 元的词报 30（栈下溢）——那也是「认识」。

(defn known? [w]
  (not= 20 (eval-exit w)))

(deftest "附录 A：L0 核心栈 / 组合子全部认得"
  (fn []
    (each w ["dup" "pop" "swap" "rot" "-rot" "keep" "dip" "apply" "call"]
      (is (known? w) (string "L0 应有：" w)))))

(deftest "附录 A：L1 / L1b / L1c / L1d 全部认得"
  (fn []
    (each w ["," ",," "len" "first" "last" "take" "drop" "map" "filter" "fold"
             "split" "at" "nth" "reverse" "sort" "zip" "show" "print"
             "wait" "sleep" "retry" "log"
             "=" "!=" "<" ">" "<=" ">=" "not" "and" "or"
             "+" "-" "*" "/" "mod" "abs" "min" "max" "sum"
             "trim" "replace" "contains" "starts-with" "ends-with" "lines" "words"
             "to-string" "to-int"]
      (is (known? w) (string "L1 应有：" w)))))

(deftest "附录 A：L2 / L3 / L4 全部认得"
  (fn []
    (each w ["say" "saysys" "to-json" "from-json" "Role" "Content" "Utter"
             "send" "bcast" "resend" "append" "session"
             "agent" "origin" "watch" "unsubscribe" "subscribe" "->" "onfail"]
      (is (known? w) (string "L2–L4 应有：" w)))))

(deftest "附录 A：L5 / L5b / L6 / L7 / L8 / L9 全部认得"
  (fn []
    (each w ["if" "when" "unless" "loop" "while" "try" "recover"
             "fail" "assert" "depth" "dump" "now" "env"
             "doc" "see"
             "read" "write" "save" "load" "current" "compact"
             "@on" "@off" "deftool" "invoke" "stop" "drain" "next"
             "watch"]
      (is (known? w) (string "L5–L9 应有：" w)))))

(deftest "附录 A：事件名是字面记号，不是词（压栈即字符串）"
  (fn []
    (each ev ["@Start" "@Chunk" "@Fail" "@Error" "@Close" "@Toolcall"
              "@Done" "@RoundDone"]
      (is= (string "\"" ev "\"") (string/format "%q" (eval-top ev))
           (string "事件记号应原样入栈：" ev)))))

(deftest "附录 A：未冻结的词仍报 20（不猜语义，SF-25 / SF-28）"
  (fn []
    # seq / par：规格未给栈效应、结果与并发语义
    (each w ["seq" "par"]
      (is= 20 (eval-exit (string w " 1")) (string "未冻结就该报 20：" w)))
    # Json：附录 A 只把它列为「类型（名词）」，没有任何语义定义
    (is= 20 (eval-exit "Json 1"))
    # 词表里没有 push（REQ-09：字面量自带入栈）
    (is= 20 (eval-exit "push 1"))))
