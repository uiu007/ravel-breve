# rb/words/l9.janet —— L9 前端订阅（REQ-28 / 附录 A「L9 前端订阅」）
#
# `watch` 是**语法糖**：查询绑定（该 agent 的会话）+ 把「视图」以 Stream 交出。
# 视图 = 会话条目的只读回放流：先吐出已有条目，再随 `append` 吐出新增条目，
# 一个条目一块（REQ-28「末尾追加最新 stream」的栈层对应物）。
#
# 它**不进入本轮列表**（`:agent nil` + `:watch true`）：视图是只读观察者，
# 不能被默认收尾钩子当成待合并的产物——否则会话内容会被 `append` 回会话。
# 运行中 agent 的标记由渲染层附加（REQ-28 末句），后端只给出流。

(defn rb/watch
  "Agent -- Stream；该 agent 的视图流（L9，REQ-28）。"
  []
  (def a (rb/agent-ensure (rb/pop)))
  (def s @{:kind :stream
           :label (a :label)
           :agent nil          # 不是发给 agent 的产物 → 收尾钩子不碰它
           :it nil
           :state :new
           :text @""
           :chunks 0
           :watch true
           :cursor 0           # 视图游标：下一条要吐的会话下标
           :closed false
           :error nil
           :meta @{:watch true :of (a :label)}})
  (put s :it
       (fn []
         (def sess (a :session))
         (def i (s :cursor))
         (if (< i (length sess))
           (do (put s :cursor (inc i))
               (rb/render (sess i)))
           nil)))
  (array/push ((rb/ws) :watch) s)
  (rb/push s))
