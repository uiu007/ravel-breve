# tests/unit/lexer.janet —— 词法单元测试（REQ-03 / REQ-04）
#
# `rb/lex` 的第二参数只是错误信息里显示的文件名，测试里统一用 "t"。

(deftest "词法：语句与记号切分"
  (fn []
    (def p (rb/lex "take 2 \"abcde\"" "t"))
    (is= 1 (length (p :stmts)))
    (def stmt ((p :stmts) 0))
    (is= 3 (length stmt))
    (is= :word ((stmt 0) :kind))
    (is= "take" ((stmt 0) :value))
    (is= :num ((stmt 1) :kind))
    (is= 2 ((stmt 1) :value))
    (is= :str ((stmt 2) :kind))
    (is= "abcde" ((stmt 2) :value))))

(deftest "词法：换行终结语句（REQ-04）"
  (fn []
    (def p (rb/lex "1 2\n3\n" "t"))
    (is= 2 (length (p :stmts)))
    (is= 2 (length ((p :stmts) 0)))
    (is= 1 (length ((p :stmts) 1)))))

(deftest "词法：反斜杠续行（REQ-04）"
  (fn []
    (def p (rb/lex "1 \\\n2\n" "t"))
    (is= 1 (length (p :stmts)))
    (is= 2 (length ((p :stmts) 0)))))

(deftest "词法：未闭合块 → incomplete（REQ-04 自动续行）"
  (fn []
    (def p (rb/lex "f : [ 1 2\n" "t"))
    (is (p :incomplete))
    (is= :unterminated-block (p :reason))))

(deftest "词法：未闭合字符串 → incomplete"
  (fn []
    (def p (rb/lex "\"abc\n" "t"))
    (is (p :incomplete))
    (is= :unterminated-string (p :reason))))

(deftest "词法：注释与空行"
  (fn []
    (def p (rb/lex "# 注释\n\n1\n   \n" "t"))
    (is= 1 (length (p :stmts)))))

(deftest "词法：块可嵌套，块内语句独立成句"
  (fn []
    (def p (rb/lex "apply [ dup\n[ * 2 ] ] 3" "t"))
    (is= 1 (length (p :stmts)))
    # 顶层语句：apply / [块] / 3
    (def stmt ((p :stmts) 0))
    (is= 3 (length stmt))
    (is= :word ((stmt 0) :kind))
    (is= :block ((stmt 1) :kind))
    # 块内两个语句：dup / [ * 2 ]
    (def inner ((stmt 1) :tokens))
    (is= 2 (length inner))
    (is= :word (((inner 0) 0) :kind))
    (is= :block (((inner 1) 0) :kind))))

(deftest "词法：字符串转义"
  (fn []
    (def p (rb/lex "\"a\\nb\"" "t"))
    (is= "a\nb" ((((p :stmts) 0) 0) :value))))

(deftest "词法：非法转义报 12"
  (fn []
    (is= 12 (eval-exit "\"a\\qb\""))))

(deftest "词法：多余 ] 报 21"
  (fn []
    (is= 21 (eval-exit "]"))))
