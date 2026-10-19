# tests/unit/literals.janet —— 字面量词法（REQ-44）
#
# 字面量 = 数据：不参与镜像、不求值，整体压栈（REQ-44）。
# 内部只允许字面量（数字 / 字符串 / 布尔 / nil / 嵌套字面量），
# 出现词名即语法错误（22）。

(deftest "字面量：序列整体压栈为 tuple"
  (fn []
    (def s (eval-stack "{ 1 2 3 }"))
    (is= 1 (length s))
    (is (tuple? (s 0)))
    (is= (tuple 1 2 3) (s 0))))

(deftest "字面量：空序列与空映射"
  (fn []
    (is= (tuple (tuple)) (eval-stack "{ }"))
    (is= (tuple @{}) (eval-stack "H{ }"))))

(deftest "字面量：映射压栈为 table"
  (fn []
    (def s (eval-stack "H{ \"a\" 1 \"b\" 2 }"))
    (is= 1 (length s))
    (is (table? (s 0)))
    (is= 1 (get (s 0) "a"))
    (is= 2 (get (s 0) "b"))))

(deftest "字面量：嵌套"
  (fn []
    (is= (tuple (tuple 1 (tuple 2 3))) (eval-stack "{ 1 { 2 3 } }"))
    (is= (tuple (tuple @{"k" (tuple 1)}))
         (eval-stack "{ H{ \"k\" { 1 } } }"))))

(deftest "字面量：布尔与 nil 是字面量"
  (fn []
    (is= (tuple (tuple true false nil)) (eval-stack "{ true false nil }"))))

(deftest "字面量：不参与镜像（元素保持书写序）"
  (fn []
    (is= 1 (eval-top "at 0 { 1 2 3 }"))
    (is= 3 (eval-top "at 2 { 1 2 3 }"))
    (is= -1 (eval-top "at 0 { -1 -2 }"))))

(deftest "字面量：词名非法（22）"
  (fn []
    (is= 22 (eval-exit "{ 1 nope }"))
    (is= 22 (eval-exit "H{ \"a\" nope }"))
    (is= 22 (eval-exit "{ [ 1 ] }"))
    (is= 22 (eval-exit "{ 1 2"))
    (is= 22 (eval-exit "H{ \"a\" }"))))

(deftest "字面量：多余的 } 是语法错误（21）"
  (fn []
    (is= 21 (eval-exit "}"))
    (is= 21 (eval-exit "1 }"))))

(deftest "字面量：H{ 重复键后者覆盖"
  (fn []
    (is= 2 (eval-top "at \"a\" H{ \"a\" 1 \"a\" 2 }"))))

(deftest "字面量：可作普通实参参与前缀式"
  (fn []
    (is= 2 (eval-top "at 0 { 2 3 }"))
    (is= (tuple 6) (eval-stack "+ 1 len { 1 2 3 4 5 }"))))

(deftest "字面量：换行与注释可出现在字面量内部"
  (fn []
    (is= (tuple (tuple 1 2)) (eval-stack "{ 1\n  # 注释\n 2 }"))
    (is= (tuple (tuple 1 2)) (eval-stack "{ 1\n2 }"))))
