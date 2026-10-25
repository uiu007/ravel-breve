# rb/events.janet —— 事件与钩子（REQ-16 / REQ-17 / REQ-19）
#
# 钩子是**工作区**的一部分（和字典、栈同寿命）：每个工作区一张
# `事件名 → 引号数组` 的表。触发 = 把载荷**压栈**后运行引号，运行完把栈
# 截回原深度（钩子是「观察者/副作用」，不改变变量空间，见 D-25）。
#
# 载荷的压栈顺序遵守唯一方向规则：**第一个操作数最后压**（在栈顶）。
# 因此 `@Chunk` 的载荷写作 `Chunk Stream`，栈顶是 Chunk。
#
# `@Approve`（REQ-69 / D-75）是**审批**事件：工具因策略（沙箱/授权）被拒时，
# 默认 `@Toolcall` 钩子不立刻 60，而是发 `@Approve`（载荷 `Request Stream`），
# 由钩子填 `:decision` 与 `:grant`。缺省实现问终端（非交互 = 拒绝）。

(def rb/event-names
  @["@Start" "@Chunk" "@Fail" "@Error" "@Close" "@Toolcall" "@Approve" "@Done" "@RoundDone"])

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

# 默认审批钩子（REQ-69；同在 rb/tools.janet）
(var rb/default-approve nil)

# 事件旁路（REQ-43 的 `event` 消息）：serve 模式下把事件写成 NDJSON。
(var rb/event-tap nil)

# 模式层（D-59）：`rb/stream-start` 在取消息之前调用它注入模式的 system 提示。
# 装载序上 modes.janet 晚于 agent.janet，故走间接层（同 D-29）。
(var rb/mode-inject-prompt nil)

# 历史标记开关（D-59）：默认全开；`flag-set false "history-turn"` 可关掉。
# 标记写在 Utter 上（`:turn` / `:from` / `:mode`），供前端与摘要钩子读，不进 provider 消息。
(def rb/flag-defaults
  # `plan` 是**正交于预置模式**的开关（D-72）：进 plan 只加提示与一个工具，不换模式。
  # `allow-shell` 是**工具的前置设定**（REQ-67）：`shell` 需要它。缺省**开**——
  # 缺省工具表里有 shell，而"看得见却一调就失败"不是"默认配好"，是埋雷（D-73）。
  # 关掉的两条路：`flag-set false "allow-shell"` / `RB_ALLOW_SHELL=0`（明细见 `--modes`）。
  @{"history-turn" true "history-origin" true "history-mode" true
    "plan" false "allow-shell" true})

# 默认钩子的**同一批函数对象**：`ws-new` 与 `default` 模式共用它们，
# 于是「模式 → 钩子 → 模式」可以用 `deep=` 直接比对（D-59 的往返性质）。
(defn rb/default-round-done-thunk
  []
  (when rb/default-round-done (rb/default-round-done)))

(defn rb/default-toolcall-thunk
  []
  (when rb/default-toolcall (rb/default-toolcall)))

(defn rb/default-approve-thunk
  []
  (when rb/default-approve (rb/default-approve)))

(defn rb/ws-default-hooks
  "缺省钩子表（= `default` 模式的内容）。"
  []
  @{"@RoundDone" @[rb/default-round-done-thunk]
    "@Toolcall" @[rb/default-toolcall-thunk]
    "@Approve" @[rb/default-approve-thunk]})

(defn rb/ws-new
  "新建一个工作区状态（REQ-30：字典 + 钩子 + 活 agent + 本轮 stream 列表）。
   栈不在这里——它是 env 的 `:rb-stack`（同一工作区的「变量」那半）。"
  []
  (def w @{:dict @{}
    :hooks (rb/ws-default-hooks)
    :mode "default"      # D-59：当前处理流程（模式）
    :mode-prompt nil     # 该模式要求注入的 system 提示（nil = 不注入）
    :flags (table/clone rb/flag-defaults)   # 历史标记开关（默认全开）
    :agents @[]
    :tools @{}     # REQ-48：工具表（名字 → 描述 + 引号）
    :plugins @{}   # REQ-60：插件台账（名字 → 装了哪些词/钩子/工具）
    :grants @[]    # REQ-69：临时授权（kind + key + 剩余次数；见 rb/tools.janet）
    :config @{}    # D-54：provider 配置（llm / llm-set / llm-get）
    :round @[]
    :round-rev 0   # 本轮列表的版本号（新建流 +1；收尾据此判断「还在变」）
    :watch @[]     # L9 被 watch 的视图流（REQ-28）
    :path nil      # 持久化目标（nil = 不落盘；REQ-20）
    :seq 0         # 已写入日志的记录数
    :snap-size 0    # 快照文件字节数（REQ-21 的 0.5 倍判据）
    :mode-tools @[]   # 当前模式装了哪些工具（D-61）
    :usage @{:prompt-tokens 0     # P2：provider 报的用量（累计）
             :completion-tokens 0
             :total-tokens 0
             :calls 0}})
  # D-61：能力层若提供默认工具包，就装进新工作区（--core-only 时这里没有能力，工具表为空）。
  # `:mode-tools` 记住「当前模式装了哪些工具」：切模式时先撤这批，再装新模式声明的那批，
  # 用户自己 `deftool` 的（不在这个名单里）不受影响。
  (def inst (rb/cap-get :tools/install))
  (when inst
    (inst (w :tools))
    (put w :mode-tools (tuple ;(sort (keys (w :tools))))))
  w)

(var rb/ws-default nil)

(defn rb/ws
  "取当前工作区状态（REQ-30：工作区 = 字典 + 栈 + 钩子/活 agent）。"
  []
  (def w (dyn :rb-ws))
  (if (nil? w)
    (do (when (nil? rb/ws-default) (set rb/ws-default (rb/ws-new)))
        rb/ws-default)
    w))

(defn rb/usage-add!
  "把一次 provider 报的用量累加进工作区（P2）。每调一次算一次请求。
   载荷形状：`{:prompt-tokens n :completion-tokens n :total-tokens n}`；
   字段缺了就跳过，不猜（不同 provider 只报一部分）。"
  [u]
  (def ws (rb/ws))
  (def acc (ws :usage))
  (when (not (and (table? u) (table? acc))) (break))
  (each [k f] [[:prompt-tokens "prompt_tokens"] [:completion-tokens "completion_tokens"]
               [:total-tokens "total_tokens"]]
    (def v (or (get u k) (get u f)))
    (when (number? v) (put acc k (+ (acc k) v))))
  # 一次元信息块 = 一次 provider 请求报的账（工具轮会有多次）
  (put acc :calls (inc (acc :calls)))
  acc)

(defn rb/usage-of
  "当前工作区的累计用量（一份拷贝，避免调用方改到内部表）。
   键是**字符串**：方言里没有关键字字面量（REQ-06），用 `at \"total-tokens\"` 才读得到。"
  []
  (def u ((rb/ws) :usage))
  (def out @{})
  (eachp [k v] u
    (put out (if (keyword? k) (string k) (string k)) v))
  out)

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
