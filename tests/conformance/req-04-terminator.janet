# tests/conformance/req-04-terminator.janet —— REQ-04 换行终结 / 续行 / 未闭合自动续行

(deftest "REQ-04：换行终结语句，语句共享同一数据栈"
  (fn []
    (is= [2 4] (eval-stack "1 2\n+ 3"))))

(deftest "REQ-04：行末反斜杠续行"
  (fn []
    (is= [3] (eval-stack "1 \\\n2\n+"))))

(deftest "REQ-04：未闭合块自动续行（incomplete 而非错误）"
  (fn []
    (def p (rb/lex "f : [ 1\n2 ]\n" "t"))
    (is (not (p :incomplete)))
    (is= 1 (length (p :stmts)))))

(deftest "REQ-04：未闭合块在整段输入结束时才报错（11）"
  (fn []
    (is= 11 (eval-exit "f : [ 1 2\n"))))

(deftest "REQ-04：空输入不产生语句"
  (fn []
    (is= 0 (length ((rb/lex "\n\n# c\n" "t") :stmts)))))
