# rb/modes.janet —— 处理流程（模式）的显式层（D-59 / D-72）
#
# 一个**模式**就是「一轮请求怎么被处理」的显式描述：
#
#   :name    模式名（工作区记住当前用的是哪个，历史标记也记它）
#   :doc     一句话说明（`modes` 打印用）
#   :hooks   8 个 `@` 事件上各自的钩子数组；**没声明的事件 = 空数组**
#   :flags   历史标记开关（`history-turn` / `history-origin` / `history-mode` / `plan`）
#   :prompt  发送前注入会话的 system 文本（nil = 不注入；支持 `{{model}}` / `{{cwd}}`）
#   :tools   应用模式时登记进工具表的条目
#   :wire    本轮**公示**给模型的工具名（nil = 公示全部；REQ-65 的呈现层）
#
# `:tools` 与 `:wire` 为什么分开：**注册 ≠ 公示**。PTC 模式的所有工具都注册着
# （程序里 `invoke` 得到），wire 上却只有 `eval`——这与 dsh 的 `mode: 'ptc'`
# （wire 上只有 `run_code`）是同一件事。v1.0m 之前把两者混在一起，导致 PTC
# 程序里什么工具都调不到（D-72 记了这次修正）。
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
  [name doc flags hooks &opt prompt tools wire]
  @{:kind :mode
    :name name
    :doc doc
    :flags (merge (table/clone rb/flag-defaults) (or flags @{}))
    :hooks (rb/mode-hooks hooks)
    :prompt prompt
    :tools (or tools @{})
    :wire (if (nil? wire) nil (tuple ;wire))})

# ---- 历史标记开关 --------------------------------------------------------

(defn rb/flag-get
  "Key -- Bool；读一个开关（未定义 = nil）。"
  [k]
  (get ((rb/ws) :flags) k))

(defn rb/flag-env-name
  "开关名 → 环境变量名：`allow-shell` → `RB_ALLOW_SHELL`。
   janet 1.42 没有 `string/upper`，这里手工做大写（只影响 ASCII，足够）。"
  [k]
  (def out @"RB_")
  (each b (string/bytes k)
    (cond
      (and (>= b 97) (<= b 122)) (buffer/push-byte out (- b 32))
      (= b 45) (buffer/push-byte out 95)
      true (buffer/push-byte out b)))
  (string out))

(defn rb/flag-env
  "开关的同名环境变量覆盖（`allow-shell` → `RB_ALLOW_SHELL`）：
   true / false / nil（没设）。环境变量压过工作区设定——它的用途是
   「这台机器上无论如何都……」；模式设定则管缺省（REQ-67）。"
  [k]
  (def v (os/getenv (rb/flag-env-name k)))
  (cond
    (nil? v) nil
    (= v "") nil            # 空串 = 没设（`RB_ALLOW_SHELL=` 不该等于「关」）
    (or (= v "0") (= v "no") (= v "false")) false
    (or (= v "1") (= v "yes") (= v "true")) true
    true))   # 其它非空值一律当「开」（RB_ALLOW_SHELL=whatever 的直觉）

(defn rb/flag-on?
  "开关此刻是否生效：环境变量优先，其次工作区开关（`nil` = 没定义 = 关）。"
  [k]
  (def env (rb/flag-env k))
  (if (nil? env) (= true (rb/flag-get k)) env))

(defn rb/flag-set!
  "Value Key --；写一个开关（值必须是布尔，否则 31）。"
  [k v]
  (when (not (or (boolean? v) (nil? v)))
    (rb/raise (rb/exit-table :runtime-type)
              (string "开关的值必须是布尔，得到 " (type v))))
  (put ((rb/ws) :flags) k v)
  nil)

# ---- plan 模式（dsh 的 plan mode：正交于预置，靠提示约束而非工具限制）------

(def rb/plan-section
  (string
    "## plan 模式\n"
    "You are in plan mode. Stay in plan mode until the user approves the plan through "
    "exit_plan_mode, or leaves plan mode.\n"
    "只做观察与设计：可以 read / glob / grep / shell 去看，**不要** edit / write 文件，"
    "不要改配置，不要提交。\n"
    "Explore first: resolve discoverable facts by inspection instead of asking.\n"
    "需要用户裁决的取舍，直接问，不要自己猜。\n"
    "Make the plan decision-complete: 目标与成功标准；按子系统分组的改动（依赖顺序）；"
    "测试与验收；显式假设与风险。\n"
    "When ready, call exit_plan_mode with the complete plan as markdown starting with a "
    "`#` title — as the only and final tool call in that response."))

(defn rb/mode-arg
  "从工具参数里取一个键（JSON 解码后的表可能用字符串键，也可能用关键字键）。"
  [args k]
  (if (table? args)
    (let [a (get args k) b (get args (keyword k))]
      (if (nil? a) b a))
    nil))

(defn rb/exit-plan-mode
  "plan 模式的 `exit_plan_mode` 工具本体：交出计划并关掉 plan 开关（dsh 同名工具）。"
  []
  (def args (rb/pop))
  (def plan (rb/mode-arg args "plan"))
  (when (not (rb/flag-get "plan"))
    (rb/raise (rb/exit-table :orchestration-base)
              "exit_plan_mode：当前不在 plan 模式（先 enter-plan）"))
  (when (not (string? plan))
    (rb/raise (rb/exit-table :runtime-type)
              "exit_plan_mode 需要一个 {\"plan\": \"<markdown>\"} 参数"))
  (rb/flag-set! "plan" false)
  (rb/push (string "计划已提交，已退出 plan 模式：\n\n" plan))
  nil)

(defn rb/enter-plan!
  "打开 plan 开关，并登记 `exit_plan_mode`（渐进披露：wire 上只在此后出现）。"
  []
  (rb/tool-register! "exit_plan_mode"
                     (string "提交计划并退出 plan 模式：参数 { \"plan\": \"<markdown>\" }；"
                             "plan 以 `#` 标题开头，是本次响应的**唯一且最后**一次工具调用。")
                     rb/exit-plan-mode)
  (rb/flag-set! "plan" true)
  nil)

(defn rb/exit-plan!
  "关掉 plan 开关（`exit_plan_mode` 之外的手动出口，同 dsh 的 `/plan off`）。"
  []
  (rb/flag-set! "plan" false)
  nil)

# ---- 预制模式 ------------------------------------------------------------
#
# 五个模式：`default`（本仓最小缺省）+ `standard` / `ptc` / `minimal` / `cordis`
# （后四个是 dsh `packages/bundle/web-app/presets/*.patch.yml` 的复刻，D-72）。
# 复刻取舍见 docs/DECISIONS.md D-72：web / jobs / schedule / subagent / todo
# 不复制（核心不含网络，子代理在本方言里是语言级的 agent/send，比工具更自然）。

(def rb/standard-system
  (string
    "You are a coding agent powered by the {{model}} model.\n"
    "工作目录：{{cwd}}。\n"
    "先用 read / glob / grep 看清楚再改；改动要小，风格跟随周围代码。"
    "shell 可用，但它绕过文件沙箱，能不用就不用。"))

(def rb/minimal-system
  # dsh 的 minimal 用 `complete: true` + `includeRuntimeContext: false`：
  # 这段就是**全部**系统提示（不拼 {{cwd}}、不拼工具说明）。
  "You are a helpful software engineer assistant.")

(def rb/cordis-system
  (string
    rb/standard-system "\n"
    "你可以修改自己：plug 装插件（.breve）、unplug 卸插件、plugins 看台账、"
    "mode 换处理流程；skills/ 下是技能说明，用 read 读。"))

(def rb/ptc-system
  (string
    "PTC 模式（仿 DeepSeek harness 的 Programmatic Tool Calling）："
    "不要发出 tool_call。改用工具 eval 提交一段 ravel breve 程序——"
    "程序里可以用 `invoke \"<工具名>\" { … }` 调用任何已注册的工具。"
    "一行一条语句，前缀式书写（最左实参先被消费）；程序执行完的栈顶就是工具结果。"
    "在本轮结束前只调一次 eval，把「要几次往返才问得清」的活儿写进程序里。"))

(defn rb/ptc-eval
  "PTC 模式的 `eval` 工具本体：把 `src` 当成 ravel 程序执行，返回栈顶（JSON 可编码化）。"
  []
  (def src (rb/mode-arg (rb/pop) "src"))
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

# cordis 的 `plugin` 工具：插件层在 modes 之后装载，故走间接层（D-29）。
(var rb/mode-plugin-load nil)

(defn rb/tool-plugin
  "cordis 模式的 `plugin` 工具：把一份 .breve 插件装进工作区（REQ-60）。"
  []
  (def path (rb/mode-arg (rb/pop) "path"))
  (when (not (string? path))
    (rb/raise (rb/exit-table :runtime-type)
              "plugin 工具需要一个 {\"path\": \"…\"} 参数"))
  (when (nil? rb/mode-plugin-load)
    (rb/raise (rb/exit-table :orchestration-base)
              "插件层未装载（--core-only？REQ-60）"))
  (def name (rb/mode-plugin-load path))
  (rb/push (string "已装插件：" name))
  nil)

(defn rb/cap-default-tools
  "能力层提供的默认工具表（`--core-only` 时没有能力 → 空表）。
   与 `ws-new` 装的是同一批函数对象，故模式 round-trip 可用 `deep=` 比。"
  []
  (def f (rb/cap-get :tools/defaults))
  (if f (f) @{}))

(defn rb/tool-gates
  "能力层提供的「工具 → 前置开关」表（`--core-only` 下为空表）。
   目前只有 shell，前置设定是 allow-shell（REQ-67）。"
  []
  (def f (rb/cap-get :tools/gates))
  (if f (f) @{}))

(defn rb/gate-open?
  "这个工具此刻能不能用：没有前置设定 → 能；有 → 看那个开关是否生效（REQ-67）。"
  [name]
  (def g (get (rb/tool-gates) name))
  (if g (rb/flag-on? g) true))

(defn rb/mode-tools-of
  "从默认工具表里挑出若干名字（模式只装自己需要的工具；缺的名字自动跳过）。"
  [names]
  (def all (rb/cap-default-tools))
  (def out @{})
  (each n names
    (def d (get all n))
    (when d (put out n d)))
  out)

(defn rb/mode-presets
  "预制模式表：名字 → 模式。`default` 的钩子对象与 `ws-new` 完全同一批。"
  []
  @{"default"
    (rb/mode-new
      "default"
      "缺省：收尾钩子把流合并进会话，工具调用自动执行（REQ-18 / REQ-48）"
      @{"allow-shell" true}
      (rb/ws-default-hooks)
      nil
      (rb/cap-default-tools))

    "ptc"
    (rb/mode-new
      "ptc"
      "dsh preset ptc 的复刻：wire 上只有 eval（呈现层），程序里 invoke 任何工具"
      @{"allow-shell" true}
      @{"@RoundDone" @[rb/default-round-done-thunk]
        "@Toolcall" @[rb/default-toolcall-thunk]}
      rb/ptc-system
      (merge (table/clone (rb/cap-default-tools))
             @{"eval" @{:desc (string "执行一段 ravel breve 程序并返回栈顶。参数 {"
                                      "\"src\": \"<程序>\"}；程序里可用 invoke \"工具名\" { … }。")
                        :fn rb/ptc-eval}})
      @["eval"])

    "standard"
    (rb/mode-new
      "standard"
      "dsh preset standard 的复刻：编码 agent 的人格 + 完整文件工具 + shell"
      @{"allow-shell" true}
      (rb/ws-default-hooks)
      rb/standard-system
      (rb/cap-default-tools))

    "minimal"
    (rb/mode-new
      "minimal"
      "dsh preset minimal 的复刻：只有 shell；人格是完整系统提示，不带运行时上下文"
      @{"allow-shell" true}
      (rb/ws-default-hooks)
      rb/minimal-system
      (rb/mode-tools-of @["shell"]))

    "cordis"
    (rb/mode-new
      "cordis"
      "dsh preset cordis 的复刻：standard + 改自己（plugin 工具装卸插件）"
      @{"allow-shell" true}
      (rb/ws-default-hooks)
      rb/cordis-system
      (merge (table/clone (rb/cap-default-tools))
             @{"plugin" @{:desc (string "装插件：参数 { \"path\": \"<.breve>\" }；"
                                      "插件里的词/钩子/工具进本工作区（REQ-60）。")
                          :fn rb/tool-plugin}}))})

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
  "模式 → 现状：整体替换钩子表，写 flags / prompt / wire，撤掉预制工具后装本模式声明的工具。"
  [m]
  (when (not (and (table? m) (= (m :kind) :mode)))
    (rb/raise (rb/exit-table :runtime-type)
              (string "需要一个模式，得到 " (type m))))
  (def ws (rb/ws))
  (put ws :hooks (rb/mode-hooks (m :hooks)))
  (put ws :mode (m :name))
  (put ws :mode-prompt (m :prompt))
  (put ws :mode-wire (m :wire))
  (def fl (ws :flags))
  (eachp [k v] (m :flags) (put fl k v))
  (def tools (ws :tools))
  # 只撤「上一个模式装的」那批：用户自己 deftool 的工具（如 PTC 程序里要 invoke 的）留着
  (each n (ws :mode-tools) (put tools n nil))
  (eachp [n d] (m :tools) (put tools n d))
  (put ws :mode-tools (tuple ;(sort (keys (m :tools)))))
  # 「模式的工具与设定必须自洽」（REQ-67）：声明了带前置设定的工具，却没把它打开，
  # 就是"看得见却一调就失败"。这里只**告警**（用户可能正想临时关掉），并把话说清。
  (eachp [n _] (m :tools)
    (def g (get (rb/tool-gates) n))
    (when (and g (not (get (m :flags) g)))
      (eprintf "ravel: 警告：模式 %s 声明了工具 %s，但设定里没有 %s → 该工具本轮不会公示，invoke 会 60（REQ-67）"
               (m :name) n g)))
  m)

(defn rb/mode-capture
  "现状 → 模式：把当前工作区的钩子、标记开关、提示、工具与呈现层导出成一张模式表。
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
    :tools (table/clone (ws :tools))
    :wire (ws :mode-wire)})

# ---- 提示组装 ------------------------------------------------------------

(defn rb/prompt-subst
  "把 `{{model}}` / `{{cwd}}` 换成当前值（dsh 的 persona 模板照抄）：
   提示每轮现拼，所以换模型/换目录立刻生效，不用重建模式。"
  [text]
  (def cfg ((rb/ws) :config))
  # 三级回落：工作区配置 → 环境变量 → 一个中性的名字（提示里不该出现 nil）
  (def model (or (get cfg "model") (os/getenv "RB_MODEL") "ravel breve"))
  # 注意用 ->>（`string/replace-all` 的签名是 patt subst str，str 在**最后**）
  (->> text
       (string/replace-all "{{model}}" model)
       (string/replace-all "{{cwd}}" (os/cwd))))

(defn rb/hidden-tools
  "注册了但**没**上 wire 的工具名（升序数组）。PTC 模式下就是全部工具。"
  []
  (def ws (rb/ws))
  (def t (ws :tools))
  (def w (ws :mode-wire))
  (def shown @[])
  (when w (each n (if (string? w) (tuple w) w) (array/push shown n)))
  (def out @[])
  (each n (sort (keys t))
    (var vis false)
    (each x shown (when (= x n) (set vis true)))
    (when (and (not vis) (not= n "exit_plan_mode")) (array/push out n)))
  out)

(defn rb/wire-sdk
  "把「wire 上看不见、程序里照样能调」的工具写成一段提示（dsh 的 `tools:sdk` 段）。
   只有声明了 `:wire` 的模式才需要它；没有隐藏工具 → 空串。"
  []
  (def hidden (rb/hidden-tools))
  (if (empty? hidden)
    ""
    (do
      (def out @["程序里可以直接用的工具（wire 上没有它们，但都已注册）："])
      (each n hidden
        (def d (rb/tool-get n))
        (array/push out (string "- " n "：" (d :desc))))
      (array/push out "调用形式：`invoke \"名字\" { \"参数\" 值 }`；一行一条语句。")
      (string/join out "\n"))))

(defn rb/mode-prompt-of
  "把一个模式的提示拼成「本轮真的发出去的 system 文本」：
   人格（`{{model}}`/`{{cwd}}` 代入）+ 隐藏工具的绑定清单 + plan 段落。"
  [m]
  (def parts @[])
  (when (m :prompt) (array/push parts (rb/prompt-subst (m :prompt))))
  (when (m :wire) (def s (rb/wire-sdk)) (when (not (empty? s)) (array/push parts s)))
  (when (rb/flag-get "plan") (array/push parts rb/plan-section))
  (if (empty? parts) nil (string/join parts "\n\n")))

(defn rb/mode-inject-prompt!
  "取「本轮请求要前置的 system 提示」（default 模式 = nil）。
   提示只进**请求**，不进会话历史——否则历史会被模式的说明文字污染，
   而且切换模式后旧提示还留在里面（D-59）。
   由 `rb/stream-start` 经间接层调用（装载序：agent 先于 modes，D-29）。"
  [a]
  (def p (rb/mode-prompt-of (rb/mode-capture)))
  (put a :mode-prompt p)
  p)

(set rb/mode-inject-prompt rb/mode-inject-prompt!)

# 装载序：`rb/tools.janet`（13）先于本文件（29），所以呈现层经间接层取这个判定（D-29）。
(set rb/tool-open? rb/gate-open?)
