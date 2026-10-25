# tests/unit/usage.janet —— P2：provider 用量记账
#
# 契约：provider 可以在取尽前吐一个**元信息块** `@{:usage {...}}`；
# 流把它记在 `(stream :usage)`，并**立刻**累加进工作区的 `:usage`（D-62：
# 一轮工具调用跨多次请求，等 `@Done` 只能留最后一笔）。
# 元信息块不是文本：不发 `@Chunk`、不进 `(s :text)`。

(deftest "P2：mock provider 报用量，立刻累加进工作区"
  (fn []
    (def env (new-ws))
    (def us @[])
    (hook-on-in env "@Done" (fn [] (array/push us ((rb/pop) :usage))))
    (def r (run-in env (string "agent \"c\" { }\n"
                               "send say \"问\"\n"
                               "drain")))
    (is (r :ok) (if (r :ok) "" (rb/error-msg (r :error))))
    (is= 1 (length us) "@Done 一次")
    (is (table? (us 0)) "流上带着 usage")
    (def acc ((env :rb-ws) :usage))
    (is= 1 (acc :calls) "记了一次调用")
    (is= (+ (acc :prompt-tokens) (acc :completion-tokens)) (acc :total-tokens)
         "total = prompt + completion")
    (is (> (acc :total-tokens) 0) "数字为正（不是占位 0）")))

(deftest "P2：多轮累加；元信息块不进正文"
  (fn []
    (def env (new-ws))
    (def r1 (run-in env (string "agent \"c\" { }\n"
                                "send say \"一\"\n"
                                "drain")))
    (is (r1 :ok) (if (r1 :ok) "" (rb/error-msg (r1 :error))))
    (def r2 (run-in env (string "agent \"c\" { }\n"
                                "send say \"二\"\n"
                                "drain")))
    (is (r2 :ok) (if (r2 :ok) "" (rb/error-msg (r2 :error))))
    (def acc ((env :rb-ws) :usage))
    (is= 2 (acc :calls))
    (def a (last (ws-agents env)))
    (each u (a :session)
      (is (not (string/find "usage" (or (u :content) ""))) "正文里没有 usage 字样"))))

(deftest "P2：usage 词读出累计值（一份拷贝）"
  (fn []
    (def env (new-ws))
    (run-in env "agent \"c\" { }\nsend say \"问\"\ndrain")
    (def t (eval-top-in env "usage"))
    (is (table? t))
    # 键是字符串：方言没有关键字字面量（REQ-06），`at "calls"` 才读得到
    (is= 1 (t "calls"))
    (put t "calls" 99)
    (is= 1 (((env :rb-ws) :usage) :calls) "改拷贝不影响工作区")))

(deftest "P2：工具轮也记用量（两次调用：工具批 + 最终文本）"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_MOCK_TOOL" "add2:{\"a\":40}")
    (put ((env :rb-ws) :tools) "add2" @{:desc "加 2" :fn (fn [] (rb/push 42) nil)})
    (def r (run-in env (string "agent \"c\" { }\n"
                               "send say \"算\"\n"
                               "drain")))
    (os/setenv "RB_MOCK_TOOL" nil)
    (is (r :ok) (if (r :ok) "" (rb/error-msg (r :error))))
    (is= 2 (((env :rb-ws) :usage) :calls) "工具批 + 最终文本各一次")))
