# rb/eval.janet —— 求值入口（REQ-30 / REQ-31）
#
# 一个求值 = 一个 fiber + 一个环境；环境携带工作区的**栈（变量）**部分，
# `:rb-ws` 携带工作区的其余部分（**字典** + 钩子 + 活 agent，REQ-30）。
# 转译期需要目标工作区的字典，故 rb/compile-source 接受 env 并从中取 dict。
# 转译产物是**可打印的宿主序文本**（REQ-31：可 dump / 可 log）。

(var rb/after-eval-hook nil)

(defn rb/new-env
  "新建一个工作区环境：自带一份数据栈（REQ-30：栈 = 工作区的变量空间）。
   工作区与它的环境互相登记（`:rb-ws` / `:env`），持久化时按对操作。"
  []
  (def env (table/setproto @{:rb-stack @[]} (curenv)))
  (when rb/out-sink (put env :out rb/out-sink))
  (def ws (rb/ws-new))
  (put ws :env env)
  (put env :rb-ws ws)
  env)

(defn rb/compile-source
  "源文本 → {:code 宿主序文本 :nstmt 语句数}；不执行。
   env 决定**用哪个工作区的字典**解析用户词（缺省 = 当前/默认工作区）。"
  [src &opt name env]
  (def dict (rb/dict-of (if env (get env :rb-ws) nil)))
  (def p (rb/lex src name))
  (when (p :incomplete)
    (rb/raise (if (= (p :reason) :unterminated-string)
                (rb/exit-table :lex-unterminated-string)
                (rb/exit-table :lex-unterminated-block))
              (string "未闭合的" (if (= (p :reason) :unterminated-string) "字符串" "块")
                      "（" (p :name) "）")))
  {:code (rb/translate-stmts (p :stmts) dict)
   :nstmt (length (p :stmts))})

(defn rb/run-code
  "执行转译后的宿主序文本。env 复用 = 同一个工作区（REQ-42）；缺省新建（一次性求值）。
   `nested?` = 工具内部求值（PTC 模式的 `eval`）：只跑代码，**不做一轮收尾**，
   否则会在 @Toolcall 钩子内部递归触发 @RoundDone（D-59）。"
  [code &opt name env nested?]
  (def ast (try
             (parse code)
             ([e] (rb/raise (rb/exit-table :syntax-compile)
                            (string "宿主解析失败：" (rb/error-msg e))))))
  (def thunk (compile ast (curenv) (or name "ravel")))
  (when (not (function? thunk))
    (rb/raise (rb/exit-table :syntax-compile)
              (string "宿主编译失败：" (get thunk :error))))
  (def e (or env (rb/new-env)))
  (def stack (e :rb-stack))
  (def snap (array/slice stack))   # 失败则回滚到求值前（D-55）
  (def fb (fiber/new thunk :e e))
  (def res (resume fb))
  (def err? (= (fiber/status fb) :error))
  # D-55：一次求值失败 → **没有栈效果**。栈回到求值前的样子，
  # 于是 REPL / --serve 报错之后可以从干净状态继续（不必重启、不留半截操作数）。
  (when err?
    (array/clear stack)
    (each v snap (array/push stack v)))
  (when (not nested?)
    # REQ-18：一轮正常结束 → 触发 @RoundDone（失败/中断不算「完成」）
    (if err? (rb/round-abort e) (rb/round-finish e))
    # REQ-20/21：绑定了路径的工作区，正常一轮后追加日志并按需 compact。
    # 经一处间接层（同 D-29）：装载顺序上 store 在 eval 之后，逻辑在 store 里。
    (when (not err?)
      (when rb/after-eval-hook (rb/after-eval-hook e))))
  {:ok (not err?)
   :value (if err? nil res)
   :error (if err? (fiber/last-value fb) nil)
   :stack (e :rb-stack)})

(defn rb/run-source
  "源文本 → 执行结果（含 :code，便于 --dump）。
   环境在**转译前**定下来：定义行的装载期注册（REQ-33）必须落在同一个工作区。"
  [src &opt name env nested?]
  (def e (or env (rb/new-env)))
  (def c (rb/compile-source src name e))
  (merge (rb/run-code (c :code) name e nested?) {:code (c :code)}))
