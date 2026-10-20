# tests/conformance/req-12-13-agent.janet —— REQ-12 会话只追加 / REQ-13 重排 = 新 agent

(deftest "REQ-12: 会话单调增长，只由 append 与收尾钩子写"
  (fn []
    (def env (new-ws))
    (def r (run-in env "agent \"c\" { }\nappend say \"一\"\nappend say \"二\"\nsession"))
    (def sess (last (r :stack)))
    (is= 2 (length sess))
    (is= (tup ["user" "user"]) (tup (map (fn [u] (u :role)) sess)))
    (is= (tup ["一" "二"]) (tup (map (fn [u] (u :content)) sess)))))

(deftest "REQ-12: session 返回副本，改副本不影响 agent（无就地编辑）"
  (fn []
    (def env (new-ws))
    (run-in env "agent \"c\" { }\nappend say \"一\"")
    (def a (last (env :rb-stack)))
    (def r2 (run-in env "session"))
    (def copy (last (r2 :stack)))
    (is= 1 (length (a :session)))
    (array/push copy @{:role "user" :content "二"})
    (is= 2 (length copy))
    (is= 1 (length (a :session)) "副本变了，agent 的会话不该变")))

(deftest "REQ-12: 词表里没有会话就地编辑词"
  (fn []
    (each w @["insert" "remove" "move" "delete" "splice" "set-session"]
      (is= 20 (eval-exit (string w " 1 2 3")) (string w " 不应是方言词")))))

(deftest "REQ-13: 重排 = 用 L1 词造新 Session 再新开 agent，老 agent 不受影响"
  (fn []
    (def env (new-ws))
    (def r (run-in env (string
                         "agent \"old\" { }\n"
                         "append say \"一\"\n"
                         "append say \"二\"\n"
                         "dup\n"
                         "session\n"
                         "reverse\n"
                         "agent \"new\"")))
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (def as (ws-agents env))
    (is= 2 (length as))
    (is= (tup ["old" "new"]) (tup (map (fn [a] (a :label)) as)))
    (def old (as 0))
    (def new (as 1))
    (is= (tup ["一" "二"]) (tup (map (fn [u] (u :content)) (old :session)))
         "老 agent 的会话不变（线性日志）")
    (is= (tup ["二" "一"]) (tup (map (fn [u] (u :content)) (new :session)))
         "新 agent 拿到的是变换后的 Session")))
