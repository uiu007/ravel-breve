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
  (def r (rb/run-source src "test"))
  (if (r :ok)
    (tup (r :stack))
    [:__error__ (rb/error-msg (r :error))]))

(defn eval-exit
  "求值并返回退出码（成功 0）。"
  [src]
  (def r (try (rb/run-source src "test") ([e] {:ok false :error e})))
  (if (r :ok) 0 (rb/error-code (r :error))))

(defn eval-ok?
  [src]
  ((rb/run-source src "test") :ok))

(defn translated
  "取转译产物文本（REQ-31）。"
  [src]
  ((rb/compile-source src "test") :code))
