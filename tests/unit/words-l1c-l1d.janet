# tests/unit/words-l1c-l1d.janet —— L1c 字符串工具 / L1d 类型转换（附录 A）

(deftest "L1c：trim"
  (fn []
    (is= ["x"] (eval-stack "trim \"  x \""))
    (is= ["x"] (eval-stack "trim \"\\t x \\n\""))))

(deftest "L1c：replace"
  (fn []
    (is= ["XbX"] (eval-stack "replace \"a\" \"X\" \"aba\""))
    (is= ["a-b-c"] (eval-stack "replace \",\" \"-\" \"a,b,c\""))))

(deftest "L1c：contains / starts-with / ends-with"
  (fn []
    (is= [true] (eval-stack "contains \"b\" \"abc\""))
    (is= [false] (eval-stack "contains \"z\" \"abc\""))
    (is= [true] (eval-stack "starts-with \"ab\" \"abc\""))
    (is= [false] (eval-stack "starts-with \"bc\" \"abc\""))
    (is= [true] (eval-stack "ends-with \"bc\" \"abc\""))
    (is= [false] (eval-stack "ends-with \"ab\" \"abc\""))))

(deftest "L1c：lines / words"
  (fn []
    (is= (tuple (array "a" "b")) (eval-stack "lines \"a\\nb\""))
    (is= (tuple (array "a" "b")) (eval-stack "words \"  a \\t b  \""))
    (is= (tuple (array)) (eval-stack "words \"   \""))))

(deftest "L1d：to-string"
  (fn []
    (is= ["42"] (eval-stack "to-string 42"))
    (is= [""] (eval-stack "to-string nil"))
    (is= ["hi"] (eval-stack "to-string say \"hi\""))
    (is= ["abc"] (eval-stack "to-string \"abc\""))))

(deftest "L1d：to-int"
  (fn []
    (is= [42] (eval-stack "to-int \"42\""))
    (is= [42] (eval-stack "to-int \"  42 \""))
    (is= [7] (eval-stack "to-int 7.9"))
    (is= 31 (eval-exit "to-int \"abc\""))
    (is= 31 (eval-exit "to-int { 1 }"))))
