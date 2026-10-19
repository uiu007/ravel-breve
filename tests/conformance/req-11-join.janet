# tests/conformance/req-11-join.janet —— REQ-11 连接与切片
#
# REQ-11：`,`（二元）/ `,,`（三元）= 多态 join；
#         `take` / `drop` 支持 N ∈ Z 四象限（附录 A）。

(deftest "REQ-11：`,` 是二元连接"
  (fn []
    (is= ["abcd"] (eval-stack ", \"ab\" \"cd\""))
    (is= [(tuple 1 2)] (eval-stack ", { 1 } { 2 }"))))

(deftest "REQ-11：`,,` 是三元连接"
  (fn []
    (is= ["abc"] (eval-stack ",, \"a\" \"b\" \"c\""))
    (is= [(tuple 1 2 3)] (eval-stack ",, { 1 } { 2 } { 3 }"))))

(deftest "REQ-11：`,` 与 `,,` 等价于左折叠"
  (fn []
    (is= (eval-stack ",, \"a\" \"b\" \"c\"")
         (eval-stack ", , \"a\" \"b\" \"c\""))))

(deftest "REQ-11：take 四象限"
  (fn []
    (is= ["ab"] (eval-stack "take 2 \"abcde\""))
    (is= ["de"] (eval-stack "take -2 \"abcde\""))
    (is= ["abcde"] (eval-stack "take 5 \"abcde\""))
    (is= ["abcde"] (eval-stack "take -5 \"abcde\""))))

(deftest "REQ-11：drop 四象限"
  (fn []
    (is= ["cde"] (eval-stack "drop 2 \"abcde\""))
    (is= ["abc"] (eval-stack "drop -2 \"abcde\""))
    (is= [""] (eval-stack "drop 5 \"abcde\""))
    (is= [""] (eval-stack "drop -5 \"abcde\""))))

(deftest "REQ-11：take/drop 对序列同样成立且保留形态"
  (fn []
    (is= [(tuple 1 2)] (eval-stack "take 2 { 1 2 3 }"))
    (is= [(tuple 1 2)] (eval-stack "drop -1 { 1 2 3 }"))
    (is (tuple? (eval-top "take 2 { 1 2 3 }")))
    (is (array? (eval-top "take 1 , 1 \"a\"")))))
