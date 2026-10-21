# tests/unit/words-l0.janet —— L0 核心栈 / 组合子（REQ-01 / REQ-09 / 附录 A）
#
# 读法（REQ-01 的推论）：书写 `词 a b` 时 a **最后**入栈 = 栈顶 = 先被消费。
# 下面每条都写出**书写形式**，期望值是**剩余栈**（底 → 顶）。

(deftest "L0：dup / pop 的栈效应"
  (fn []
    (is= (tup [1 1]) (eval-stack "dup 1"))
    (is= (tup []) (eval-stack "pop 1"))
    # 书写 `pop 2 1`：1 先入栈，2 在栈顶 → pop 掉 2，只剩 1
    (is= (tup [1]) (eval-stack "pop 2 1"))))

(deftest "L0：swap 交换栈顶两项"
  (fn []
    # 书写 `swap 2 1`：栈 = [1 2]（顶 2）→ 交换后 [2 1]
    (is= (tup [2 1]) (eval-stack "swap 2 1"))
    (is= (tup [1 3 2]) (eval-stack "swap 3 2 1"))))

(deftest "L0：rot 把第三元提到栈顶"
  (fn []
    # 栈 [1 2 3]（顶 3）→ [2 3 1]
    (is= (tup [2 3 1]) (eval-stack "rot 3 2 1"))))

(deftest "L0：-rot 把栈顶沉到第三位"
  (fn []
    # 栈 [1 2 3] → [3 1 2]（与 rot 互为反操作）
    (is= (tup [3 1 2]) (eval-stack "-rot 3 2 1"))
    (is= (tup [1 2 3]) (eval-stack "-rot rot 3 2 1") "rot 再 -rot 复原")))

(deftest "L0：keep 保留原值（X -- X r）"
  (fn []
    (is= (tup [2 4]) (eval-stack "keep [ * 2 ] 2"))
    (is= (tup ["ab" 2]) (eval-stack "keep [ len ] \"ab\""))
    # 引号里 dup 会看到两份拷贝（先 X X 再求值）
    (is= (tup [7 7 7]) (eval-stack "keep [ dup ] 7"))))

(deftest "L0：dip 移开栈顶执行引号（[q] X -- … X）"
  (fn []
    # 栈 [1 2]：dip 拿走 2，引号在 [1] 上算 1+1，再把 2 放回
    (is= (tup [2 2]) (eval-stack "dip [ + 1 ] 2 1"))
    # 引号需要栈顶以下有东西时，dip 才会下溢（说明它确实移开了 X）
    (is= 30 (eval-exit "dip [ dup ] 9"))))

(deftest "L0：apply / call 求值引号"
  (fn []
    (is= (tup [3]) (eval-stack "apply [ + 1 2 ]"))
    (is= (tup [3]) (eval-stack "call [ + 1 2 ]"))))

(deftest "L0：引号是数据，不被自动求值（REQ-32）"
  (fn []
    (is (function? (eval-top "[ + 1 2 ]")))
    (is= 1 (length (eval-stack "[ + 1 2 ]")) "引号只入栈，不执行")))

(deftest "L0：栈下溢 → 退出码 30（REQ-23）"
  (fn []
    (is= 30 (eval-exit "pop"))
    (is= 30 (eval-exit "swap 1"))
    (is= 30 (eval-exit "+ 1"))))
