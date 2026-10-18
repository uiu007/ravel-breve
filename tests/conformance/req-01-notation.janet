# tests/conformance/req-01-notation.janet —— REQ-01 RTL / REQ-02 镜像 / REQ-31 产物
#
# 验收：写下的顺序 = 求值的顺序；同一语义只有一种写法。

(deftest "REQ-01：take 2 \"abcde\" ≡ \"abcde\" 2 take（附录 A 例）"
  (fn []
    (is= ["ab"] (eval-stack "take 2 \"abcde\""))))

(deftest "REQ-01：- 5 3 读作 5 减 3（左 = 栈顶）"
  (fn []
    (is= [2] (eval-stack "- 5 3"))))

(deftest "REQ-01：= 3 3 为真"
  (fn []
    (is= [true] (eval-stack "= 3 3"))))

(deftest "REQ-01：后缀写法不成立（RTL 的反面验收）"
  (fn []
    # "abcde" 2 take 若按后缀读，会先 take 而栈空 → 30 栈下溢
    (is= 30 (eval-exit "\"abcde\" 2 take"))))

(deftest "REQ-02：镜像原理可解释每一条转译（无 VM / 无字节码）"
  (fn []
    # "+ 1 2" 书写序：最左的 1 最后入栈 → 转译为 push 2, push 1, add
    (is= "(do (rb/push 2) (rb/push 1) (rb/add))" (translated "+ 1 2"))
    (is= [3] (eval-stack "+ 1 2"))))

(deftest "REQ-31：转译产物可 dump，且与规格示例逐字一致"
  (fn []
    (is= "(do (rb/push \"abcde\") (rb/push 2) (rb/take))"
         (translated "take 2 \"abcde\""))))
