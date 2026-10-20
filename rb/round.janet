# rb/round.janet —— 回合的边界与默认收尾钩子（REQ-18 / REQ-19 / REQ-45 / REQ-46）
#
# 一轮 = 一次求值（一次 `-e`、一行 `--serve`、REPL 的一次回车）。
# 一轮的产物 = `list Stream`；求值成功结束时触发 `@RoundDone`，载荷是该列表。
#
# 默认钩子对列表里**每个 stream** 依次做四件事（REQ-18）：
#   ① 解析绑定（已在 `send` 时预解析，O(1)）→ ② `Stream → Utter`（REQ-46）
#   → ③ `append` 进该 agent 的会话 → ④ 从本轮列表删去（退订）
# 用户 `@off @RoundDone` 后可手动 `utter` + `append`，语义等价（REQ-19 / REQ-46）。

(defn rb/round-drop!
  "④ 退订并删去本轮列表里的某个 stream。"
  [s]
  (def reg ((rb/ws) :round))
  (def keep @[])
  (each x reg (when (not (= x s)) (array/push keep x)))
  (array/clear reg)
  (each x keep (array/push reg x))
  (put s :bound true)
  nil)

(defn rb/round-streams
  "本轮到目前为止产出的 stream 列表（tuple）。"
  []
  (tuple ;((rb/ws) :round)))

(set rb/default-round-done
     (fn []
       (def ss (rb/pop))
       (each s ss
         (when (rb/stream? s)
           (def a (rb/agent-ensure (s :agent)))  # ① 绑定（预解析）
           (def u (rb/stream->utter! s))          # ② Stream → Utter
           (rb/agent-append! a u)                 # ③ append
           (rb/round-drop! s)))))                 # ④ 退订并删去

(defn rb/round-abort
  "一轮失败/中止：**不**触发 @RoundDone（REQ-18 排除中断），只把本轮列表丢掉，
   避免残留 stream 混进下一轮。"
  [env]
  (def ws (get env :rb-ws))
  (when ws (array/clear (ws :round)))
  nil)

(defn rb/round-finish
  "一轮结束：在**工作区环境**里触发 `@RoundDone`。
   只在本轮成功结束时调用（REQ-18：工具调用中断代表本轮未完成）。"
  [env]
  (def ws (get env :rb-ws))
  (when (and ws (not (empty? (ws :round))))
    (def ss (tuple ;(ws :round)))
    (def fb (fiber/new (fn [] (rb/emit "@RoundDone" [ss])) :e env))
    (resume fb)
    (when (= (fiber/status fb) :error)
      (def e (fiber/last-value fb))
      (rb/raise (if (rb/rb-error? e) (get e :rb-code) (rb/exit-table :orchestration-base))
                (string "@RoundDone 失败：" (rb/error-msg e))))
    (array/clear (ws :round)))
  nil)
