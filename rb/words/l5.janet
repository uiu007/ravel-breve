# rb/words/l5.janet —— L5 控制（附录 A）
#
# 全部是组合子：引号 = 延迟代码（REQ-32），只在组合子内部触发，作用在同一数据栈上。
# 记法：左 = 栈顶 = 先被消费；因此**书写序就是自然阅读序**：
#   if cond [ 体 ] [ 体 ]      when cond [ 体 ]      loop n [ 体 ]
#   while [ 条件 ] [ 体 ]      try [ 体 ] [ 处理 ]   recover [ 体 ] [ 处理 ]
#
# try 与 recover 的差别（见 docs/DECISIONS.md D-19，待 CHK 裁决）：
#   try     —— 失败时把错误值压栈后跑处理引号，**保留**体引号已产生的栈效果；
#   recover —— 失败时先把栈**回滚**到 try 之前的深度，再压错误值跑处理引号。

(defn rb/if
  "cond [then] [else] -- ..."
  []
  (def c (rb/pop))
  (def then-q (rb/pop))
  (def else-q (rb/pop))
  (if c (then-q) (else-q)))

(defn rb/when
  "cond [q] -- ..."
  []
  (def c (rb/pop))
  (def q (rb/pop))
  (when c (q)))

(defn rb/unless
  "cond [q] -- ..."
  []
  (def c (rb/pop))
  (def q (rb/pop))
  (unless c (q)))

(defn rb/loop
  "n [q] -- ...；执行 n 次"
  []
  (def n (rb/pop))
  (def q (rb/pop))
  (for _ 0 n (q)))

(defn rb/while
  "[cond] [body] -- ...；条件引号须留一个真值在栈上"
  []
  (def cond-q (rb/pop))
  (def body-q (rb/pop))
  (var go true)
  (while go
    (cond-q)
    (def v (rb/pop))
    (if (truthy? v) (body-q) (set go false))))

(defn rb/try
  "[body] [handler] -- ...；书写序 `try [ 体 ] [ 处理 ]`，镜像后**体引号在栈顶**。"
  []
  (def body-q (rb/pop))
  (def handler-q (rb/pop))
  (def r (protect (body-q)))
  (when (not (get r 0))
    (rb/push (get r 1))
    (handler-q))
  nil)

(defn rb/recover
  "[body] [handler] -- ...；失败时回滚栈深度再跑处理引号"
  []
  (def body-q (rb/pop))
  (def handler-q (rb/pop))
  (def d0 (length (rb/stack)))
  (def r (protect (body-q)))
  (when (not (get r 0))
    (rb/stack-truncate d0)
    (rb/push (get r 1))
    (handler-q))
  nil)
