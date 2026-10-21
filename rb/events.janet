# rb/events.janet —— 事件与钩子（REQ-16 / REQ-17 / REQ-19）
#
# 钩子是**工作区**的一部分（和字典、栈同寿命）：每个工作区一张
# `事件名 → 引号数组` 的表。触发 = 把载荷**压栈**后运行引号，运行完把栈
# 截回原深度（钩子是「观察者/副作用」，不改变变量空间，见 D-25）。
#
# 载荷的压栈顺序遵守唯一方向规则：**第一个操作数最后压**（在栈顶）。
# 因此 `@Chunk` 的载荷写作 `Chunk Stream`，栈顶是 Chunk。

(def rb/event-names
  @["@Start" "@Chunk" "@Fail" "@Error" "@Close" "@Toolcall" "@Done" "@RoundDone"])

(defn rb/event?
  "是不是一个合法的事件名（REQ-17）。"
  [name]
  (var found false)
  (each e rb/event-names (when (= e name) (set found true)))
  found)

(defn rb/event-ensure
  [name]
  (when (not (rb/event? name))
    (rb/raise (rb/exit-table :runtime-type)
              (string "未知的事件名：" name "（REQ-17 只列了 " (string/join rb/event-names " ") "）")))
  name)

# 默认回合收尾钩子的实现（在 rb/round.janet 里装入；这里只留一个间接层，
# 让工作区可以在装载期就注册「默认钩子」，而实现可以稍后定义）。
(var rb/default-round-done nil)

# 默认工具调用钩子（REQ-48；实现在 rb/tools.janet，装载序更晚）
(var rb/default-toolcall nil)

# 事件旁路（REQ-43 的 `event` 消息）：serve 模式下把事件写成 NDJSON。
(var rb/event-tap nil)

(defn rb/ws-new
  "新建一个工作区状态（REQ-30：字典 + 钩子 + 活 agent + 本轮 stream 列表）。
   栈不在这里——它是 env 的 `:rb-stack`（同一工作区的「变量」那半）。"
  []
  @{:dict @{}
    :hooks @{"@RoundDone" @[(fn [] (when rb/default-round-done (rb/default-round-done)))]
             "@Toolcall" @[(fn [] (when rb/default-toolcall (rb/default-toolcall)))]}
    :agents @[]
    :tools @{}     # REQ-48：工具表（名字 → 描述 + 引号）
    :config @{}    # D-54：provider 配置（llm / llm-set / llm-get）
    :round @[]
    :round-rev 0   # 本轮列表的版本号（新建流 +1；收尾据此判断「还在变」）
    :watch @[]     # L9 被 watch 的视图流（REQ-28）
    :path nil      # 持久化目标（nil = 不落盘；REQ-20）
    :seq 0         # 已写入日志的记录数
    :snap-size 0})  # 快照文件字节数（REQ-21 的 0.5 倍判据）

(var rb/ws-default nil)

(defn rb/ws
  "取当前工作区状态（REQ-30：工作区 = 字典 + 栈 + 钩子/活 agent）。"
  []
  (def w (dyn :rb-ws))
  (if (nil? w)
    (do (when (nil? rb/ws-default) (set rb/ws-default (rb/ws-new)))
        rb/ws-default)
    w))

(defn rb/hooks-of
  "取某事件的钩子数组（不存在则建）。"
  [name]
  (def hooks ((rb/ws) :hooks))
  (def arr (get hooks name))
  (if arr
    arr
    (let [a @[]] (put hooks name a) a)))

(defn rb/hook-add
  "注册一个钩子引号（REQ-16：`@on`）。"
  [name q]
  (rb/event-ensure name)
  (when (not (function? q))
    (rb/raise (rb/exit-table :runtime-type)
              (string "@on 需要一个引号，得到 " (type q))))
  (array/push (rb/hooks-of name) q)
  nil)

(defn rb/hook-del
  "注销钩子（REQ-19：`@off` 不给引号 = 清空该事件的全部钩子，含默认钩子）。"
  [name &opt q]
  (rb/event-ensure name)
  (def arr (rb/hooks-of name))
  (if (nil? q)
    (array/clear arr)
    (do
      (def keep @[])
      (each h arr (when (not (= h q)) (array/push keep h)))
      (array/clear arr)
      (each h keep (array/push arr h))))
  nil)

(defn rb/emit
  "触发一个事件：载荷按「第一个操作数最后压」入栈，逐个运行钩子引号。"
  [name payload]
  (def arr (get ((rb/ws) :hooks) name))
  (when (and arr (not (empty? arr)))
    (def d0 (length (rb/stack)))
    (each q (array/slice arr)
      (when (not (function? q))
        (rb/raise (rb/exit-table :runtime-type)
                  (string "钩子必须是引号，得到 " (type q))))
      (each v (reverse payload) (rb/push v))
      (q)
      (rb/stack-truncate d0)))
  (when rb/event-tap (rb/event-tap name payload))
  nil)

(defn rb/hook-count
  "某事件当前的钩子数（调试 / 测试用）。"
  [name]
  (def arr (get ((rb/ws) :hooks) name))
  (if arr (length arr) 0))
