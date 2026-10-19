# tests/unit/words-l1.janet —— L1 序列 / 文本与连接（REQ-10 / REQ-11 / 附录 A）

(deftest "L1：len"
  (fn []
    (is= [5] (eval-stack "len \"abcde\""))
    (is= [3] (eval-stack "len { 1 2 3 }"))))

(deftest "L1：take / drop 四象限（REQ-11）"
  (fn []
    (is= ["ab"] (eval-stack "take 2 \"abcde\""))
    (is= ["de"] (eval-stack "take -2 \"abcde\""))
    (is= ["cde"] (eval-stack "drop 2 \"abcde\""))
    (is= ["abc"] (eval-stack "drop -2 \"abcde\""))
    (is= [(tuple 1 2)] (eval-stack "take 2 { 1 2 3 4 }"))
    (is= [(tuple 3 4)] (eval-stack "take -2 { 1 2 3 4 }"))
    (is= [(tuple 3 4)] (eval-stack "drop 2 { 1 2 3 4 }"))
    (is= [(tuple 1 2)] (eval-stack "drop -2 { 1 2 3 4 }"))
    # 越界不报错，按边界截断
    (is= ["ab"] (eval-stack "take 9 \"ab\""))
    (is= [""] (eval-stack "take 0 \"ab\""))))

(deftest "L1：first / last 是 take 1 / take -1 糖"
  (fn []
    (is= ["a"] (eval-stack "first \"abc\""))
    (is= ["c"] (eval-stack "last \"abc\""))
    (is= [(tuple 1)] (eval-stack "first { 1 2 3 }"))))

(deftest "L1：at / nth（支持负索引）"
  (fn []
    (is= [2] (eval-stack "at 1 { 1 2 3 }"))
    (is= [3] (eval-stack "at -1 { 1 2 3 }"))
    (is= ["b"] (eval-stack "at 1 \"abc\""))
    (is= [2] (eval-stack "nth 1 { 1 2 3 }"))))

(deftest "L1：reverse / sort 保留形态"
  (fn []
    (is= ["cba"] (eval-stack "reverse \"abc\""))
    (is= [(tuple 3 2 1)] (eval-stack "reverse { 1 2 3 }"))
    (is= ["abc"] (eval-stack "sort \"cab\""))
    (is= [(tuple 1 2 3)] (eval-stack "sort { 3 1 2 }"))))

(deftest "L1：map 保留形态"
  (fn []
    (is= [(tuple 2 4 6)] (eval-stack "map [ * 2 ] { 1 2 3 }"))
    (is= ["abc"] (eval-stack "map [ to-string ] \"abc\""))))

(deftest "L1：filter 保留形态"
  (fn []
    # 引号里的隐藏实参是**最右**操作数：`[ < 2 ]` 读作 `2 < 元素`
    (is= [(tuple 3 4)] (eval-stack "filter [ < 2 ] { 1 2 3 4 }"))
    (is= ["b"] (eval-stack "filter [ contains \"b\" ] \"abc\""))))

(deftest "L1：fold（引号形如 `q acc x`）"
  (fn []
    (is= [10] (eval-stack "fold [ + ] 0 { 1 2 3 4 }"))
    (is= [24] (eval-stack "fold [ * ] 1 { 1 2 3 4 }"))
    # 非交换：acc - x
    (is= [-10] (eval-stack "fold [ - ] 0 { 1 2 3 4 }"))))

(deftest "L1：组合子引号元数不符 → 运行时元数错误（32）"
  (fn []
    (is= 32 (eval-exit "map [ dup ] { 1 2 }"))
    (is= 32 (eval-exit "map [ pop 1 1 ] { 1 2 }"))))

(deftest "L1：join（REQ-11）"
  (fn []
    (is= ["abcd"] (eval-stack ", \"ab\" \"cd\""))
    (is= ["abc"] (eval-stack ",, \"a\" \"b\" \"c\""))
    (is= [(tuple 1 2 3)] (eval-stack ", { 1 } { 2 3 }"))
    # 异类 → array
    (is= (tuple (array 1 "a")) (eval-stack ", 1 \"a\""))))

(deftest "L1：split（显式分隔符）"
  (fn []
    (is= (tuple (array "a" "b" "c")) (eval-stack "split \",\" \"a,b,c\""))
    (is= (tuple (array "a" "" "b")) (eval-stack "split \",\" \"a,,b\""))))

(deftest "L1：zip"
  (fn []
    (def s (eval-top "zip { 1 2 3 } { \"a\" \"b\" }"))
    (is= 2 (length s))
    (is= (tuple 1 "a") (s 0))
    (is= (tuple 2 "b") (s 1))))

(deftest "L1：非序列实参 → 类型错误（31）"
  (fn []
    (is= 31 (eval-exit "reverse 5"))
    (is= 31 (eval-exit "map [ * 2 ] 5"))))
