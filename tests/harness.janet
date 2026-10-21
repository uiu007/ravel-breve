# tests/harness.janet —— 极简测试框架（不引第三方）
#
# 约定：只从 tests/run.janet 入口运行。runner.janet 会把本文件与各测试文件
# 装进**同一个**环境（逐 form eval），因此测试文件里可以直接用
# deftest / is= / eval-stack，无需 import。
#
# 为什么不用 (dofile ...)：janet 的 dofile 每个文件开新环境；
# 而 (eval-string ...) 会把所有 form 一起编译（跨 form 前向引用会失败）。
# 内核是**逐 form**编译执行的，测试装载必须一致。

(def harness-tests @[])
(def harness-fails @[])
(def harness-current @{:name "?"})

(defn deftest
  [name body]
  (array/push harness-tests [name body]))

(defn is
  [ok &opt msg]
  (when (not ok)
    (array/push harness-fails [(harness-current :name) :name (or msg "断言为假")])))

(defn is=
  [expected actual &opt msg]
  # 注意：janet 的 = 对数组/表是**同一性**比较，结构比较用 deep=
  (when (not (deep= expected actual))
    (array/push harness-fails
                [(harness-current :name) :name
                 (string (or msg "值不相等")
                         "：期望 " (string/format "%q" expected)
                         "，得到 " (string/format "%q" actual))])))

# ---- 求值辅助 ----

(defn tup
  "把序列冻结为元组（janet 的 = / deep= 对数组是同一性比较，测试里统一比元组）。"
  [xs]
  (tuple ;xs))

(defn eval-stack
  "求值并返回剩余数据栈（元组）；出错返回 [:__error__ 消息]。"
  [src]
  (def r (try (rb/run-source src "test") ([e] {:ok false :error e})))
  (if (r :ok)
    (tup (r :stack))
    [:__error__ (rb/error-msg (r :error))]))

(defn eval-top
  "求值并返回**栈顶**值（栈空则 nil）；出错返回 [:__error__ 消息]。"
  [src]
  (def r (try (rb/run-source src "test") ([e] {:ok false :error e})))
  (if (r :ok)
    (last (r :stack))
    [:__error__ (rb/error-msg (r :error))]))

(defn eval-exit
  "求值并返回退出码（成功 0）。"
  [src]
  (def r (try (rb/run-source src "test") ([e] {:ok false :error e})))
  (if (r :ok) 0 (rb/error-code (r :error))))

(defn eval-ok?
  [src]
  ((try (rb/run-source src "test") ([e] {:ok false :error e})) :ok))

(defn translated
  "取转译产物文本（REQ-31）。"
  [src]
  ((rb/compile-source src "test") :code))

# ---- 工作区（M3：agent / stream / 钩子需要同一份工作区跨步骤）----

(defn new-ws
  "新建一个工作区环境（相当于一次 `ravel` 会话）。"
  []
  (rb/new-env))

(defn run-in
  "在给定工作区里跑源码（一次 = 一轮 = 触发 @RoundDone）。"
  [env src]
  (try (rb/run-source src "test" env) ([e] {:ok false :error e :stack @[]})))

(defn eval-stack-in
  "同 eval-stack，但复用给定工作区。"
  [env src]
  (def r (run-in env src))
  (if (r :ok) (tup (r :stack)) [:__error__ (rb/error-msg (r :error))]))

(defn run-in-exit
  "在给定工作区里跑源码，返回退出码（成功 0）。"
  [env src]
  (def r (run-in env src))
  (if (r :ok) 0 (rb/error-code (r :error))))

(defn eval-top-in
  "同 eval-top，但复用给定工作区。"
  [env src]
  (def r (run-in env src))
  (if (r :ok) (last (r :stack)) [:__error__ (rb/error-msg (r :error))]))

(defn ws-hooks
  "某工作区的钩子表（事件名 → 数组）。"
  [env]
  ((env :rb-ws) :hooks))

(defn hook-on-in
  "在给定工作区上挂一个 janet 钩子（等价于方言里的 @on；用于观察时序）。"
  [env ev f]
  (def h (ws-hooks env))
  (def a (or (get h ev) (let [x @[]] (put h ev x) x)))
  (array/push a f))

(defn hook-count-in
  [env ev]
  (def a (get (ws-hooks env) ev))
  (if a (length a) 0))

(defn ws-agents
  [env]
  ((env :rb-ws) :agents))

(defn in-env
  "在给定工作区环境里运行一个 janet thunk（让 rb/push 等能取到数据栈）。
   返回 fiber 本身——要看有没有抛错用 (fiber/status ...)，要取值用 val-in。"
  [env f]
  (def fb (fiber/new f :e env))
  (resume fb)
  fb)

(defn val-in
  "同 in-env，但返回 thunk 的值（抛错则返回错值）。"
  [env f]
  (fiber/last-value (in-env env f)))
