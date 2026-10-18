# rb/eval.janet —— 求值入口（REQ-30 / REQ-31）
#
# 一个求值 = 一个 fiber + 一个 fiber-local 数据栈环境。
# 转译产物是**可打印的宿主序文本**（REQ-31：可 dump / 可 log）。

(defn rb/new-env
  "新建一个求值环境：fiber-local 数据栈（REQ-30）。"
  []
  (table/setproto @{:rb-stack @[]} (curenv)))

(defn rb/compile-source
  "源文本 → {:code 宿主序文本 :nstmt 语句数}；不执行。"
  [src &opt name]
  (def p (rb/lex src name))
  (when (p :incomplete)
    (rb/raise (if (= (p :reason) :unterminated-string)
                (rb/exit-table :lex-unterminated-string)
                (rb/exit-table :lex-unterminated-block))
              (string "未闭合的" (if (= (p :reason) :unterminated-string) "字符串" "块")
                      "（" (p :name) "）")))
  {:code (rb/translate-stmts (p :stmts))
   :nstmt (length (p :stmts))})

(defn rb/run-code
  "执行转译后的宿主序文本。env 可复用（REPL 保持栈），缺省新建（并发隔离）。"
  [code &opt name env]
  (def ast (try
             (parse code)
             ([e] (rb/raise (rb/exit-table :syntax-compile)
                            (string "宿主解析失败：" (rb/error-msg e))))))
  (def thunk (compile ast (curenv) (or name "ravel")))
  (when (not (function? thunk))
    (rb/raise (rb/exit-table :syntax-compile)
              (string "宿主编译失败：" (get thunk :error))))
  (def e (or env (rb/new-env)))
  (def fb (fiber/new thunk :e e))
  (def res (resume fb))
  (def err? (= (fiber/status fb) :error))
  {:ok (not err?)
   :value (if err? nil res)
   :error (if err? (fiber/last-value fb) nil)
   :stack (e :rb-stack)})

(defn rb/run-source
  "源文本 → 执行结果（含 :code，便于 --dump）。"
  [src &opt name env]
  (def c (rb/compile-source src name))
  (merge (rb/run-code (c :code) name env) {:code (c :code)}))
