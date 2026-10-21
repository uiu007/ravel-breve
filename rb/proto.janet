# rb/proto.janet —— NDJSON 协议 v1 的核心侧（REQ-24 / REQ-43 / 附录 F）
#
# 职责只有两件：
#   ① 提供一条「协议出口」（`rb/proto-sink`），serve 模式把它接到 stdout；
#      非 serve 模式下它是 nil，一切静默（`-e` / 脚本 / REPL 不受影响）。
#   ② stream 的旁路：每块**到达即**发一条 `chunk`，每次关闭发一条 `close`
#      （REQ-08「chunk 到达即 flush」在协议上的体现）。
#
# 消息 schema 见 docs/PROTOCOL.md（M5 冻结）。这里不引入任何 IO 依赖：
# 真正的写 stdout / JSON 编码在 rb/cli.janet（能力层 `:json/encode`）。

(def rb/protocol-version 1)

# (fn [msg] …)：把一条协议消息写给前端。nil = 不在 serve 模式。
(var rb/proto-sink nil)

(defn rb/proto-emit
  "发一条协议消息（无 sink 时什么都不做）。"
  [msg]
  (when rb/proto-sink (rb/proto-sink msg))
  nil)

(defn rb/proto-tap
  "stream 旁路（由 rb/cli.janet 装进 `rb/stream-tap`）。
   chunk 的 `n` = 从 0 起的块序号；close 的 `ok` 取决于流是否失败。"
  [s ev chunk]
  (case ev
    :chunk (rb/proto-emit @{:type "chunk"
                            :stream (string (s :label))
                            :n (s :chunks)
                            :text chunk})
    :close (rb/proto-emit @{:type "close"
                            :stream (string (s :label))
                            :ok (not= (s :state) :failed)})
    nil))

# ---- 事件旁路（REQ-17 / REQ-48 / 附录 F）---------------------------------

(defn rb/proto-event
  "事件旁路（由 rb/cli.janet 装进 `rb/event-tap`）。
   只把 `@Toolcall` 这类带流的事件推给前端（附录 F 的 event 消息形状）。
   载荷形状不够就退化成 `text` = 名称，绝不因为编码失败打断求值。"
  [name payload]
  # 只推 `@Toolcall`：其余事件（@Start/@Chunk/@Close…）已有专门消息，
  # 再发一条 event 只会让前端重复计数（D-45）。
  (when (and rb/proto-sink (= name "@Toolcall"))
    (def call (first payload))
    (def stream (if (> (length payload) 1) (payload 1) nil))
    (def enc (protect (rb/cap-get :json/encode)))
    (def encode (if (get enc 0) (get enc 1) nil))
    (def part (fn [x]
                (cond
                  (string? x) x
                  (buffer? x) (string x)
                  (and encode (not (nil? x))) (protect (encode x))
                  nil)))
    (def args-text
      (cond
        (not (table? call)) nil
        (string? (call :arguments)) (call :arguments)
        :else (let [r (part (call :arguments))]
                (if (tuple? r) (if (get r 0) (get r 1) "") r))))
    (rb/proto-emit @{:type "event"
                      :name name
                      :stream (if (table? stream) (string (stream :label)) nil)
                      :text (if (table? call)
                              (string (call :name) " " (or args-text ""))
                              (string name))})))

# ---- L9 视图流的推送（REQ-24「持续接收」/ REQ-28）------------------------

(def rb/watch-tick-limit 64)

(defn rb/watch-tick!
  "把每个被 `watch` 的视图流推进到取尽，块由旁路变成协议消息。
   每次至多 64 块：宁可下一轮再推，也不让输入饿死（REQ-24 双向不阻塞）。
   返回本次推出的块数。"
  [env]
  (def ws (get env :rb-ws))
  (var total 0)
  (when ws
    (each s (ws :watch)
      (var go (or (= (s :state) :new) (= (s :state) :open)))
      (while (and go (< total rb/watch-tick-limit))
        (if (nil? (rb/stream-next! s))
          (set go false)
          (set total (+ total 1))))))
  total)
