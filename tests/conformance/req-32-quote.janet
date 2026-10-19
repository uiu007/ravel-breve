# tests/conformance/req-32-quote.janet —— REQ-32 引号只由组合子触发
#
# REQ-32：`[ … ]` 压栈即数据（thunk），**只在组合子内部**被触发；
#         组合子作用在同一数据栈上；引号必须消费固定元数、产出固定元数。

(deftest "REQ-32：引号不是词表的一部分（负面）"
  (fn []
    (each w ["quot" "lambda" "fn" "block"]
      (is= 20 (eval-exit (string w " 1"))))))

(deftest "REQ-32：引号可作数据搬运"
  (fn []
    (def s (eval-stack "dup [ 1 ]"))
    (is= 2 (length s))
    (is (function? (s 0)))
    (is (function? (s 1)))))

(deftest "REQ-32：组合子消费引号后不残留"
  (fn []
    (is= [5] (eval-stack "keep [ * 2 ] 5\npop"))
    (is= [(tuple 2)] (eval-stack "map [ * 2 ] { 1 }"))))

(deftest "REQ-32：apply 是显式触发点"
  (fn []
    (is= [42] (eval-stack "apply [ * 2 ] 21"))
    (is= 31 (eval-exit "apply 5"))))

(deftest "REQ-32：引号内可嵌套引号"
  (fn []
    (is= [42] (eval-stack "apply apply [ [ * 2 ] ] 21"))
    (is= [8] (eval-stack "apply [ apply [ * 2 ] ] 4"))))

(deftest "REQ-32：元数不符 → 32"
  (fn []
    (is= 32 (eval-exit "map [ dup ] { 1 }"))
    (is= 32 (eval-exit "filter [ pop 1 1 ] { 1 }"))))
