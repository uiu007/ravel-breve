# tests/unit/cancel.janet —— P3：取消（cancel / stop 血缘传播）与流截止时间
#
# 约定：`stop` 停一个流时沿 `->` 血缘把下游一起停（D-47 的边就是取消边）；
# `cancel` 停掉本工作区所有还开着的流；`RB_STREAM_DEADLINE_MS` 给流一个截止时间。

(defn cz-open
  [s]
  (or (= (s :state) :new) (= (s :state) :open)))

(deftest "P3：stop 沿 -> 血缘停掉下游"
  (fn []
    (def env (new-ws))
    # 书写 `->` 从栈上取两个 agent（先出的那个 = 目标）：
    # `agent "a" { }` → `agent "b" { }` → `->` 得到 a → b 的边
    (def r (run-in env (string "agent \"a\" { }\n"
                               "agent \"b\" { }\n"
                               "->\n")))
    (is (r :ok) (if (r :ok) "" (rb/error-msg (r :error))))
    (def made
      (val-in env (fn []
                    (def reg ((rb/ws) :agents))
                    (def a (first (filter |(= ($ :label) "a") reg)))
                    (def b (first (filter |(= ($ :label) "b") reg)))
                    (rb/agent-append! a @{:role "user" :content "x"})
                    (rb/agent-append! b @{:role "user" :content "y"})
                    @[(rb/stream-start a) (rb/stream-start b)])))
    (def sa (made 0))
    (def sb (made 1))
    (is= (tup ["a"]) (tup ((sb :agent) :origin)) "血缘边在")
    (val-in env (fn [] (rb/stream-stop! sa)))
    (is (= :stopped (sa :state)) "上游停了")
    (is (= :stopped (sb :state)) "下游被血缘带停")))

(deftest "P3：cancel 停掉所有开着的流并返回个数"
  (fn []
    (def env (new-ws))
    (def n (val-in env (fn []
                         (rb/stream-new "x" (rb/agent-new "x" @[]) (fn [] nil))
                         (rb/stream-new "y" (rb/agent-new "y" @[]) (fn [] nil))
                         (rb/cancel-all!))))
    (is= 2 n "两条都停了")
    (is= 0 (length (filter cz-open ((env :rb-ws) :round))) "没有还开着的")))

(deftest "P3：方言 cancel 词返回停下的个数"
  (fn []
    (def env (new-ws))
    (is= 0 (eval-top-in env "cancel") "空工作区 = 0")
    (val-in env (fn [] (rb/stream-new "x" (rb/agent-new "x" @[]) (fn [] nil))))
    (is= 1 (eval-top-in env "cancel"))))

(deftest "P3：RB_STREAM_DEADLINE_MS 到点后中途止住并报 60"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_STREAM_DEADLINE_MS" "30")
    (def s (val-in env (fn []
                         (rb/stream-new "x" (rb/agent-new "x" @[])
                                        (fn [] (os/sleep 0.05) "late")))))
    # 第一次取块还在截止时间内（t0 刚建），第二次才超时
    (val-in env (fn [] (rb/stream-next! s)))
    # 超时 = 流失败（D-27）：取块返回 nil，00 由 fail-error! 在收尾处抛 60
    (is (nil? (val-in env (fn [] (rb/stream-next! s)))) "取不到块")
    (os/setenv "RB_STREAM_DEADLINE_MS" nil)
    (is (= :failed (s :state)) "流被标成 failed")
    (def p (protect (rb/stream-fail-error! s)))
    (is= 60 (if (not (get p 0)) (get (get p 1) :rb-code) 0) "编排级 60")))
