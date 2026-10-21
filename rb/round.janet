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

(defn rb/round-superseded?
  "s 是否已被**同一 agent 的更新的流**取代（REQ-49：重试 = 新流换旧流）。
   依据 = 本轮列表的创建顺序。"
  [s ss]
  (var seen false)
  (var hit false)
  (each x ss
    (cond
      (= x s) (set seen true)
      (and seen (= (x :agent) (s :agent))) (set hit true)))
  hit)

(defn rb/round-stream-utter
  "② Stream → Utter；失败时若有 `onfail` 回退引号，用它的产物作为替代回复（REQ-51）。
   失败但已被同一 agent 的新流取代（重试）→ 返回 nil，调用方跳过（REQ-49）。"
  [a s]
  (def p (protect (rb/stream->utter! s)))
  (if (get p 0)
    (get p 1)
    (if (rb/round-superseded? s (tuple ;((rb/ws) :round)))
      (do (rb/round-drop! s) nil)
      (do
        (def q (a :onfail))
        (if (nil? q)
          (rb/stream-fail-error! s)    # 没有回退 → 沿用 D-27 的错误
          (do
            (rb/push (get p 1))
            (q)
            @{:role "assistant" :content (string (rb/pop))}))))))

(set rb/default-round-done
     (fn []
       (def ss (rb/pop))
       (each s ss
         (when (and (rb/stream? s) (not (rb/round-superseded? s ss)))
           (def a (rb/agent-ensure (s :agent)))  # ① 绑定（预解析）
           (def u (rb/round-stream-utter a s))    # ② Stream → Utter（含 onfail）
           (when (not (nil? u)) (rb/agent-append! a u))  # ③ append
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
  (when ws
    # 一趟钩子可能再产出流（REQ-49 的重试），故循环到列表空；上限防死循环
    (var pass 0)
    (var rev -1)
    # 一趟之后列表没变（钩子关了、没人认领）→ 结束，别空转（REQ-19）
    (while (and (not (empty? (ws :round)))
                (not= (ws :round-rev) rev)
                (< pass 64))
      (set rev (ws :round-rev))
      (++ pass)
      # REQ-48：有流停在「待外部动作」= 本轮未完成 → 不触发 @RoundDone
      (def frozen @[])
      (each s (ws :round) (when (= (s :state) :tool) (array/push frozen s)))
      (when (not (empty? frozen))
        (array/clear (ws :round))
        (rb/raise (rb/exit-table :orchestration-base)
                  "本轮未完成：工具调用停在待外部动作状态（REQ-48，用 invoke + append + resend 接管）"))
      (def ss (tuple ;(ws :round)))
      (def fb (fiber/new (fn [] (rb/emit "@RoundDone" [ss])) :e env))
      (resume fb)
      (when (= (fiber/status fb) :error)
        (def e (fiber/last-value fb))
        (rb/raise (if (rb/rb-error? e) (get e :rb-code) (rb/exit-table :orchestration-base))
                  (string "@RoundDone 失败：" (rb/error-msg e)))))
    (when (>= pass 64)
      (array/clear (ws :round))
      (rb/raise (rb/exit-table :orchestration-base)
                "本轮收尾超过 64 趟：钩子里可能无限重试（REQ-49）"))
    (array/clear (ws :round)))
  nil)
