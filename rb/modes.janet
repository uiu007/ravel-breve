# rb/modes.janet —— 处理流程（模式）的显式层（D-59）
#
# 一个**模式**就是「一轮请求怎么被处理」的显式描述：
#
#   :name    模式名（工作区记住当前用的是哪个，历史标记也记它）
#   :doc     一句话说明（`modes` 打印用）
#   :hooks   8 个 `@` 事件上各自的钩子数组；**没声明的事件 = 空数组**
#   :flags   历史标记开关（`history-turn` / `history-origin` / `history-mode`）
#   :prompt  发送前注入会话的 system 文本（nil = 不注入）
#   :tools   应用模式时登记进工具表的条目（PTC 模式的 `eval`）
#
# 与钩子是**双向**关系（用户要求的「互相转换」）：
#
#   (mode "ptc")   模式 → 现状：把该模式的钩子/开关/工具/提示装进工作区
#   (mode-of)      现状 → 模式：把当前工作区的钩子与开关导出成模式表
#
# 于是「显式流程」与「钩子实现」是同一件事的两个视图：预置模式导出的表与
# 预置本身 `deep=` 相等（同一批函数对象，见 rb/events.janet 的 `ws-default-hooks`），
# 用户 `@on` 出来的钩子也能被 `mode-of` 收成一份可再 `mode` 回去的模式。

(def rb/mode-events
  @["@Start" "@Chunk" "@Fail" "@Error" "@Close" "@Toolcall" "@Done" "@RoundDone"])

(defn rb/mode-hooks-empty
  "8 个事件齐全、每个都是空数组的钩子表（模式的规范形状）。"
  []
  (def h @{})
  (each e rb/mode-events (put h e @[]))
  h)

(defn rb/mode-hooks
  "把「部分事件 → 钩子序列」补成规范形状（缺的事件 = 空数组）。"
  [partial]
  (def h (rb/mode-hooks-empty))
  (when (table? partial)
    (each e rb/mode-events
      (def arr (get partial e))
      (when arr (each q arr (array/push (h e) q)))))
  h)

(defn rb/mode-new
  "构造一个模式表（不装进工作区）。"
  [name doc flags hooks &opt prompt tools]
  @{:kind :mode
    :name name
    :doc doc
    :flags (merge (table/clone rb/flag-defaults) (or flags @{}))
    :hooks (rb/mode-hooks hooks)
    :prompt prompt
    :tools (or tools @{})})

# ---- 预制模式 ------------------------------------------------------------

(def rb/ptc-system
  (string
    "PTC 模式（仿 DeepSeek harness 的 Programmatic Tool Calling）："
    "不要发出 tool_call。改用工具 eval 提交一段 ravel breve 程序——"
    "程序里可以用 `invoke \"<工具名>\" { … }` 调用任何已注册的工具。"
    "一行一条语句，前缀式书写（最左实参先被消费）；程序执行完的栈顶就是工具结果。"))

(defn rb/ptc-arg
  "从工具参数里取一个键（JSON 解码后的表可能用字符串键，也可能用关键字键）。"
  [args k]
  (if (table? args)
    (let [a (get args k) b (get args (keyword k))]
      (if (nil? a) b a))
    nil))

(defn rb/ptc-eval
  "PTC 模式的 `eval` 工具本体：把 `src` 当成 ravel 程序执行，返回栈顶（JSON 可编码化）。"
  []
  (def src (rb/ptc-arg (rb/pop) "src"))
  (when (not (string? src))
    (rb/raise (rb/exit-table :runtime-type)
              "eval 工具需要一个 {\"src\": \"…\"} 参数（D-59）"))
  (def env ((rb/ws) :env))
  (when (nil? env)
    (rb/raise (rb/exit-table :orchestration-base)
              "PTC 模式需要活动的工作区环境（D-59）"))
  (def d0 (length (env :rb-stack)))
  (def r (rb/run-source src "ptc" env true))   # nested? = 不做一轮收尾
  (when (not (r :ok))
    (rb/raise (if (rb/rb-error? (r :error))
                (get (r :error) :rb-code)
                (rb/exit-table :orchestration-base))
              (string "eval 失败：" (rb/error-msg (r :error)))))
  (def st (env :rb-stack))
  (def top (if (> (length st) d0) (array/peek st) nil))
  (rb/stack-truncate d0)
  # 工具体的契约（REQ-48）：**把结果留在栈上**，由 `rb/tool-run` 取栈顶。
  (rb/push
    (cond
      (nil? top) ""
      (or (string? top) (number? top) (boolean? top) (tuple? top) (array? top) (struct? top)
          (table? top)) top
      (string top)))
  nil)

(defn rb/cap-default-tools
  "能力层提供的默认工具表（`--core-only` 时没有能力 → 空表）。
   与 `ws-new` 装的是同一批函数对象，故模式 round-trip 可用 `deep=` 比。"
  []
  (def f (rb/cap-get :tools/defaults))
  (if f (f) @{}))

(defn rb/mode-presets
  "预制模式表：名字 → 模式。`default` 的钩子对象与 `ws-new` 完全同一批。"
  []
  @{"default"
    (rb/mode-new
      "default"
      "缺省：收尾钩子把流合并进会话，工具调用自动执行（REQ-18 / REQ-48）"
      nil
      (rb/ws-default-hooks)
      nil
      (rb/cap-default-tools))

    "ptc"
    (rb/mode-new
      "ptc"
      "仿 DeepSeek harness 的 PTC：模型提交程序，程序里 invoke 工具；只有一个 eval 工具"
      nil
      @{"@RoundDone" @[rb/default-round-done-thunk]
        "@Toolcall" @[rb/default-toolcall-thunk]}
      rb/ptc-system
      @{"eval" @{:desc (string "执行一段 ravel breve 程序并返回栈顶。参数 {"
                             "\"src\": \"<程序>\"}；程序里可用 invoke \"工具名\" { … }。")
                 :fn rb/ptc-eval}})})
(defn rb/mode-preset-tools
  "所有预制模式声明过的工具名（切换模式时先撤掉它们，避免模式互相污染）。"
  []
  (def names @[])
  (eachp [n m] (rb/mode-presets)
    (each k (keys (m :tools))
      (var seen false)
      (each x names (when (= x k) (set seen true)))
      (when (not seen) (array/push names k))))
  names)

# ---- 模式 ⇄ 钩子 --------------------------------------------------------

(defn rb/mode-get
  "按名字取预制模式；未知 → nil。"
  [name]
  (get (rb/mode-presets) name))

(defn rb/mode-apply!
  "模式 → 现状：整体替换钩子表，写 flags / prompt，撤掉预制工具后装本模式声明的工具。"
  [m]
  (when (not (and (table? m) (= (m :kind) :mode)))
    (rb/raise (rb/exit-table :runtime-type)
              (string "需要一个模式，得到 " (type m))))
  (def ws (rb/ws))
  (put ws :hooks (rb/mode-hooks (m :hooks)))
  (put ws :mode (m :name))
  (put ws :mode-prompt (m :prompt))
  (def fl (ws :flags))
  (eachp [k v] (m :flags) (put fl k v))
  (def tools (ws :tools))
  # 只撤「上一个模式装的」那批：用户自己 deftool 的工具（如 PTC 程序里要 invoke 的）留着
  (each n (ws :mode-tools) (put tools n nil))
  (eachp [n d] (m :tools) (put tools n d))
  (put ws :mode-tools (tuple ;(sort (keys (m :tools)))))
  m)

(defn rb/mode-capture
  "现状 → 模式：把当前工作区的钩子、标记开关、提示与工具导出成一张模式表。
   对预置模式之后的工作区，导出的表与原预置 `deep=` 相等。"
  []
  (def ws (rb/ws))
  (def name (or (ws :mode) "captured"))
  (def p (rb/mode-get name))
  @{:kind :mode
    :name name
    :doc (if p (p :doc) "")
    :flags (table/clone (ws :flags))
    :hooks (rb/mode-hooks (ws :hooks))
    :prompt (ws :mode-prompt)
    :tools (table/clone (ws :tools))})

(defn rb/mode-inject-prompt!
  "取「本轮请求要前置的 system 提示」（默认模式 = nil）。
   提示只进**请求**，不进会话历史——否则历史会被模式的说明文字污染，
   而且切换模式后旧提示还留在里面（D-59）。
   由 `rb/stream-start` 经间接层调用（装载序：agent 先于 modes，D-29）。"
  [a]
  (def p ((rb/ws) :mode-prompt))
  (put a :mode-prompt p)
  p)

(set rb/mode-inject-prompt rb/mode-inject-prompt!)

# ---- 历史标记开关 --------------------------------------------------------

(defn rb/flag-get
  "Key -- Bool；读一个开关（未定义 = nil）。"
  [k]
  (get ((rb/ws) :flags) k))

(defn rb/flag-set!
  "Value Key --；写一个开关（值必须是布尔，否则 31）。"
  [k v]
  (when (not (or (boolean? v) (nil? v)))
    (rb/raise (rb/exit-table :runtime-type)
              (string "开关的值必须是布尔，得到 " (type v))))
  (put ((rb/ws) :flags) k v)
  nil)
