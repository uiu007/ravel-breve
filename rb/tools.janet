# rb/tools.janet —— 工具调用（REQ-48）
#
# 工具是**工作区里的表项**（`名字 → { :desc , :fn }`），与字典、钩子、栈同寿命。
# 模型侧契约：
#   `send` 时把工具表转成 provider 的 `tools`；
#   模型返回 `tool_calls` 时 ① 发 `@Toolcall`（载荷 `Call Stream`）
#   ② 本轮未完成 ③ 工具结果以 role "tool" 追加 ④ 自动重发，**同一个流**继续吐文本。
#
# 自动执行是 `@Toolcall` 上的**默认钩子**（与 REQ-18 的 `@RoundDone` 默认钩子同构）：
# `@off @Toolcall` 之后流停在 `:tool`（待外部动作），本轮不算完成。

(defn rb/tool-get
  "按名字取工具表项；不存在返回 nil。"
  [name]
  (get ((rb/ws) :tools) name))

(defn rb/tool-register!
  "注册/覆盖一个工具（REQ-48 的 `deftool`）。
   第四个参数可选：给模型的**参数模式**（JSON Schema，REQ-68）；缺省 = 不写形状。"
  [name desc fn &opt params]
  (put ((rb/ws) :tools) name (if params
                               @{:desc desc :fn fn :params params}
                               @{:desc desc :fn fn}))
  nil)

(defn rb/tool-names
  "工作区工具表里注册过的工具名（升序元组）。"
  []
  (tuple ;(sort (keys ((rb/ws) :tools)))))

(var rb/tool-open? nil)   # 前置设定判定（rb/modes.janet 定义后经间接层装上，D-29 / REQ-67）

(defn rb/tool-wire
  "本轮**公示**给模型的工具名（升序元组；纯函数式的呈现层，REQ-65）。

   为什么需要它：注册（能 `invoke`）与公示（模型看得见）是两件事——
   dsh 的 PTC 就是这么做的（wire 上只有 `run_code`，程序里能调全部工具）。
   - 模式声明了 `:wire` → 只公示这些（不在工具表里的忽略）；
   - 没声明 → 公示全部注册的；
   - `plan` 开关打开时追加 `exit_plan_mode`（渐进披露，同 dsh）。"
  []
  (def ws (rb/ws))
  (def t (ws :tools))
  (def w (ws :mode-wire))
  (def names @[])
  (if (nil? w)
    (each n (keys t) (array/push names n))
    (each n (if (string? w) (tuple w) w)
      (when (get t n) (array/push names n))))
  (when (and (get (ws :flags) "plan") (get t "exit_plan_mode"))
    (var seen false)
    (each n names (when (= n "exit_plan_mode") (set seen true)))
    (when (not seen) (array/push names "exit_plan_mode")))
  # 前置设定不满足的工具**不上 wire**（REQ-67）：模型看不见就不会去调，
  # 于是不会在回合中途冒出「工具失败」。注册表里它还在（invoke 会给出清楚的 60）。
  (tuple
    ;(sort
       (filter (fn [n]
                 (if rb/tool-open? (rb/tool-open? n) true))
               names))))

(defn rb/tool-defs
  "工具表 → provider 的 `tools` 数组；表空则为 nil（请求里不带该字段）。
   只公示 `rb/tool-wire` 认可的条目（REQ-65 的呈现层）。"
  []
  (def names (rb/tool-wire))
  (if (empty? names)
    nil
    (do
      (def out @[])
      (each name names
        (def d (rb/tool-get name))
        (array/push out
                    @{:type "function"
                      :function @{:name name
                                  :description (d :desc)
                                  # 参数**模式**要写真（REQ-68）：空壳 `additionalProperties`
                                  # 等于让模型猜参数名，猜错就报废一整轮。
                                  :parameters (or (d :params)
                                                  @{:type "object"
                                                    :additionalProperties true})}}))
      (tuple ;out))))

(defn rb/tool-arg-fail
  "抛一个**参数错误**（REQ-68）：带 `:rb-arg` 标记。
   为什么单独一类：参数名写错是**模型的手误**，把整轮以 60 报废太贵——
   工具循环会把它当成 `role \"tool\"` 的结果回给模型（模型能自己改），
   而 `invoke`/脚本路径仍按编排级 60 报错（没人替程序员改）。"
  [msg &opt name]
  (error @{:rb-code (rb/exit-table :orchestration-base)
           :rb-msg msg
           :rb-tool name
           :rb-arg true}))

(defn rb/tool-run
  "调用工具本体：`args` 压栈 → 运引号 → 取栈顶为结果，栈回到调用前深度。
   未注册 / 本体失败 → 60（编排级，REQ-48）；参数错误带 `:rb-arg`（REQ-68）。"
  [name args]
  (def d (rb/tool-get name))
  (when (nil? d)
    (rb/tool-arg-fail (string "未注册的工具：" name "（先 deftool 注册，REQ-48；名字或参数见工具定义）")
                      name))
  (def body (d :fn))
  (when (not (function? body))
    (rb/raise (rb/exit-table :orchestration-base)
              (string "工具的体必须是引号：" name)))
  (def d0 (length (rb/stack)))
  (rb/push args)
  (def p (protect (body)))
  (def ok (get p 0))
  (def v (get p 1))
  (def top (if (> (length (rb/stack)) d0) (array/peek (rb/stack)) nil))
  (rb/stack-truncate d0)
  (if ok
    top
    (cond
      (and (dictionary? v) (get v :rb-arg))
      (rb/tool-arg-fail (string "工具失败：" name "：" (rb/error-msg v)) name)

      # REQ-69：策略拒绝（沙箱/授权）带着「请求表」上送，交给审批层决定，而不是就地 60。
      (and (dictionary? v) (get v :rb-denied))
      (error @{:rb-code (rb/exit-table :orchestration-base)
               :rb-msg (string "工具失败：" name "：" (rb/error-msg v))
               :rb-denied true
               :rb-request (get v :rb-request)})

      true
      (rb/raise (rb/exit-table :orchestration-base)
                (string "工具失败：" name "：" (rb/error-msg v))))))

(defn rb/tool-encode
  "工具结果 → 追加进会话的 `tool` 消息内容（JSON 文本，经能力层）。"
  [v]
  (def enc (rb/cap-get :json/encode))
  (if (nil? enc)
    (string v)
    (enc v)))

(defn rb/tool-call-new
  "把 provider 交来的一条调用规整成内部结构。"
  [a call]
  @{:kind :tool-call
    :id (or (get call :id) "")
    :name (string (get call :name))
    :arguments (get call :arguments)
    :raw (get call :raw)
    :agent a
    :stream nil
    :done false})

# ---- 临时授权与审批（REQ-69 / D-75）-------------------------------------
#
# 策略拒绝（沙箱最典型）原来是一整轮的死刑：`@RoundDone 失败：…沙箱拒绝…`。
# 但「越界读一个文件」常常只是**需要人点一次头**，不是错误。于是：
#
#   工具被策略拒绝 → 发 `@Approve`（载荷 `Request Stream`）→ 钩子填
#   `:decision`（`:allow` / `:deny`）与 `:grant`（`kind` + `key` + `uses`）
#   → 允许就登记一条**临时**授权，然后**重试一次**；拒绝就照旧 60。
#
# 核心**不认识** `kind` 的语义：能力层自己来查（`cap/fs-check` 查 `"fs"`）。
# 授权是临时的：`uses` 有限 = 只用 N 次；`nil` = 到本工作区结束（`reset` 就没了）。

(defn rb/grant-match?
  "授权是否覆盖这个键：相等，或键在「授权的路径 + /」之下（按段对齐，`/a/b` 不覆盖 `/a/bc`）。"
  [key k]
  (or (= k key)
      (and (string? k) (string? key) (string/has-prefix? (string key "/") k))))

(defn rb/grant-add!
  "登记一条临时授权（`uses` = nil 表示到工作区结束；数字 = 还能用几次）。"
  [kind key &opt uses]
  (def g @{:kind kind :key key :uses uses})
  (array/push ((rb/ws) :grants) g)
  g)

(defn rb/grant-find
  "找一条覆盖 `key` 的授权（**只查不扣**）。没有 → nil。

   为什么不在这里扣：一次工具调用会查好几次（工具自己查一遍、能力函数再查一遍），
   按「查」扣的话，`uses = 1` 的授权连一次调用都撑不过。计数按**工具调用**扣，
   扣的地方在 `rb/tool-approve` 的重试收尾（`rb/grant-consume!`）。"
  [kind key]
  (var found nil)
  (each g ((rb/ws) :grants)
    (when (and (nil? found) (= kind (g :kind)) (rb/grant-match? (g :key) key))
      (set found g)))
  found)

(defn rb/grant-consume!
  "扣掉一条授权的**一次**用量（`uses` 用完即销）；`uses` 为 nil 的不动。返回扣掉的条数。"
  [kind key]
  (def ws (rb/ws))
  (def gs (ws :grants))
  (var n 0)
  (each g (array/slice gs)
    (when (and (= kind (g :kind)) (= key (g :key)) (number? (g :uses)))
      (if (<= (g :uses) 1)
        (do
          (def keep @[])
          (each x gs (when (not (= x g)) (array/push keep x)))
          (put ws :grants keep))
        (put g :uses (dec (g :uses))))
      (++ n)))
  n)

(defn rb/grants-of
  "当前授权的一份拷贝（方言词 `grants` 用）。"
  []
  (tuple ;(map (fn [g] (table/clone g)) ((rb/ws) :grants))))

(defn rb/grant-clear!
  "撤掉所有临时授权，返回撤掉的条数。"
  []
  (def ws (rb/ws))
  (def n (length (ws :grants)))
  (put ws :grants @[])
  n)

(defn rb/approve-tty?
  "有没有可交互的终端（没有就只能拒绝：脚本里要跨目录就预先 `grant` 或设 RB_SANDBOX）。"
  []
  (def t (dyn :rb-term))
  (if t (not (not (t :tty))) false))

(defn rb/approve-ask
  "问一次：`y` 只这一次 / `d` 这个目录（到工作区结束）/ 其它 = 拒绝。"
  [req]
  (def path (or (req :path) (req :key) "?"))
  (def dir (or (req :dir) path))
  (file/write stderr (string "\nravel: 审批：" (or (req :tool) "工具") " 想访问沙箱外的 " path "\n"
                             "       沙箱根 = " (req :root) "\n"
                             "       [y] 只这一次   [d] 这个目录（" dir "，到本工作区结束）"
                             "   [回车] 拒绝\n"
                             "   > "))
  (file/flush stderr)
  (def line (protect (file/read stdin :line)))
  # 注意：`file/read … :line` 成功时给的是 **buffer**，不是 string（Janet 1.42）
  (def ans (if (and (get line 0) (not (nil? (get line 1))))
             (string/trim (string (get line 1)))
             ""))
  (cond
    (or (= ans "y") (= ans "Y") (= ans "yes"))
    @{:decision :allow :grant @{:kind (req :kind) :key path :uses 1}}
    (or (= ans "d") (= ans "D") (= ans "dir"))
    @{:decision :allow :grant @{:kind (req :kind) :key dir}}
    @{:decision :deny
      :msg (string "已拒绝：" path "（要长期允许：grant \"" (req :kind) "\" \"" dir "\"）")}))

(defn rb/default-approve-hook
  "默认 `@Approve` 钩子：**问人**。非交互（管道 / `--serve` / 测试）→ 拒绝并说明怎么预先授权。"
  []
  (def req (rb/pop))
  (when (table? req)
    (if (rb/approve-tty?)
      (do
        (def d (protect (rb/approve-ask req)))
        (if (get d 0)
          (eachp [k v] (get d 1) (put req k v))
          (do (put req :decision :deny)
              (put req :msg (string "审批失败：" (rb/error-msg (get d 1)))))))
      (do
        (put req :decision :deny)
        (put req :msg (string "非交互环境不能审批：" (or (req :path) "?")
                             "；预先授权用 grant \"" (req :kind) "\" \""
                             (or (req :dir) (req :path)) "\"，或设 RB_SANDBOX=none（D-60）")))))
  nil)

(defn rb/tool-approve
  "遇到策略拒绝时的一次审批：发 `@Approve`，允许则登记授权并重试**一次**。
   返回 `[ok 值]`（与 `protect` 同形）；拒绝则原样返回第一次的失败。"
  [call v]
  (def req (if (and (dictionary? v) (get v :rb-request)) (get v :rb-request)))
  (if (nil? req)
    [false v]
    (do
      (put req :tool (call :name))
      (put req :decision nil)
      (rb/emit "@Approve" [req (call :stream)])
      (if (not= (req :decision) :allow)
        (do
          # 拒绝：错误消息换成审批给的那句（点名怎么预先授权），退出码照旧
          [false @{:rb-code (if (rb/rb-error? v) (v :rb-code) (rb/exit-table :orchestration-base))
                   :rb-msg (or (req :msg) (if (rb/rb-error? v) (v :rb-msg) (rb/error-msg v)))}])
        (do
          (def g (req :grant))
          (when (table? g) (rb/grant-add! (g :kind) (g :key) (g :uses)))
          (def p (protect (rb/tool-run (call :name) (call :arguments))))
          # 扣一次用量（`uses = 1` 的授权在这次重试后就没了）
          (when (and (table? g) (number? (g :uses)))
            (rb/grant-consume! (g :kind) (g :key)))
          p)))))

(defn rb/default-toolcall-hook
  "默认 `@Toolcall` 钩子：**自动执行**工具并把结果追加进会话。
   载荷 `Call Stream` → 栈顶是 `Call`。"
  []
  (def call (rb/pop))
  (when (= (call :kind) :tool-call)
    (def a (rb/agent-ensure (call :agent)))
    (def p0 (protect (rb/tool-run (call :name) (call :arguments))))
    (def ok0 (get p0 0))
    (def v0 (get p0 1))
    # REQ-69：策略拒绝先走审批（允许 → 登记临时授权 → 重试一次）
    (def p (if (and (not ok0) (dictionary? v0) (get v0 :rb-denied))
             (rb/tool-approve call v0)
             p0))
    (def ok (get p 0))
    (def v (get p 1))
    (if ok
      (rb/agent-append! a @{:role "tool"
                             :content (rb/tool-encode v)
                             :tool-call-id (call :id)})
      (if (and (dictionary? v) (get v :rb-arg))
        # REQ-68：模型的手误（参数名 / 工具名）作为**工具结果**回给它，回合继续。
        # 不这么做的话，一次 `command` 写成 `cmd` 就换来整轮 `@RoundDone 失败`。
        (rb/agent-append! a @{:role "tool"
                               :content (string "错误：" (rb/error-msg v)
                                                "\n（参数名不对。工具定义里写了可接受的键，改正后再调用。）")
                               :tool-call-id (call :id)})
        (rb/raise (rb/exit-table (if (rb/rb-error? v) (v :rb-code) :orchestration-base))
                  (rb/error-msg v))))
    (put call :done true))
  nil)

# 装进工作区的默认钩子（REQ-48；`@off @Toolcall` 后不起作用）
(set rb/default-toolcall rb/default-toolcall-hook)
# 审批的默认实现（REQ-69）：`@off @Approve` 后没人点头 → 拒绝（退回 v1.0o 的行为）
(set rb/default-approve rb/default-approve-hook)

(defn rb/tool-loop
  "把一个 provider 取块函数包成**工具感知**的取块函数（REQ-48 ④）。
   provider 返回 table = 一次工具调用批：追加 `assistant` 消息 → 发 `@Toolcall`
   → 钩子执行工具并追加 `tool` 消息 → **同一个流**接着取下一批文本。
   有任何调用未被处理（`@off @Toolcall`）→ 把流冻在 `:tool`。"
  [a it0 opts stream]
  (var it it0)
  (fn []
    (var go true)
    (var out nil)
    (while go
      (def v (it))
      (cond
        (nil? v)
        (set go false)

        (string? v)
        (do (set out v) (set go false))

        # P2：纯用量元信息块原样透传（stream-next! 记下来、继续取，不发 @Chunk）。
        # 注意：带 `:tool-calls` 的批要先执行工具，所以这个分支必须排在它后面判。
        (and (table? v) (get v :usage) (not (get v :tool-calls)))
        (do (set out v) (set go false))

        (table? v)
        (do
          (def calls (get v :tool-calls))
          (when (not (and calls (> (length calls) 0)))
            (rb/raise (rb/exit-table :orchestration-base)
                      (string "provider 返回的块既不是文本也不是工具调用："
                              (string/format "%q" v))))
          # 一条 assistant 消息承载这一批调用（OpenAI 兼容格式）
          (rb/agent-append! a @{:role "assistant" :content ""
                                 :tool-calls (tuple ;(map (fn [c] (or (get c :raw) c)) calls))})
          (var blocked false)
          (each raw calls
            (def call (rb/tool-call-new a raw))
            (put call :stream stream)
            (rb/emit "@Toolcall" [call stream])
            (unless (call :done) (set blocked true)))
          (if blocked
            (do
              (when stream (put stream :state :tool))
              (set go false))
            (do
              (set it (rb/llm-chat (rb/messages-of a) opts))
              (when (not (function? it))
                (rb/raise (rb/exit-table :orchestration-base)
                          (string "provider 必须返回取块函数，得到 " (type it))))
              # P2：这一批若带用量，先把它交出去（流记账后再来取下一批文本）
              (when (get v :usage)
                (set out @{:usage (get v :usage)})
                (set go false)))))

        (rb/raise (rb/exit-table :orchestration-base)
                  (string "provider 的块类型未知：" (type v)))))
    out))

(set rb/tool-hooks
     @{:defs rb/tool-defs
       :wrap (fn [a it opts stream]
               (rb/tool-loop a it opts stream))})
