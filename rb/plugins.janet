# rb/plugins.janet —— 插件 ABI（REQ-60，v1.0j）
#
# ## 分层：什么是「核心层」，什么是「用户层」
#
#   核心层（插件**改不了**）：词法 + 转译 + 栈运行时、流、agent、钩子**机制**、
#   工作区与持久化、协议、退出码。这是方言的语法与语义——插件不能让它变。
#   用户层（插件**只能**往这里加）：词（定义行 `名字 : [ … ]`）、
#   钩子（`@on`）、工具（`deftool`）。这是「工作区里的内容」。
#
# 插件 = 一个用方言写的 `.breve` 文件：
#
#   plug "plugins/audit.breve"     # → "audit"
#   plugins                        # → @["audit"]
#   unplug "audit"                 # → 撤销项数
#
# 装载时**逐项记账**（词条表引用、钩子函数对象、工具表项），`unplug` 精确撤销：
#   - 插件新增的 → 删掉
#   - 插件**重定义**的（会照常告警）→ 还原旧词条
# 装载失败 → 同样撤销，再把原错误抛出去（不留半装状态，同 D-55 的精神）。
#
# ## 三条不许
#
#   ① 插件不能注册**能力**（`:cap`）：能力层是核心侧的东西（§4.11），
#      要新能力就改宿主——这条线保证「插件不改变求值语义，只改变工作区内容」。
#   ② 插件里不能再 `plug`（不做传递依赖；要组合就用 `RB_PLUGINS=a.breve,b.breve`）。
#   ③ 插件不能改核心词表的语义：重定义会告警、卸载还原，但 `@off` 掉默认钩子
#      这类**副作用**不可撤销（钩子本身能撤，它改过的状态不能）。
#
# ## 不算一轮
#
# 装载走 `rb/run-source … nested?=true`（同 PTC 的 `eval`）：**不触发** `@RoundDone`、
# 不写交互日志、不改本轮列表。插件是装载期的事，不是一次对话。
# 也正因为如此，`plug` **不进快照**：重开工作区要重新装（`RB_PLUGINS` 是给人用的）。

(def rb/plugin-events rb/mode-events)

# 当前正在装载的插件名。用模块变量而不是 `with-dyns`：
# 插件代码在**新的求值 fiber** 里跑（fiber 的 env 是工作区环境），
# 看不到调用者 fiber 的 dyn 绑定。
(var rb/plugin-now nil)

(defn rb/plugin-table
  "工作区里的插件台账（名字 → 记录）；没有就建一个。"
  []
  (def w (rb/ws))
  (def p (get w :plugins))
  (if (table? p)
    p
    (let [t @{}] (put w :plugins t) t)))

(defn rb/plugin-name
  "路径 → 插件名：取文件名，去掉 `.breve` 后缀。"
  [path]
  (def base (last (string/split "/" path)))
  (if (string/has-suffix? ".breve" base)
    (string/slice base 0 (- (length base) 6))
    base))

(defn rb/plugin-drop
  "真删一个键。Janet 的 `(put t k nil)` 只是把值设成 nil、键还留着，
   而字典的序列化（rb/store-dict-json）按 `(keys dict)` 逐项取字段——留着会炸。"
  [t k]
  (def keep @[])
  (eachp [kk vv] t
    (when (not= kk k) (array/push keep [kk vv])))
  (table/clear t)
  (each [kk vv] keep (put t kk vv))
  nil)

(defn rb/plugin-snap
  "装载前快照：字典 / 工具表 / 8 个事件的钩子数组（都是浅拷贝）。"
  []
  (def ws (rb/ws))
  (def hooks @{})
  (each e rb/plugin-events (put hooks e (array/slice (rb/hooks-of e))))
  @{:dict (table/clone (ws :dict))
    :tools (table/clone (ws :tools))
    :hooks hooks})

(defn rb/plugin-diff
  "快照 → 这一趟新增/替换了哪些项（按表引用/函数对象同一性判定）。"
  [snap]
  (def ws (rb/ws))
  (def words @[])
  (eachp [n e] (ws :dict)
    (when (not= e (get (snap :dict) n))
      (array/push words n)))
  (def tools @[])
  (eachp [n e] (ws :tools)
    (when (not= e (get (snap :tools) n))
      (array/push tools n)))
  (def hooks @[])
  (each e rb/plugin-events
    (def old (get (snap :hooks) e))
    (each q (rb/hooks-of e)
      (when (not (find |(= q $) old))
        (array/push hooks [e q]))))
  @{:words words :tools tools :hooks hooks})

(defn rb/plugin-undo
  "按快照撤销一趟装载：删掉新增的，还原被替换的（词条 / 工具 / 钩子）。"
  [snap]
  (def ws (rb/ws))
  (eachp [n e] (ws :dict)
    (def old (get (snap :dict) n))
    (when (not= e old)
      (if old
        (put (ws :dict) n old)
        (rb/plugin-drop (ws :dict) n))))
  (eachp [n e] (ws :tools)
    (def old (get (snap :tools) n))
    (when (not= e old)
      (if old
        (put (ws :tools) n old)
        (rb/plugin-drop (ws :tools) n))))
  (each e rb/plugin-events
    (def old (get (snap :hooks) e))
    (each q (array/slice (rb/hooks-of e))
      (when (not (find |(= q $) old))
        (rb/hook-del e q))))
  nil)

(defn rb/plugin-unload
  "卸载一个插件 → 撤销的项数；没装过 → 20（未知的词）。"
  [name]
  (def t (rb/plugin-table))
  (def rec (get t name))
  (when (nil? rec)
    (rb/raise (rb/exit-table :syntax-unknown-word)
              (string "没有装载这个插件：" name)))
  (def ws (rb/ws))
  (def snap (rec :snap))
  (var n 0)
  (each w (rec :words)
    (when (get (ws :dict) w)
      (def old (if snap (get (snap :dict) w) nil))
      (if old (put (ws :dict) w old) (rb/plugin-drop (ws :dict) w))
      (set n (inc n))))
  (each tl (rec :tools)
    (when (get (ws :tools) tl)
      (def old (if snap (get (snap :tools) tl) nil))
      (if old (put (ws :tools) tl old) (rb/plugin-drop (ws :tools) tl))
      (set n (inc n))))
  (each [e q] (rec :hooks)
    (when (find |(= q $) (rb/hooks-of e))
      (rb/hook-del e q)
      (set n (inc n))))
  (rb/plugin-drop t name)
  n)

(defn rb/plugin-load
  "装载一个插件文件 → 插件名。失败则撤销已装的部分并抛出原错误。"
  [path]
  (when (not (string? path))
    (rb/raise (rb/exit-table :runtime-type)
              (string "plug 需要一个路径字符串，得到 " (type path))))
  (when rb/plugin-now
    (rb/raise (rb/exit-table :runtime-type)
              (string "插件里不能再 plug（不做传递依赖）：" path)))
  (def f (rb/cap-get :fs/read))
  (when (nil? f)
    (rb/raise (rb/exit-table :orchestration-base)
              "plug 需要能力 :fs/read（cap/fs）"))
  (def src (f path))
  (when (nil? src)
    (rb/raise (rb/exit-table :io-read)
              (string "插件文件不存在或无权限：" path)))
  (def name (rb/plugin-name path))
  # 同名重装 = 先卸旧账（否则旧的那些词/钩子/工具就再也没人认领了）
  (when (get (rb/plugin-table) name) (rb/plugin-unload name))
  (def snap (rb/plugin-snap))
  (def env (or ((rb/ws) :env) (rb/new-env)))
  # 数据栈是 fiber-local 的（`(dyn :rb-stack)`）：装载既可能发生在方言求值里
  # （用户写 `plug`），也可能发生在 `rb/new-env`（`RB_PLUGINS` 启动装载，此时
  # 还没有求值 fiber）——两种情况下都取**同一个** env 的栈数组。
  (def stack (or (rb/stack) (env :rb-stack)))
  (def d0 (length stack))
  (defn cut [] (while (> (length stack) d0) (array/pop stack)))
  (def prev rb/plugin-now)
  (set rb/plugin-now name)
  (def r (protect (rb/run-source src path env true)))
  (set rb/plugin-now prev)
  (def ok (get r 0))
  (def res (get r 1))
  (when (not (and ok (res :ok)))
    (rb/plugin-undo snap)
    (cut)
    (error (if ok (res :error) res)))
  (cut)
  (def d (rb/plugin-diff snap))
  (put (rb/plugin-table) name
       @{:kind :plugin
         :name name
         :path path
         :words (d :words)
         :hooks (d :hooks)
         :tools (d :tools)
         :snap snap          # 装载前快照（卸载时据此还原被替换的旧词条/工具）
         :items (+ (length (d :words))
                   (length (d :hooks))
                   (length (d :tools)))})
  name)

(defn rb/plugin-list
  "已装插件名（升序）。"
  []
  (tuple ;(sort (keys (rb/plugin-table)))))

(defn rb/plugin-startup!
  "装载 `RB_PLUGINS` 列出的插件（逗号分隔，按序）。返回装载个数。"
  [_env]
  (def raw (os/getenv "RB_PLUGINS"))
  (var n 0)
  (when (and raw (not (empty? (string/trim raw))))
    (each piece (string/split "," raw)
      (def path (string/trim piece))
      (when (not (empty? path))
        (rb/plugin-load path)
        (set n (inc n)))))
  n)

# REQ-60：间接层接线（rb/eval.janet 的 `rb/new-env` 里调用）
(set rb/plugin-startup rb/plugin-startup!)

# D-72：cordis 模式的 `plugin` 工具要用它（modes 先于 plugins 装载，走间接层）
(set rb/mode-plugin-load rb/plugin-load)
