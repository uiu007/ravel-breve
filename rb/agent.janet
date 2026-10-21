# rb/agent.janet —— agent 与一轮的发起（REQ-12 / REQ-13 / REQ-30 / REQ-45）
#
# agent 是**工作区栈上的变量**（REQ-30）：一个普通表值，可以被 `dup` / `swap`
# 搬来搬去；同时登记进工作区的「活 agent」表，供 `bcast` 缺省域使用。
#
# 活会话只能 `append`（REQ-12：线性追加日志）；重排提示词 = 用 L1 词造新
# Session 再 `agent` 新开一个（REQ-13）。
#
# 一轮的产物是 **list Stream**（REQ-45）：`send` / `resend` / `bcast` 都只
# 产出 Stream，不直接写会话；写会话只发生在收尾钩子（REQ-18）。

(defn rb/agent?
  [x]
  (and (table? x) (= (get x :kind) :agent)))

(defn rb/agent-ensure
  [x]
  (when (not (rb/agent? x))
    (rb/raise (rb/exit-table :runtime-type)
              (string "需要一个 Agent，得到 " (type x))))
  x)

(defn rb/session-of
  "把会话字面量（{ … } / H{ … } 之外）转成可增改的 array。"
  [x]
  (cond
    (array? x) (array/slice x)
    (tuple? x) (array ;x)
    (nil? x) @[]
    (rb/raise (rb/exit-table :runtime-type)
              (string "Session 必须是序列，得到 " (type x)))))

(defn rb/agent-new
  [label session &opt behavior origin]
  @{:kind :agent
    :label label
    :session (rb/session-of session)
    :behavior behavior
    :origin (or origin (tuple))
    :live true
    :turn 0})

(defn rb/agent-add!
  "登记为活 agent（`bcast` 缺省域 = 全部活 agent）。"
  [a]
  (array/push ((rb/ws) :agents) a)
  a)

(defn rb/agent-drop!
  "注销（REQ-15：缺省广播域只含**未注销**的 agent）。"
  [a]
  (put a :live false)
  (def keep @[])
  (each x ((rb/ws) :agents) (when (not (= x a)) (array/push keep x)))
  (def reg ((rb/ws) :agents))
  (array/clear reg)
  (each x keep (array/push reg x))
  a)

(defn rb/agent-append!
  "REQ-12：唯一允许的会话变更 —— 追加。"
  [a u]
  (array/push (a :session) u)
  (put a :turn (inc (a :turn)))
  a)

(defn rb/messages-of
  "Utter 序列 → provider 需要的消息数组（role / content 都是字符串）。
   REQ-48：带工具调用/结果的 utter 额外带 `tool_calls` / `tool_call_id`。"
  [a]
  (def out @[])
  (each u (a :session)
    (def m @{:role (string (get u :role ""))
             :content (string (get u :content ""))})
    (def tc (get u :tool-calls))
    (when tc (put m :tool_calls tc))
    (def tcid (get u :tool-call-id))
    (when tcid (put m :tool_call_id tcid))
    (array/push out m))
  (tuple ;out))

(defn rb/wild-match?
  "标签通配：`*` 任意串、`?` 单字符（REQ-15）。"
  [pat s]
  (defn go [i j]
    (if (>= i (length pat))
      (>= j (length s))
      (if (= "*" (string/slice pat i (inc i)))
        (or (go (inc i) j)
            (and (< j (length s)) (go i (inc j))))
        (and (< j (length s))
             (let [p (string/slice pat i (inc i))
                   c (string/slice s j (inc j))]
               (and (or (= p "?") (= p c))
                    (go (inc i) (inc j))))))))
  (go 0 0))

(defn rb/domain-match?
  "广播域里的任一模式匹配标签即为命中；空域 = 全部。"
  [patterns label]
  (if (empty? patterns)
    true
    (do
      (var hit false)
      (each p patterns
        (when (string? p)
          (when (rb/wild-match? p label) (set hit true))))
      hit)))

(defn rb/llm-chat
  "经能力层注册表取 provider（§4.11：核心不认识 net/http，也不认识 provider）。"
  [messages opts]
  (def f (rb/cap-get :llm/chat))
  (when (nil? f)
    (rb/raise (rb/exit-table :orchestration-base)
              "能力层未提供 :llm/chat（REQ-37：核心不含网络实现）"))
  (f messages opts))

# 工具层的接入点（REQ-48）。装载序上 tools 在 agent 之后，故用间接层（同 D-29）。
# `@{:wrap (fn [agent it opts] → it') , :defs (fn [] → tools|nil)}`
(var rb/tool-hooks nil)

(defn rb/stream-start
  "对某个 agent 发起一轮：产物是一个 Stream，绑定已在此预先解析（REQ-18 ①）。"
  [a &opt meta]
  (when (not (a :live))
    (rb/raise (rb/exit-table :runtime-type)
              (string "agent 已注销：" (a :label))))
  (def messages (rb/messages-of a))
  (when (empty? messages)
    (rb/raise (rb/exit-table :orchestration-base)
              (string "会话为空，无法发起：" (a :label))))
  (def opts @{:label (a :label) :agent a})
  (when rb/tool-hooks
    (def defs ((rb/tool-hooks :defs)))
    (when defs (put opts :tools defs)))
  (def it0 (rb/llm-chat messages opts))
  (when (not (function? it0))
    (rb/raise (rb/exit-table :orchestration-base)
              (string "provider 必须返回取块函数，得到 " (type it0))))
  # 先建流再装取块函数：工具循环的 `@Toolcall` 载荷要带流本体（REQ-48 ①）
  (def s (rb/stream-new (a :label) a it0 (or meta @{})))
  (when rb/tool-hooks
    (put s :it ((rb/tool-hooks :wrap) a it0 opts s)))
  s)
