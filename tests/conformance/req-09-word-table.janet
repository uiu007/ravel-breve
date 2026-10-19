# tests/conformance/req-09-word-table.janet —— REQ-09 词表分层与一名一词性
#
# REQ-09：词表分 L0–L9；**一个名字只有一种词性**；名词大写、动词小写（附录 A）。
#         内置词不可被用户定义遮蔽（换名表优先于字典）。

(deftest "REQ-09：L0 栈/组合子词存在"
  (fn []
    (is= [1 1] (eval-stack "dup 1"))
    (is= [2] (eval-stack "pop 1 2"))
    (is= [1 2] (eval-stack "swap 1 2"))
    (is= [2 1 3] (eval-stack "rot 1 2 3"))
    (is= [1 3 2] (eval-stack "-rot 1 2 3"))
    (is= [42] (eval-stack "apply [ * 2 ] 21"))
    (is= [5 10] (eval-stack "keep [ * 2 ] 5"))
    (is= [6 5] (eval-stack "dip [ * 2 ] 5 3"))))

(deftest "REQ-09：L1b 比较与算术"
  (fn []
    (is= [true] (eval-stack "= 3 3"))
    (is= [false] (eval-stack "= 3 4"))
    (is= [false] (eval-stack "< 5 3"))
    (is= [true] (eval-stack "< 3 5"))
    (is= [8] (eval-stack "+ 5 3"))
    (is= [2] (eval-stack "- 5 3"))
    (is= [15] (eval-stack "* 5 3"))
    (is= [2] (eval-stack "mod 5 3"))
    (is= [6] (eval-stack "sum { 1 2 3 }"))))

(deftest "REQ-09：名词大写（Role / Content / Utter）"
  (fn []
    (is= ["user"] (eval-stack "Role say \"hi\""))
    (is= ["hi"] (eval-stack "Content say \"hi\""))
    (is= ["a"] (eval-stack "Content Utter \"a\" \"a\""))))

(deftest "REQ-09：内置词不可被遮蔽"
  (fn []
    (is (eval-ok? "map : [ 1 ]"))
    # 定义之后 map 仍是内置的 map
    (is= [(tuple 2 4)] (eval-stack "map [ * 2 ] { 1 2 }"))))

(deftest "REQ-09：未知名报词法/语法类错误 20"
  (fn []
    (is= 20 (eval-exit "nosuchword"))
    (is= 20 (eval-exit "Insert"))))

(deftest "REQ-09：来源树词不得出现在词表（负面）"
  (fn []
    (each w ["agents" "focus" "tree" "AgentTree"]
      (is= 20 (eval-exit (string w " 1"))))))
