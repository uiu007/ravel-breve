# rb/words/l4.janet —— L4 名字、agent 与编排图（附录 A）
#
# 来源树是**内部追踪**，不进词表（REQ-14）；只留一个动词 `origin` 显示来源。
# 重排提示词 = 用 L1 词造新 Session，再 `agent` 新开一个（REQ-13：重排 = 新建血缘）。

(defn rb/agent
  "Label Session [ quot ] -- Agent；引号可选 = 该 agent 的起始行为引号。"
  []
  (def label (rb/pop))
  (def sess (rb/pop))
  (def st (rb/stack))
  (def behavior
    (if (and (not (empty? st)) (function? (array/peek st)))
      (rb/pop)
      nil))
  (when (not (string? label))
    (rb/raise (rb/exit-table :runtime-type)
              (string "标签必须是字符串，得到 " (type label))))
  (def a (rb/agent-new label sess behavior))
  (rb/agent-add! a)
  (rb/push a))

(defn rb/subscribe
  "Agent -- Agent；恢复缺省广播域的订阅（REQ-51：与 unsubscribe 互逆）。"
  []
  (def a (rb/agent-ensure (rb/pop)))
  (put a :live true)
  (def reg ((rb/ws) :agents))
  (var found false)
  (each x reg (when (= x a) (set found true)))
  (unless found (array/push reg a))
  (rb/push a))

(defn rb/-> 
  "Agent Agent -- Agent；线性血缘边：给后者的 origin 记上前者（REQ-51）。"
  []
  (def to (rb/agent-ensure (rb/pop)))
  (def from (rb/agent-ensure (rb/pop)))
  (put to :origin (tuple ;(array/concat @[(from :label)] (to :origin))))
  (rb/push to))

(defn rb/onfail
  "[ quot ] Agent -- Agent；失败回退引号（REQ-51）。
   该 agent 的流失败时，引号收 `Fail` 并以它的产物（String）作为替代回复并入会话。
   目标已在栈上时写 `onfail [ q ]`（最左操作数 = 引号 = 先出栈）。"
  []
  (def q (rb/pop))
  (def a (rb/agent-ensure (rb/pop)))
  (when (not (function? q))
    (rb/raise (rb/exit-table :runtime-type)
              (string "onfail 需要一个引号，得到 " (type q))))
  (put a :onfail q)
  (rb/push a))

(defn rb/origin
  "Agent -- seq；显示来源（唯一的来源动词，REQ-14）。"
  []
  (def a (rb/agent-ensure (rb/pop)))
  (rb/push (a :origin)))

(defn rb/unsubscribe
  "Agent -- Agent；注销（不再参与缺省广播域，REQ-15）。"
  []
  (rb/push (rb/agent-drop! (rb/agent-ensure (rb/pop)))))
