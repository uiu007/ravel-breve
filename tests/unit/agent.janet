# tests/unit/agent.janet —— agent 值、标签匹配、会话与消息构造（REQ-12 / REQ-15 / REQ-30）

(deftest "agent: 标签通配 * 与 ?"
  (fn []
    (is (rb/wild-match? "coder*" "coder1"))
    (is (rb/wild-match? "coder*" "coder"))
    (is (rb/wild-match? "coder?" "coder7"))
    (is (not (rb/wild-match? "coder?" "coder77")))
    (is (rb/wild-match? "*" ""))
    (is (rb/wild-match? "*" "任意标签"))
    (is (rb/wild-match? "a*b" "ab"))
    (is (rb/wild-match? "a*b" "a中间b"))
    (is (not (rb/wild-match? "coder" "coder1")))
    (is (rb/wild-match? "c*d*r" "coder"))))

(deftest "agent: 广播域匹配（空域 = 全部）"
  (fn []
    (is (rb/domain-match? (tuple) "任意"))
    (is (rb/domain-match? (tuple "coder*" "reviewer") "coder1"))
    (is (rb/domain-match? (tuple "coder*" "reviewer") "reviewer"))
    (is (not (rb/domain-match? (tuple "coder*") "reviewer")))
    (is (not (rb/domain-match? (tuple "coder*" "reviewer") "other")))))

(deftest "agent: 新建 / 追加 只增不改（REQ-12）"
  (fn []
    (def env (new-ws))
    (in-env env (fn []
                  (def a (rb/agent-new "c" (tuple)))
                  (rb/agent-append! a @{:role "user" :content "一"})
                  (rb/agent-append! a @{:role "assistant" :content "二"})
                  (rb/push a)))
    (def a (last (env :rb-stack)))
    (is= "c" (a :label))
    (is= 2 (length (a :session)))
    (is= "一" (get ((a :session) 0) :content))
    (is= 2 (a :turn))))

(deftest "agent: session 字面量可以是元组，内部转成可增改数组"
  (fn []
    (def env (new-ws))
    (in-env env (fn []
                  (rb/push (rb/agent-new "c" (tuple @{:role "user" :content "x"})))))
    (def a (last (env :rb-stack)))
    (is (array? (a :session)))
    (is= 1 (length (a :session)))))

(deftest "agent: messages-of 只留 role / content 且都是字符串"
  (fn []
    (def env (new-ws))
    (in-env env (fn []
                  (def a (rb/agent-new "c" (tuple)))
                  (rb/agent-append! a @{:role "user" :content "你好"})
                  (rb/push (rb/messages-of a))))
    (def ms (last (env :rb-stack)))
    (is= 1 (length ms))
    (is= "user" (get (ms 0) :role))
    (is= "你好" (get (ms 0) :content))))

(deftest "agent: 注销后不再算活 agent（REQ-15）"
  (fn []
    (def env (new-ws))
    (in-env env (fn []
                  (def a (rb/agent-new "c" (tuple)))
                  (def b (rb/agent-new "d" (tuple)))
                  (rb/agent-add! a)
                  (rb/agent-add! b)
                  (rb/agent-drop! a)
                  (rb/push [(a :live) (b :live) (length ((rb/ws) :agents))])))
    (is= (tup [false true 1]) (tup (last (env :rb-stack))))))

(deftest "agent: 类型校验 —— 非 Agent 一律 31"
  (fn []
    (def env (new-ws))
    (def fb (in-env env (fn [] (rb/agent-ensure "不是 agent"))))
    (is= :error (fiber/status fb))
    (is= 31 (rb/error-code (fiber/last-value fb)))
    (is (rb/agent? (rb/agent-new "c" (tuple))))
    (is (not (rb/agent? @{:kind :stream})))))

(deftest "agent: 未注册的 agent 不能发起（注销后 send 报错）"
  (fn []
    (def env (new-ws))
    (def r (run-in env "agent \"c\" { }\nunsubscribe\ndup\nresend"))
    (is (not (r :ok)))
    (is= 31 (rb/error-code (r :error)))))
