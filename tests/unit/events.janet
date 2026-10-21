# tests/unit/events.janet —— 事件名表与钩子运行时（REQ-16 / REQ-17 / REQ-19）

(deftest "events: 事件名表就是规格附录列出的八个"
  (fn []
    (is= 8 (length rb/event-names))
    (each e @["@Start" "@Chunk" "@Fail" "@Error" "@Close" "@Toolcall" "@Done" "@RoundDone"]
      (is (rb/event? e) (string "应认识事件 " e)))
    (is (not (rb/event? "@Nope")) "未列出的名字不算事件")
    (is (not (rb/event? "RoundDone")) "不带 @ 的不是事件")))

(deftest "events: 未知事件名注册报类型错（31）"
  (fn []
    (def env (new-ws))
    (def fb (in-env env (fn [] (rb/hook-add "@Nope" (fn [] nil)))))
    (is= :error (fiber/status fb))
    (is= 31 (rb/error-code (fiber/last-value fb)))))

(deftest "events: 工作区建好就带一个默认 @RoundDone 钩子"
  (fn []
    (def env (new-ws))
    (is= 1 (hook-count-in env "@RoundDone"))
    (is= 0 (hook-count-in env "@Chunk"))))

(deftest "events: 注册 / 按引号注销 / 清空"
  (fn []
    (def env (new-ws))
    (def q1 (fn [] nil))
    (def q2 (fn [] nil))
    (in-env env (fn []
                  (rb/hook-add "@Chunk" q1)
                  (rb/hook-add "@Chunk" q2)))
    (is= 2 (hook-count-in env "@Chunk"))
    (in-env env (fn [] (rb/hook-del "@Chunk" q1)))
    (is= 1 (hook-count-in env "@Chunk"))
    (in-env env (fn [] (rb/hook-del "@Chunk")))
    (is= 0 (hook-count-in env "@Chunk"))
    (in-env env (fn [] (rb/hook-del "@RoundDone")))
    (is= 0 (hook-count-in env "@RoundDone") "不给引号 = 连默认钩子一起清掉")))

(deftest "events: 载荷按「第一个操作数在栈顶」压栈"
  (fn []
    (def env (new-ws))
    (def got @[])
    (hook-on-in env "@Chunk"
                (fn []
                  (def first (rb/pop))
                  (def second (rb/pop))
                  (array/push got [first second])))
    (in-env env (fn [] (rb/emit "@Chunk" ["块" "流"])))
    (is= (tup [["块" "流"]]) (tup got))))

(deftest "events: 钩子跑完把栈截回原深度（钩子不改变量空间）"
  (fn []
    (def env (new-ws))
    (hook-on-in env "@Done" (fn [] (rb/push 1) (rb/push 2) (rb/push 3)))
    (in-env env (fn [] (rb/push :keep) (rb/emit "@Done" [])))
    (is= (tup [:keep]) (tup (env :rb-stack)))))

(deftest "events: 多个钩子都跑，且互相看不到对方留下的值"
  (fn []
    (def env (new-ws))
    (def order @[])
    (hook-on-in env "@Close" (fn [] (array/push order :a) (rb/push :x)))
    (hook-on-in env "@Close" (fn [] (array/push order :b)))
    (in-env env (fn [] (rb/emit "@Close" [])))
    (is= (tup [:a :b]) (tup order))))

(deftest "events: 没有钩子的事件什么都不做"
  (fn []
    (def env (new-ws))
    (in-env env (fn [] (rb/push 1) (rb/emit "@Unknown" []) (rb/push 2)))
    (is= (tup [1 2]) (tup (env :rb-stack)))))
