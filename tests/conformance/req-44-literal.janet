# tests/conformance/req-44-literal.janet —— REQ-44 字面量 vs 引号
#
# REQ-44：`[ … ]` = 延迟代码（引号，参与镜像，只由组合子触发）；
#         `{ … }` / `H{ … }` = 字面量（数据，不求值，整体压栈）。
#         字面量内部只允许字面量；出现词名即语法错误（22）。
#         `H{ }` 重复键后者覆盖（装载期告警）。

(deftest "REQ-44：`{ }` 是数据，不参与镜像"
  (fn []
    # 若参与镜像，元素次序会反转，at 0 将得 3
    (is= 1 (eval-top "at 0 { 1 2 3 }"))
    (is= 3 (eval-top "at 2 { 1 2 3 }"))))

(deftest "REQ-44：`[ ]` 是代码，由组合子触发"
  (fn []
    (is (function? (eval-top "[ 1 2 ]")))
    (is= [42] (eval-stack "apply [ * 2 ] 21"))))

(deftest "REQ-44：`H{ }` 是映射字面量"
  (fn []
    (is= 1 (eval-top "at \"a\" H{ \"a\" 1 }"))))

(deftest "REQ-44：字面量内出现词名 → 语法错误 22"
  (fn []
    (is= 22 (eval-exit "{ dup }"))
    (is= 22 (eval-exit "H{ \"a\" fail }"))
    (is= 22 (eval-exit "{ [ 1 ] }"))))

(deftest "REQ-44：`H{ }` 重复键后者覆盖"
  (fn []
    (is= 2 (eval-top "at \"a\" H{ \"a\" 1 \"a\" 2 }"))
    (is= 1 (eval-top "len H{ \"a\" 1 \"a\" 2 }"))))

(deftest "REQ-44：字面量可嵌套"
  (fn []
    (is= 2 (eval-top "at 0 at 1 { 1 { 2 3 } }"))
    (is= (tuple (tuple (tuple 1 2))) (eval-stack "{ { 1 2 } }"))))
