# rb/stream.janet —— Stream 的生命周期（REQ-08 / REQ-36 / REQ-45 / REQ-46）
#
# Stream 的语义 = 惰性拉取的字符块序列；宿主映射是「取块函数 + 状态机」
# （Janet fiber 的等价物，REQ-36 表）。每次取到一块立即发 `@Chunk`（REQ-08
# 「到达即 flush」），取尽发 `@Done` / `@Close`，出错发 `@Fail` / `@Close`。
#
# 一个 Stream 携带它的**标签绑定**（`Label`）以及预先解析好的 agent 句柄
# （REQ-18 ①：`send` 时就绑定，收尾钩子无需再搜栈）。

# 协议旁路（REQ-24）：serve 模式下，每块/每次关闭**同时**写成一条 NDJSON 消息。
# 用间接层（同 D-29）让 stream 不必静态依赖 rb/proto.janet 的装载序。
(var rb/stream-tap nil)

(defn rb/stream?
  [x]
  (and (table? x) (= (get x :kind) :stream)))

(defn rb/stream-ensure
  [x]
  (when (not (rb/stream? x))
    (rb/raise (rb/exit-table :runtime-type)
              (string "需要一个 Stream，得到 " (type x))))
  x)

(defn rb/stream-new
  "建一个 Stream 并登记进「本轮」（REQ-45：一轮 = list Stream）。
   it = 0 元取块函数，返回 String 或 nil（nil = 结束）。"
  [label agent it &opt meta]
  (def s @{:kind :stream
           :label label
           :agent agent
           :it it
           :state :new      # :new → :open → :done | :failed | :stopped
           :text @""
           :chunks 0        # 已发出的块数（协议用序号，REQ-43/附录 F）
           :watch false     # 是不是 L9 的只读视图流（不进本轮列表）
           :closed false
           :error nil
           :meta (or meta @{})})
  (array/push ((rb/ws) :round) s)
  s)

(defn rb/stream-close!
  "发 `@Close`（每个 Stream 恰好一次）。"
  [s]
  (unless (s :closed)
    (put s :closed true)
    (rb/emit "@Close" [s])
    (when rb/stream-tap (rb/stream-tap s :close nil)))
  s)

(defn rb/stream-next!
  "取下一块；nil = 已到末尾/已中止。"
  [s]
  (case (s :state)
    :new
    (do
      (put s :state :open)
      (rb/emit "@Start" [s])
      (rb/stream-next! s))

    :open
    (let [p (protect ((s :it)))]
      (if (not (get p 0))
        (do
          (put s :state :failed)
          (put s :error (get p 1))
          (rb/emit "@Fail" [(get p 1) s])
          (rb/stream-close! s)
          nil)
        (let [chunk (get p 1)]
          (cond
            (nil? chunk)
            (if (s :watch)
              # L9 视图流（REQ-28）：取尽只是「暂时没有新条目」，不是结束——
              # 关掉它会让前端以为 agent 这一轮结束（REQ-08 的 close 语义）
              nil
              (do
                (put s :state :done)
                (rb/emit "@Done" [s])
                (rb/stream-close! s)
                nil))

            (string? chunk)
            (do
              (buffer/push-string (s :text) chunk)
              (when rb/stream-tap (rb/stream-tap s :chunk chunk))
              (put s :chunks (inc (s :chunks)))
              (rb/emit "@Chunk" [chunk s])
              chunk)

            (rb/raise (rb/exit-table :runtime-type)
                      (string "取块函数必须返回 String 或 nil，得到 " (type chunk)))))))

    nil))

(defn rb/stream-fail-error!
  "流处于 :failed → 抛出（码沿用底因，默认 60 编排层，D-27）。"
  [s]
  (def e (s :error))
  (rb/raise (if (rb/rb-error? e) (get e :rb-code)
                (rb/exit-table :orchestration-base))
            (string "流失败：" (rb/error-msg e))))

(defn rb/stream-drain!
  "取尽（REQ-36：drain），返回拼好的全文；流失败则抛错（D-27）。"
  [s]
  (var go true)
  (while go
    (when (nil? (rb/stream-next! s)) (set go false)))
  (when (= (s :state) :failed)
    (rb/stream-fail-error! s))
  (string (s :text)))

(defn rb/stream-stop!
  "中止（REQ-36：stop）。已结束的流不变。"
  [s]
  (when (or (= (s :state) :new) (= (s :state) :open))
    (put s :state :stopped)
    (rb/stream-close! s))
  s)

(defn rb/stream->utter!
  "REQ-46：Stream → Utter（自动路径与手动路径共用的**唯一**转换）。"
  [s]
  (rb/stream-drain! s)
  (when (= (s :state) :failed)
    (rb/stream-fail-error! s))
  @{:role "assistant" :content (string (s :text))})
