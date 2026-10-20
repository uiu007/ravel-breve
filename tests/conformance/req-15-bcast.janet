# tests/conformance/req-15-bcast.janet —— REQ-15：广播可带域、支持通配、缺省全部未注销

(deftest "REQ-15: 缺省域 = 全部活 agent"
  (fn []
    (def env (new-ws))
    (def r (run-in env "agent \"a\" { }\nagent \"b\" { }\nbcast say \"hi\" { }\nlen"))
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (is= 2 (last (r :stack)) "两个 agent 各得一个流")
    (each a (ws-agents env)
      (is= (tup ["hi" "abcdefgh"]) (tup (map (fn [u] (u :content)) (a :session)))
           (string "agent " (a :label) " 应收到广播，收尾后再拿到回复")))))

(deftest "REQ-15: 域模式支持 * 与 ?"
  (fn []
    (def env (new-ws))
    (def r (run-in env (string
                         "agent \"coder1\" { }\n"
                         "agent \"coder2\" { }\n"
                         "agent \"reviewer\" { }\n"
                         "bcast say \"hi\" { \"coder*\" }\n"
                         "len")))
    (is= 2 (last (r :stack)))
    (def as (ws-agents env))
    (is= 0 (length ((as 2) :session)) "reviewer 不在域内，会话应为空")
    (is= 2 (length ((as 0) :session)) "coder1 收到广播 + 回复")))

(deftest "REQ-15: ? 匹配单字符"
  (fn []
    (def env (new-ws))
    (def r (run-in env (string
                         "agent \"c1\" { }\n"
                         "agent \"c22\" { }\n"
                         "bcast say \"hi\" { \"c?\" }\n"
                         "len")))
    (is= 1 (last (r :stack)))))

(deftest "REQ-15: 已注销的 agent 不再参与缺省广播"
  (fn []
    (def env (new-ws))
    (def r (run-in env (string
                         "agent \"a\" { }\n"
                         "agent \"b\" { }\n"
                         "unsubscribe\n"
                         "bcast say \"hi\" { }\n"
                         "len")))
    (is= 1 (last (r :stack)) "只剩一个活 agent 参与广播")
    (is= 2 (length ((last (ws-agents env)) :session)))))

(deftest "REQ-15: 广播产物是 list Stream，不是字符串"
  (fn []
    (def env (new-ws))
    (def r (run-in env "agent \"a\" { }\nbcast say \"hi\" { }"))
    (def outs (last (r :stack)))
    (is (tuple? outs) "list Stream 用元组表示")
    (is= 1 (length outs))
    (is (rb/stream? (outs 0)))))
