# rb/words/l8.janet —— L8 钩子与流操作（REQ-16 ~ REQ-19 / REQ-36 / REQ-46）
#
# 事件名是 `@` 前缀的字面记号（由转译层直接压栈，见 rb/translate.janet）。

(defn rb/hook-on
  "Event [ quot ] -- ；注册钩子（REQ-16）。书写：`@on @Chunk [ … ]`。"
  []
  (def ev (rb/pop))
  (def q (rb/pop))
  (rb/hook-add ev q)
  nil)

(defn rb/hook-off
  "Event [ quot ]? -- ；注销钩子；不给引号 = 清空该事件全部钩子（REQ-19）。"
  []
  (def ev (rb/pop))
  (def st (rb/stack))
  (if (and (not (empty? st)) (function? (array/peek st)))
    (rb/hook-del ev (rb/pop))
    (rb/hook-del ev))
  nil)

(defn rb/next
  "Stream -- Chunk|nil；取下一块（REQ-36：resume 一次）。"
  []
  (rb/push (rb/stream-next! (rb/stream-ensure (rb/pop)))))

(defn rb/drain
  "Stream -- String；取尽（REQ-36）。"
  []
  (rb/push (rb/stream-drain! (rb/stream-ensure (rb/pop)))))

(defn rb/utter
  "Stream -- Utter；REQ-46：显式转换，自动路径与手动路径共用。"
  []
  (rb/push (rb/stream->utter! (rb/stream-ensure (rb/pop)))))

(defn rb/stop
  "Stream -- Stream；中止（REQ-36）。"
  []
  (rb/push (rb/stream-stop! (rb/stream-ensure (rb/pop)))))
