# rb/runtime.janet —— 数据栈运行时（REQ-30 / REQ-31 / §4.9.2）
#
# 数据栈是 **fiber-local** 的：每个求值 fiber 拥有自己的环境表
# @{:rb-stack @[]}，其原型指向核心环境（见 rb/eval.janet）。
# 因此并发 eval 互不污染（REQ-30 验收）。
#
# 约定：方言词一律 **0 元**，自己 pop 所需元数、push 结果（§4.9.3）。
# 栈效应的书写序：附录 A 记法「左 = 栈顶 = 先被消费」。

(defn rb/stack
  "取当前 fiber 的数据栈。"
  []
  (dyn :rb-stack))

(defn rb/push
  "压栈（REQ-31：转译产物中的基本操作）。"
  [x]
  (array/push (rb/stack) x))

(defn rb/pop
  "弹栈并返回值；空栈为运行时错误。"
  []
  (def s (rb/stack))
  (if (empty? s)
    (rb/raise (rb/exit-table :runtime-stack-underflow) "栈下溢")
    (array/pop s)))

(defn rb/peek
  []
  (def s (rb/stack))
  (if (empty? s)
    (rb/raise (rb/exit-table :runtime-stack-underflow) "栈下溢")
    (array/peek s)))

(defn rb/depth
  "L5b：栈深度。"
  []
  (rb/push (length (rb/stack))))

(defn rb/dup
  "L0：X -- X X"
  []
  (rb/push (rb/peek)))

(defn rb/swap
  "L0：X Y -- Y X"
  []
  (def s (rb/stack))
  (def a (rb/pop))
  (def b (rb/pop))
  (array/push s b)
  (array/push s a))

(defn rb/rot
  "L0：X Y Z -- Z X Y（第三元提到栈顶）"
  []
  (def s (rb/stack))
  (def x (rb/pop))
  (def y (rb/pop))
  (def z (rb/pop))
  (array/push s y)
  (array/push s x)
  (array/push s z))

(defn rb/-rot
  "L0：X Y Z -- Y Z X（栈顶沉到第三位）"
  []
  (def s (rb/stack))
  (def x (rb/pop))
  (def y (rb/pop))
  (def z (rb/pop))
  (array/push s x)
  (array/push s z)
  (array/push s y))

(defn rb/apply
  "L0：弹出一个引号（thunk）并求值（REQ-32：引号只由组合子触发）。"
  []
  (def q (rb/pop))
  (if (function? q)
    (q)
    (rb/raise (rb/exit-table :runtime-type) (string "apply 需要引号，得到 " (type q)))))

(defn rb/keep
  "L0：[q] X -- X r（保留 X，再对 X 求 q）"
  []
  (def q (rb/pop))
  (def x (rb/pop))
  (rb/push x)
  (rb/push x)
  (q))

(defn rb/dip
  "L0：[q] X -- ... X（移开 X 执行 q，再把 X 放回）"
  []
  (def q (rb/pop))
  (def x (rb/pop))
  (q)
  (rb/push x))

(defn rb/quot
  "压入一个引号（延迟代码，不求值；REQ-32）。"
  [f]
  (rb/push f))

(defn rb/env-get
  "按名字取环境里的**绑定值**。
  janet 1.42 的 env 项是绑定表：def → @{:value v}，var → @{:ref @[v]}。
  直接 (get (curenv) sym) 拿到的是那张表，不是值 —— 动态查名时必须拆一层。"
  [name &opt env]
  (def e (get (or env (curenv)) (symbol name)))
  (cond
    (nil? e) nil
    (table? e) (if (nil? (get e :ref))
                 (get e :value)
                 (get (get e :ref) 0))
    e))

(defn rb/dump
  "L5b：打印当前数据栈（调试）。"
  []
  (def s (rb/stack))
  (print (string "栈深度 " (length s)))
  (each v s (print (rb/render v))))
