# rb/store.janet —— 工作区持久化（REQ-20 / REQ-21，D-33…D-37）
#
# 一个工作区 = 版本化**单文件 JSON 快照** + **JSONL 增量日志**（REQ-20）：
#   <path>       快照：整份工作区（字典的源 + 栈的值 + agent 血缘）
#   <path>.log   JSONL：每轮一行，记「本轮新增/改写的定义 + 本轮的栈」
#
# 为什么日志记**源**不记宿主序：方言源是唯一可重放的真相，宿主序是实现
# 细节（D-34）。载入时把 `名字 : [ 体 ]` 重新转译。
#
# 值编码（D-36）——只在必要时加 `"$"` 标签，其余按 JSON 原样：
#   字符串 / 数字 / 布尔 / nil  → 原样
#   tuple  → {"$":"tuple","v":[…]}      array → {"$":"array","v":[…]}
#   Utter  → {"$":"utter","role":…,"content":…}
#   其他表 → {"$":"table","v":{…}}      关键字/符号 → {"$":"keyword"/"symbol"}
#   Agent  → {"$":"agent-ref","label":…}（定义在快照顶层 "agents" 里）
#   Stream → **不持久化**（本轮产物，跨轮无意义；载入丢弃并保留 nil 占位感）
#
# 文件读写一律经能力层（REQ-37）：:fs/read/:fs/write/:fs/append/:fs/size + :json/*。
# 缺能力层（--core-only）时 L7 词报 60，核心其余部分不受影响。

(def rb/store-version 1)
(def rb/store-kind "ravel-workspace")
(def rb/store-absent (gensym))
(def rb/store-log-limit 1000)

# REQ-21 主判据的下限：小工作区（快照 ~150 字节）按纯比例会「每轮 compact」，
# 使增量日志退化成每轮全量重写；因此日志至少要到 512 字节才按比例判（D-58 / SF-18）。
(def rb/store-log-floor 512)
(def rb/store-max-depth 12)

# ---- 能力层取用（核心不含具体实现）-------------------------------------

(defn rb/store-cap
  [k]
  (def f (rb/cap-get k))
  (when (nil? f)
    (rb/raise (rb/exit-table :orchestration-base)
              (string "持久化需要能力 " k "（cap/fs + cap/json）")))
  f)

(defn rb/store-encode [v] ((rb/store-cap :json/encode) v))
(defn rb/store-decode [s] ((rb/store-cap :json/decode) s))
(defn rb/store-file-read [p] ((rb/store-cap :fs/read) p))
(defn rb/store-file-append [t p] ((rb/store-cap :fs/append) t p))
(defn rb/store-file-size [p] ((rb/store-cap :fs/size) p))

(defn rb/store-file-write
  "写文件；失败归入 IO(41)。"
  [text path]
  (def f (rb/store-cap :fs/write)) # 先取能力：缺能力层要报 60，不能被下面的 protect 吞成 41
  (def p (protect (f text path)))
  (when (not (get p 0))
    (rb/raise (rb/exit-table :io-write)
              (string "写入失败：" path "（" (rb/error-msg (get p 1)) "）")))
  (length text))

# ---- 值 ⇄ JSON（D-36）---------------------------------------------------

(defn rb/utter?
  "Utter = @{:role 字符串 :content 字符串}（D-22）。"
  [x]
  (and (table? x)
       (nil? (get x :kind))
       (string? (get x :role))
       (string? (get x :content))))

# 表 ↔ 表互相递归，先声明
(var rb/store-enc nil)
(var rb/store-dec nil)

(defn rb/store-enc-table
  [v depth]
  (def o @{})
  (eachp [k x] v (put o (string k) (rb/store-enc x depth)))
  o)

(set rb/store-enc
     (fn [v &opt depth]
       (def d (or depth 0))
       (cond
         (nil? v) nil
         (or (boolean? v) (number? v) (string? v)) v
         (rb/stream? v) @{"$" "stream" "label" (string (get v :label ""))}
         (rb/agent? v) @{"$" "agent-ref" "label" (string (get v :label ""))}
         (rb/workspace-value? v) @{"$" "workspace"}
         (rb/utter? v) @{"$" "utter" "role" (v :role) "content" (v :content)}
         (> d rb/store-max-depth) @{"$" "opaque" "type" "deep"}
         (tuple? v) @{"$" "tuple" "v" (map (fn [x] (rb/store-enc x (+ 1 d))) v)}
         (array? v) @{"$" "array" "v" (map (fn [x] (rb/store-enc x (+ 1 d))) v)}
         (table? v) @{"$" "table" "v" (rb/store-enc-table v (+ 1 d))}
         (keyword? v) @{"$" "keyword" "v" (string v)}
         (symbol? v) @{"$" "symbol" "v" (string v)}
         @{"$" "opaque" "type" (string (type v))})))

(defn rb/store-agent-by-label
  [ws label]
  (var found nil)
  (each a (ws :agents) (when (= label (a :label)) (set found a)))
  found)

(defn rb/store-dec-table
  [x ws]
  (def o @{})
  (eachp [k e] x (put o k (rb/store-dec e ws)))
  o)

(set rb/store-dec
     (fn [x ws]
       (if (not (dictionary? x))
         x
         (let [tag (get x "$")]
           (if (nil? tag)
             x
             (cond
               (= tag "tuple") (tuple ;(map (fn [e] (rb/store-dec e ws)) (get x "v")))
               (= tag "array") (map (fn [e] (rb/store-dec e ws)) (get x "v"))
               (= tag "utter") @{:role (get x "role") :content (get x "content")}
               (= tag "table") (rb/store-dec-table (get x "v") ws)
               (= tag "keyword") (keyword (get x "v"))
               (= tag "symbol") (symbol (get x "v"))
               (= tag "agent-ref") (rb/store-agent-by-label ws (get x "label"))
               (= tag "workspace") ws
               (= tag "stream") rb/store-absent
               (= tag "opaque") rb/store-absent
               x))))))

# ---- 快照 ---------------------------------------------------------------

(defn rb/store-dict-json
  "字典 → 名字 → 含 doc 与 src 两字段的表（只存 ravel 源，D-34）。"
  [dict]
  (def o @{})
  (each name (sort (keys dict))
    (def e (get dict name))
    (put o name @{"doc" (or (e :doc) "") "src" (or (e :src) "")}))
  o)

(defn rb/store-dict-diff
  "两个 dict-json 的差异 → 定义数组（供日志与 compact 判据用）。"
  [old new]
  (def out @[])
  (eachp [n e] new
    (def o (get old n))
    (when (or (nil? o)
              (not= (get o "src") (get e "src"))
              (not= (get o "doc") (get e "doc")))
      (array/push out @{"name" n "src" (get e "src") "doc" (get e "doc")})))
  out)

(defn rb/store-agents-json
  [ws]
  (def out @[])
  (each a (ws :agents)
    (array/push out @{"label" (string (get a :label ""))
                      "live" (not (nil? (a :live)))
                      "turn" (or (a :turn) 0)
                      "origin" (map string (or (a :origin) []))
                      "session" (map rb/store-enc (or (a :session) @[]))}))
  out)

(defn rb/store-enc-stack
  "栈 → JSON 形状；Stream 落盘无意义，丢弃（D-36）。"
  [stack]
  (map rb/store-enc (filter (fn [v] (not (rb/stream? v))) stack)))

(defn rb/store-config-json
  "工作区 provider 配置 → 纯 JSON 对象（键都是字符串，值是标量；D-54）。"
  [ws]
  (def o @{})
  (eachp [k v] (or (ws :config) @{})
    (when (not (nil? v)) (put o (string k) v)))
  o)

(defn rb/store-config-apply!
  "载入快照里的 `llm` 段；缺省 = 清空（回落到环境变量/内置缺省）。"
  [ws cfg]
  (def c @{})
  (when (dictionary? cfg)
    (eachp [k v] cfg (put c (string k) v)))
  (put ws :config c))

(defn rb/store-snapshot
  "工作区 + 栈 → 快照 JSON 文本（REQ-20 的「单文件」）。"
  [ws stack]
  (rb/store-encode @{"kind" rb/store-kind
                     "version" rb/store-version
                     "dict" (rb/store-dict-json (ws :dict))
                     "stack" (rb/store-enc-stack stack)
                     "agents" (rb/store-agents-json ws)
                     # D-54：provider 配置随工作区走（明文 JSON 对象；密钥不在其中）
                     "llm" (rb/store-config-json ws)}))

(defn rb/store-log-line
  "一轮 → 一行 JSONL 文本（不含换行）。`llm` 段只在配置与本轮日志基线不同时出现（D-54）。"
  [ws seq defs stack]
  (def cfg (rb/store-config-json ws))
  (def rec @{"v" rb/store-version
             "n" seq
             "defs" defs
             "stack" (rb/store-enc-stack stack)})
  (when (not= (rb/store-encode cfg) (or (ws :logged-config) "{}"))
    (put rec "llm" cfg))
  rec
  (rb/store-encode rec))

(defn rb/store-log-path
  [path]
  (string path ".log"))

# ---- 执行（载入 / 重放共用；不触发钩子、不写日志）----------------------

(defn rb/store-run-def!
  "在给定工作区里重新定义一条 {name src doc}。"
  [ws d name]
  (def n (get d "name"))
  (def src (or (get d "src") ""))
  (def env (ws :env))
  (when (and n (not= src ""))
    (def code ((rb/compile-source (string n " : [ " src " ]") name env) :code))
    (def thunk (compile (parse code) (curenv) name))
    (when (not (function? thunk))
      (rb/raise (rb/exit-table :syntax-compile)
                (string "载入失败：" n "（" (get thunk :error) "）")))
    (def fb (fiber/new thunk :e env))
    (resume fb)
    (when (= (fiber/status fb) :error)
      (rb/raise (rb/exit-table :syntax-compile)
                (string "载入失败：" n "（" (rb/error-msg (fiber/last-value fb)) "）")))
    (def e (rb/dict-entry n (ws :dict)))
    (when e (put e :doc (or (get d "doc") "")))))

(defn rb/store-apply-defs!
  [ws defs name]
  (each d defs (rb/store-run-def! ws d name)))

(defn rb/store-apply-stack!
  "用记录里的栈替换当前栈（Stream 等不可持久化项跳过）。"
  [ws stack-json]
  (def env (ws :env))
  (def stk (if env (env :rb-stack) nil))
  (when stk
    (array/clear stk)
    (each v stack-json
      (def x (rb/store-dec v ws))
      (when (not= x rb/store-absent) (array/push stk x)))))

# ---- 保存 / 载入 --------------------------------------------------------

(defn rb/store-save!
  "写快照 + 清空日志，并把工作区**绑定**到该路径（REQ-20）。"
  [ws stack path]
  (when (not (string? path))
    (rb/raise (rb/exit-table :runtime-type)
              (string "save 需要一个路径字符串，得到 " (type path))))
  (def text (rb/store-snapshot ws stack))
  (rb/store-file-write text path)
  (rb/store-file-write "" (rb/store-log-path path))
  (put ws :path path)
  (put ws :seq 0)
  (put ws :snap-size (length text))
  (put ws :logged (rb/store-dict-json (ws :dict)))
  (put ws :logged-config (rb/store-encode (rb/store-config-json ws)))
  (put ws :logged-stack (rb/store-encode (rb/store-enc-stack stack)))
  ws)

(defn rb/store-load!
  "从 path 载入（快照 + 日志重放）到该工作区；返回工作区（REQ-20）。"
  [ws path]
  (when (not (string? path))
    (rb/raise (rb/exit-table :runtime-type)
              (string "load 需要一个路径字符串，得到 " (type path))))
  (def text (rb/store-file-read path))
  (when (nil? text)
    (rb/raise (rb/exit-table :io-read) (string "文件不存在或无权限：" path)))
  (def snap (rb/store-decode text))
  (when (not= (get snap "kind") rb/store-kind)
    (rb/raise (rb/exit-table :orchestration-base)
              (string "不是 ravel 工作区快照：" path)))
  (when (> (or (get snap "version") 0) rb/store-version)
    (rb/raise (rb/exit-table :orchestration-base)
              (string "快照版本过新：" (get snap "version"))))
  (put ws :loading true)
  # 1) agent 注册表先重建（栈里的 agent-ref 依赖它）
  (array/clear (ws :agents))
  (each a (or (get snap "agents") @[])
    (def ag (rb/agent-new (string (get a "label")) @[] nil
                          (tuple ;(or (get a "origin") @[]))))
    (put ag :live (not (nil? (get a "live"))))
    (put ag :turn (or (get a "turn") 0))
    (each u (or (get a "session") @[])
      (def uu (rb/store-dec u ws))
      (when (not= uu rb/store-absent) (array/push (ag :session) uu)))
    (array/push (ws :agents) ag))
  # 2) 字典：清空后按源重定义（REQ-20：字典属于工作区）
  (put ws :dict @{})
  (def defs @[])
  (eachp [n e] (or (get snap "dict") @{})
    (array/push defs
                @{"name" n
                  "src" (or (get e "src") "")
                  "doc" (or (get e "doc") "")}))
  (rb/store-apply-defs! ws defs path)
  # 3) 快照里的栈、agent 与 provider 配置（D-54）
  (rb/store-config-apply! ws (get snap "llm"))
  (rb/store-apply-stack! ws (or (get snap "stack") @[]))
  # 4) 日志重放：坏行 / 末尾半行容忍（崩溃恢复）
  (def logp (rb/store-log-path path))
  (def logtext (rb/store-file-read logp))
  (var n 0)
  (when (and logtext (not= logtext ""))
    (def ends-nl (string/has-suffix? "\n" logtext))
    (def lines (string/split "\n" logtext))
    (var i 0)
    (while (< i (length lines))
      (def line (lines i))
      (when (not= line "")
        (def p (protect (rb/store-decode line)))
        (if (get p 0)
          (let [rec (get p 1)]
            (when (dictionary? (get rec "llm"))
              (rb/store-config-apply! ws (get rec "llm")))
            (rb/store-apply-defs! ws (or (get rec "defs") @[]) path)
            (rb/store-apply-stack! ws (or (get rec "stack") @[]))
            (set n (+ n 1)))
          (when (and (not ends-nl) (= i (- (length lines) 1)))
            (eprintf "ravel: 警告：日志末行不完整（崩溃残留），已忽略\n"))))
      (set i (+ i 1))))
  (put ws :loading false)
  (array/clear (ws :watch))   # 视图流是活的观察者，不随快照复原
  (put ws :path path)
  (put ws :seq n)
  (put ws :snap-size (length text))
  (put ws :logged (rb/store-dict-json (ws :dict)))
  (put ws :logged-config (rb/store-encode (rb/store-config-json ws)))
  (put ws :logged-stack (rb/store-encode (rb/store-enc-stack (if (ws :env) ((ws :env) :rb-stack) @[]))))
  ws)

# ---- 增量日志与 compact（REQ-21）---------------------------------------

(defn rb/store-log-ratio
  "日志字节数 / 快照字节数（REQ-21 的 0.5 倍主判据）。"
  [ws]
  (def path (ws :path))
  (def snap (if (> (or (ws :snap-size) 0) 0)
              (ws :snap-size)
              (or (rb/store-file-size path) 0)))
  (def logsz (if path (rb/store-file-size (rb/store-log-path path)) 0))
  (if (or (nil? logsz) (nil? snap) (<= snap 0))
    {:log 0 :snap (or snap 0) :ratio 0}
    {:log logsz :snap snap :ratio (/ logsz snap)}))

(defn rb/store-compact-needed?
  "REQ-21：日志 > max(0.5 × 快照, 512 字节)（主判据，下限 512 见 D-58），
   或日志 > 1000 条，或显式调用。"
  [ws]
  (def r (rb/store-log-ratio ws))
  (or (> (r :log) (max (* 0.5 (r :snap)) rb/store-log-floor))
      (> (or (ws :seq) 0) rb/store-log-limit)))

(defn rb/store-compact!
  "写一版新快照并清空日志（REQ-21）。"
  [ws stack]
  (def path (ws :path))
  (when (nil? path)
    (rb/raise (rb/exit-table :orchestration-base)
              "该工作区未绑定持久化路径，无法 compact"))
  (def text (rb/store-snapshot ws stack))
  (rb/store-file-write text path)
  (rb/store-file-write "" (rb/store-log-path path))
  (put ws :seq 0)
  (put ws :snap-size (length text))
  (put ws :logged (rb/store-dict-json (ws :dict)))
  (put ws :logged-config (rb/store-encode (rb/store-config-json ws)))
  (put ws :logged-stack (rb/store-encode (rb/store-enc-stack stack)))
  ws)

(defn rb/store-after-eval!
  "一轮正常结束后：已绑定路径 → 追加一行日志，并按需 compact（REQ-20/21）。"
  [env]
  (def ws (get env :rb-ws))
  (when ws
    (def path (ws :path))
    (when (and path (not (ws :loading)))
      (def stack (env :rb-stack))
      (def defs (rb/store-dict-diff (or (ws :logged) @{})
                                    (rb/store-dict-json (ws :dict))))
      (def stack-json (rb/store-encode (rb/store-enc-stack stack)))
      (when (or (> (length defs) 0) (not= stack-json (ws :logged-stack)))
        (put ws :seq (+ 1 (or (ws :seq) 0)))
        (rb/store-file-append
          (string (rb/store-log-line ws (ws :seq) defs stack) "\n")
          (rb/store-log-path path))
        (each d defs
          (put (ws :logged) (get d "name")
               @{"src" (get d "src") "doc" (get d "doc")}))
        (put ws :logged-stack stack-json)
        (when (rb/store-compact-needed? ws)
          (rb/store-compact! ws stack))))
    ws))

# 接上求值出口（rb/eval.janet 里只有一处间接调用，见其注释）
(set rb/after-eval-hook rb/store-after-eval!)
