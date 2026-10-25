# rb/words/l10.janet —— L10 处理流程（模式）与历史标记开关（D-59）
#
# 这一层把「一轮请求怎么被处理」显式化：模式（数据） ⇄ 钩子（工作区现状）。
# 词性（REQ-09）：`mode` / `flag-set` 是动词；`modes` / `mode-of` / `flag` 是名词。

(defn rb/mode
  "Name|Mode -- ；切换处理流程。
   给字符串 = 取预制模式（`default` / `standard` / `ptc` / `minimal` / `cordis`）；
   给模式表 = 用它（可用 `mode-of` 造）。
   未知名字 → 20（未知的词），未知模式值 → 31。"
  []
  (def x (rb/pop))
  (def m (if (string? x)
           (do
             (def p (rb/mode-get x))
             (when (nil? p)
               (rb/raise (rb/exit-table :syntax-unknown-word)
                         (string "未知的模式：" x "（可用："
                                 (string/join (sort (keys (rb/mode-presets))) " ") "）")))
             p)
           x))
  (rb/mode-apply! m)
  nil)

(defn rb/modes
  "-- list ; 预制模式名（升序）。"
  []
  (rb/push (tuple ;(sort (keys (rb/mode-presets))))))

(defn rb/mode-of
  "-- Mode ；把当前工作区的钩子与开关导出成模式表（可与 `mode` 互逆）。"
  []
  (rb/push (rb/mode-capture)))

(defn rb/flag
  "Key -- Bool ；读一个历史标记开关（`history-turn` / `history-origin` / `history-mode` / `plan`）。"
  []
  (def k (rb/pop))
  (rb/push (rb/flag-get k)))

(defn rb/enter-plan
  "-- ；进入 plan 模式（打开 `plan` 开关，并登记 `exit_plan_mode` 工具）。
   与 dsh 的 `/plan` 同构：**正交于预置模式**，工具不换，只加提示约束。"
  []
  (rb/enter-plan!)
  nil)

(defn rb/exit-plan
  "-- ；手动退出 plan 模式（`exit_plan_mode` 之外的口子，同 dsh 的 `/plan off`）。"
  []
  (rb/exit-plan!)
  nil)

# ---- 临时授权（REQ-69 / D-75）------------------------------------------
#
# 模型发起的一次越界调用会先问人（`@Approve`）。人不在场（脚本 / CI / --serve）时
# 就用这两个词**预先**授权——比 `RB_SANDBOX=none` 细，比改模式小：
#   grant "fs" "/home/uiu/project/shader-learning"   → 该目录之下本工作区随便读写
#   grants                                           → 现在有哪些授权
#   ungrant                                          → 全撤掉

(defn rb/grant
  "Kind Key -- ；登记一条临时授权（到本工作区结束；`reset` 即失效）。
   只对**能力层认得的 kind** 有意义（目前 `fs`）。"
  []
  (def kind (rb/pop))   # 最左实参先被消费：`grant "fs" "/tmp"` → 先弹 kind
  (def key (rb/pop))
  (when (not (string? kind))
    (rb/raise (rb/exit-table :runtime-type) "grant 的第一个参数要是字符串（kind，如 \"fs\"）"))
  (when (not (string? key))
    (rb/raise (rb/exit-table :runtime-type) "grant 的第二个参数要是字符串（key，如一个路径）"))
  (rb/grant-add! kind key)
  (rb/push (string "已授权：" kind " " key "（到本工作区结束）")))

(defn rb/grants
  "-- list ；当前临时授权（表数组的拷贝）。"
  []
  (rb/push (rb/grants-of)))

# 裁决词（REQ-69）：在 `@on @Approve [ … ]` 里用，替代默认的「问终端」。
# 请求表是 `@Approve` 的载荷（栈顶），这几个词弹出它、写进裁决。

(defn rb/accept
  "Request -- ；允许这一次（登记一条 uses = 1 的授权，工具会被重试一次）。"
  []
  (def req (rb/pop))
  (when (table? req)
    (put req :decision :allow)
    (put req :grant @{:kind (req :kind) :key (or (req :path) (req :key)) :uses 1}))
  nil)

(defn rb/accept-dir
  "Request -- ；允许这个目录（到本工作区结束）：脚本 / CI 的常用写法。"
  []
  (def req (rb/pop))
  (when (table? req)
    (put req :decision :allow)
    (put req :grant @{:kind (req :kind) :key (or (req :dir) (req :path))}))
  nil)

(defn rb/reject
  "Request -- ；拒绝（错误消息用请求里那句，退出码 60）。"
  []
  (def req (rb/pop))
  (when (table? req)
    (put req :decision :deny)
    (put req :msg (string "已拒绝：" (or (req :path) (req :key) "?"))))
  nil)

(defn rb/ungrant
  "-- n ；撤掉所有临时授权，返回撤掉的条数。"
  []
  (rb/push (rb/grant-clear!)))

(defn rb/flag-set
  "Value Key -- ；写一个历史标记开关（值必须是布尔；nil = 删除该项）。"
  []
  (def v (rb/pop))
  (def k (rb/pop))
  (rb/flag-set! k v)
  nil)

# ---- 模式的自省（名词，只读；全是 0 元）--------------------------------

(defn rb/mode-name
  "Mode -- String ；模式名。"
  []
  (rb/push ((rb/pop) :name)))

(defn rb/mode-prompt
  "Mode -- String|nil ；模式的系统提示（只进请求，不进会话）。"
  []
  (rb/push ((rb/pop) :prompt)))

(defn rb/mode-tools
  "Mode -- list String ；模式声明的工具名（升序）。"
  []
  (def m (rb/pop))
  (rb/push (tuple ;(sort (keys (or (m :tools) @{}))))))
