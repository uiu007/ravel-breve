# tests/conformance/req-03-quote.janet —— REQ-03 引号块 / REQ-32 引号只由组合子触发

(deftest "REQ-32：引号压栈不求值"
  (fn []
    # 若块被求值，fail 会报 33
    (def s (eval-stack "[ fail \"x\" ]"))
    (is= 1 (length s))
    (is (function? (s 0)))))

(deftest "REQ-32：引号只是数据，depth 计数为 1"
  (fn []
    (def s (eval-stack "depth [ 1 2 ]"))
    (is= 2 (length s))
    (is (function? (s 0)))
    (is= 1 (s 1))))

(deftest "REQ-03：块内递归反转，由 apply 触发"
  (fn []
    (is= [42] (eval-stack "apply [ * 2 ] 21"))
    (is= [6] (eval-stack "apply [ - 10 4 ]"))))

(deftest "REQ-03：块内语句保持书写序"
  (fn []
    # 块内两条语句：1 2（入栈 2 1）、+ 3（3 + 1 = 4）→ 栈为 2 4
    (is= [2 4] (eval-stack "apply [ 1 2\n+ 3 ]"))))

(deftest "REQ-03：块可嵌套"
  (fn []
    (is= [42] (eval-stack "apply apply [ [ * 2 ] ] 21"))))

(deftest "REQ-32：keep / dip 是仅有的引号触发点（L0）"
  (fn []
    (is= [5 10] (eval-stack "keep [ * 2 ] 5"))
    (is= [6 5] (eval-stack "dip [ * 2 ] 5 3"))))
