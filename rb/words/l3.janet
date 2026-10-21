# rb/words/l3.janet —— L3 消息流（附录 A）
#
# 栈效应按唯一方向规则书写：**最左实参 = 第一个操作数 = 栈顶 = 先被消费**。
# 产物一律是 Stream（REQ-45），不直接写会话。
#
# 实参次序（D-26）：消息在前、目标在后 —— `send <消息> <agent>`。
# 理由（D-18 的直接推论）：agent 是**栈上的变量**（REQ-30），已在栈上的值只能
# 落在**最右**实参位置；把目标写在右边，`send say "hi"` 就能直接用栈上的 agent。

(defn rb/append
  "Utter Agent -- Agent；把一条消息追加进该 agent 的活会话（REQ-12）。"
  []
  (def u (rb/utter-ensure (rb/pop)))
  (def a (rb/agent-ensure (rb/pop)))
  (rb/agent-append! a u)
  (rb/push a))

(defn rb/session
  "Agent -- Session；取会话副本（REQ-10：返回新 Session，不改原值）。"
  []
  (rb/push (array/slice ((rb/agent-ensure (rb/pop)) :session))))

(defn rb/send
  "Utter Agent -- Stream；把消息记入会话并发起一轮，产物是流（REQ-45）。"
  []
  (def u (rb/utter-ensure (rb/pop)))
  (def a (rb/agent-ensure (rb/pop)))
  (rb/agent-append! a u)
  (rb/push (rb/stream-start a)))

(defn rb/resend
  "Agent|Stream -- Stream；按现有会话重发（不新增消息）。
   给 Stream 时取它的绑定 agent（REQ-49：失败重试写在钩子里，不必再解析标签）。"
  []
  (def x (rb/pop))
  (def a (if (rb/stream? x) (rb/agent-ensure (x :agent)) (rb/agent-ensure x)))
  (rb/push (rb/stream-start a @{:resend true})))

(defn rb/bcast
  "Utter Domain -- list Stream；域 = 标签模式序列 { \"coder*\" }，空域 = 全部活 agent。"
  []
  (def u (rb/utter-ensure (rb/pop)))
  (def dom (rb/pop))
  (def patterns
    (cond
      (tuple? dom) dom
      (array? dom) (tuple ;dom)
      (nil? dom) (tuple)
      (rb/raise (rb/exit-table :runtime-type)
                (string "广播域必须是序列字面量 { … }，得到 " (type dom)))))
  (def live (filter (fn [a] (a :live)) ((rb/ws) :agents)))
  (def outs @[])
  (each a live
    (when (rb/domain-match? patterns (a :label))
      (rb/agent-append! a u)
      (array/push outs (rb/stream-start a))))
  (rb/push (tuple ;outs)))
