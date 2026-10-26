# rb/cli.janet —— CLI 与前后端分离（REQ-22 / REQ-23 / REQ-24 / REQ-25 / REQ-43）
#
# 形态：
#   ravel                  REPL（提示符 `ravel> `，栈在一个工作区里跨行保留）
#   ravel -e "<一行>"       求值一行
#   ravel script.breve     执行脚本
#   ravel --serve          NDJSON over stdio（协议 v1，见 docs/PROTOCOL.md）
#   ravel --json …         把结果按协议消息形状打到 stdout（REQ-22「输出 JSON」）
#
# 退出码由 rb/exit.janet 分级（REQ-23 / 附录 E）。
#
# REQ-25：元命令是**无前缀裸词**，与 ravel 代码的分界由编辑器 minibuffer 承担。
# 因此后端只冻结一份**保留名表**，并保证这些名字不是方言词（在代码里出现即 20）。
# 保留名表**不得**与词表重名（REQ-09：一个名字只有一种词性）——`watch` 是方言词
# （L9），所以它不在这里。

(def rb/version "1.0q")
(def rb/version-string "ravel breve 1.0q · janet 1.42.1")

# REQ-25：保留的元命令名（无前缀裸词，均不是方言词）
(def rb/meta-commands
  @["quit" "exit" "help" "clear"])

(defn rb/meta-command?
  [s]
  (var found false)
  (each m rb/meta-commands (when (= m s) (set found true)))
  found)

(defn rb/cli-usage
  []
  (print "用法：")
  (print "  ravel                     REPL（提示符 ravel> ）")
  (print "  ravel -e \"<一行>\"           求值一行，打印剩余栈")
  (print "  ravel script.breve        执行脚本")
  (print "  ravel --serve             NDJSON over stdio（REQ-24）")
  (print "  ravel --dump ...          打印转译产物（REQ-31）")
  (print "  ravel --json ...          按协议消息形状输出（REQ-22）")
  (print "  ravel --preset <名字>     启动即导入 provider 配置预设（REQ-62，可重复）")
  (print "  ravel --presets           列出可用的配置预设（REQ-64）")
  (print "  ravel --modes             列出预制的处理流程模式（REQ-64）")
  (print "  ravel --no-config         不装载 ~/.config/ravel/config.json（REQ-63）")
  (print "  ravel -v | -h"))

# ---- 结果 → 文本 / 协议消息 ---------------------------------------------

(defn rb/cli-result-msg
  "把一次求值结果变成协议消息（附录 F；`id` 原样回显，REQ-24）。"
  [r &opt id]
  (def msg (if (r :ok)
             @{:type "result"
               :ok true
               :stack (map rb/render (r :stack))}
             @{:type "result"
               :ok false
               :code (rb/error-code (r :error))
               :error (rb/error-msg (r :error))}))
  (when (not (nil? id)) (put msg :id id))
  msg)

(defn rb/cli-encode
  "一条协议消息 → 一行 JSON；缺能力层返回 nil（REQ-37）。"
  [msg]
  (def encode (rb/cap-get :json/encode))
  (if (nil? encode) nil (encode msg)))

(defn rb/cli-report
  "把一次求值结果写到 stdout/stderr，返回退出码。"
  [r dump? json?]
  (when dump?
    # REQ-43：json 模式下 stdout 只承载协议，诊断走 stderr
    (if json?
      (eprintf "dump: %s\n" (get r :code ""))
      (print (get r :code ""))))
  (if json?
    (let [line (rb/cli-encode (rb/cli-result-msg r))]
      (if (nil? line)
        (do (eprintf "ravel: --json 需要能力层 cap/json（REQ-37）\n")
            (rb/exit-table :orchestration-base))
        (do (print line) (flush)
            (if (r :ok) 0 (rb/error-code (r :error))))))
    (if (r :ok)
      (do
        (each v (r :stack) (print (rb/render v)))
        0)
      (do
        (eprintf "ravel: %s\n" (rb/error-msg (r :error)))
        (rb/error-code (r :error))))))

(defn rb/cli-out-begin
  "开始捕获方言 print/show 的输出（REQ-43：stdout 只承载协议）。"
  [&opt buf]
  (set rb/out-sink (or buf @""))
  rb/out-sink)

(defn rb/cli-out-flush!
  "把捕获到的方言输出转去 stderr 并清空（诊断通道）。"
  []
  (def b rb/out-sink)
  (when (and b (> (length b) 0))
    (file/write stderr b)
    (file/flush stderr)
    (buffer/clear b))
  nil)

(defn rb/cli-run-source
  [src name dump? json? &opt env]
  (when json? (rb/cli-out-begin))
  (def r (try
           (rb/run-source src name env)
           ([e] {:ok false :error e :stack @[]})))
  (when json? (rb/cli-out-flush!))
  (rb/cli-report r dump? json?))

# ---- REPL 与元命令（REQ-22 / REQ-25）------------------------------------

(defn rb/cli-meta
  "REPL 的元命令分发：返回 nil = 继续读，数字 = 退出码。"
  [line env]
  (cond
    (or (= line "quit") (= line "exit")) 0
    (= line "help") (do (rb/cli-usage) nil)
    # clear = 清空变量空间（栈），保留字典与钩子（REQ-25）
    (= line "clear") (do (array/clear (env :rb-stack)) nil)
    nil))

(defn rb/cli-repl
  [dump? json?]
  (def env (rb/new-env)) # REPL 内栈跨行保留
  (var buf "")
  (def hist @[])       # 行编辑器的历史（D-57）
  (var running true)
  (var exit 0)
  (while running
    # 行编辑器交给 rb/line.janet（D-57）；nil = EOF（C-d 空行 / stdin 关闭）
    (def raw (rb/line-read (if (empty? buf) "ravel> " "     > ") hist))
    (if (nil? raw)
      (set running false)
      (do
        (def line (string/trimr (string raw)))
        (when (and (empty? buf) (not (empty? line)))
          (array/push hist line))
        (if (and (empty? buf) (rb/meta-command? line))
          # 元命令只认「单独一行、且没有待续的块」，其余一律当方言代码（REQ-25）
          (let [code (rb/cli-meta line env)]
            (when (not (nil? code))
              (set running false)
              (set exit code)))
          (do
            (set buf (string buf line "\n"))
            (def p (try (rb/lex buf "repl") ([e] {:error e})))
            (cond
              (get p :error)
              (do (eprintf "ravel: %s\n" (rb/error-msg (p :error)))
                  (set buf ""))

              (p :incomplete) nil

              (do
                (when (> (length (p :stmts)) 0)
                  (when json? (rb/cli-out-begin))
                  (def r (try
                           (rb/run-source buf "repl" env)
                           ([e] {:ok false :error e :stack @[]})))
                  # REPL 也报告栈（同 -e），错误走 stderr 且不退出（REQ-22）
                  (when json? (rb/cli-out-flush!))
                  # 先冲 stdout：管道/重定向时它是块缓冲，不冲会让提示符
                  # 出现在错误消息之后，看着像「REPL 重开了」（D-55）
                  (flush)
                  (rb/cli-report r dump? json?)
                  (flush)
                  (when (not (r :ok)) (set exit 0)))
                (set buf ""))))))))
  exit)

# ---- --serve：NDJSON over stdio（REQ-24 / REQ-42 / REQ-43）---------------

(defn rb/serve-json-line?
  "这一行是 JSON 请求还是 ravel 源码？
   `{ 1 2 }`（字面量）与 `{\"type\":\"eval\"}`（请求）都以 `{` 开头，
   故判定为：`{` 之后（跳过空白）紧跟 `\"`（协议 v1，见 docs/PROTOCOL.md）。"
  [line]
  (def t (string/triml (string line)))
  (and (string/has-prefix? "{" t)
       (string/has-prefix? "\"" (string/triml (string/slice t 1)))))

(defn rb/serve-parse
  "一行请求 → 表 `{:type … :msg … :error …}`。
   裸文本 = `eval` 的简写（附录 F）；`{ … }` = 显式 JSON 请求（协议 v1）。"
  [line decode]
  (if (rb/serve-json-line? line)
    (let [p (protect (decode line))
          m (get p 1)]
      (cond
        (not (get p 0)) {:type "bad" :error (string "请求不是合法 JSON：" (rb/error-msg m))}
        (not (table? m)) {:type "bad" :error "请求必须是 JSON 对象"}
        {:type (string (get m "type" "eval")) :msg m}))
    {:type "eval" :msg @{"type" "eval" "src" line}}))

(defn rb/serve-bad
  "协议错误：一条失败响应，但**不**终止循环（REQ-42）。"
  [error &opt id]
  (def msg @{:type "result" :ok false :code 2 :error error})
  (when (not (nil? id)) (put msg :id id))
  (rb/proto-emit msg)
  msg)

(defn rb/serve-eval
  [env src id dump?]
  (def r (try
           (rb/run-source src "<serve>" env)
           ([e] {:ok false :error e :stack @[]})))
  (when dump?
    # REQ-43：stdout 只承载协议 → 转译产物走 stderr
    (eprintf "dump: %s\n" (get r :code "")))
  (def msg (rb/cli-result-msg r id))
  (rb/proto-emit msg)
  msg)

(defn rb/cli-serve-loop
  [dump?]
  # 能力层走显式注册表（§4.11）：核心不静态依赖 cap/，剔除 cap/ 后仍可装载
  (def encode (rb/cap-get :json/encode))
  (def decode (rb/cap-get :json/decode))
  (rb/cli-out-begin)     # 方言 print/show 走 stderr，不污染协议 stdout（REQ-43）
  (var env (rb/new-env)) # REQ-42：工作区（字典 + 栈）跨请求保留
  # 注意：必须写**真正的** stdout——求值期间的 fiber 里 `print` 会被
  # `rb/out-sink` 截获（那是方言输出通道，见 rb/cli-out-begin）
  (set rb/proto-sink (fn [msg]
                       (file/write stdout (string (encode msg) "\n"))
                       (file/flush stdout)))
  (set rb/stream-tap rb/proto-tap)
  (set rb/event-tap rb/proto-event)   # REQ-48：`@Toolcall` 等事件推给前端
  (var running true)
  (var exit 0)
  (while running
    (def raw (getline ""))
    (if (empty? raw)
      (set running false)
      (do
        (def line (string/trimr (string raw)))
        (when (not (empty? line))
          (def req (rb/serve-parse line decode))
          (def m (req :msg))
          (def id (if (table? m) (get m "id") nil))
          (case (req :type)
            "eval"
            (do
              (def src (get m "src"))
              (if (string? src)
                (rb/serve-eval env src id dump?)
                (rb/serve-bad "eval 需要字符串字段 src（协议 v1）" id)))

            "ping" (rb/proto-emit @{:type "pong" :protocol rb/protocol-version})

            "hello"
            (rb/proto-emit @{:type "hello"
                             :protocol rb/protocol-version
                             :version rb/version-string})

            # P3：取消 —— 停掉还开着的流（含 `->` 血缘传播），不结束会话
            "cancel"
            (do
              (def n (rb/cancel-all!))
              (def msg @{:type "result" :ok true :stack @[] :stopped n})
              (when (not (nil? id)) (put msg :id id))
              (rb/proto-emit msg))

            "reset"
            (do
              (set env (rb/new-env))
              (def msg @{:type "result" :ok true :stack @[]})
              (when (not (nil? id)) (put msg :id id))
              (rb/proto-emit msg))

            "quit"
            (do
              (rb/proto-emit @{:type "bye" :protocol rb/protocol-version})
              (set running false))

            "bad" (rb/serve-bad (req :error) id)

            (do
              (rb/serve-bad (string "未知的请求类型：" (req :type) "（协议 v1 只认 eval/ping/hello/reset/cancel/quit）")
                            id)))
          (rb/cli-out-flush!)
          # REQ-24：请求处理完再把视图流推给前端——前端可边收边写
          (when running (rb/watch-tick! env))))))
  (set rb/proto-sink nil)
  (set rb/stream-tap nil)
  (set rb/event-tap nil)
  exit)

# ---- 预制的可发现（REQ-64）----------------------------------------------

# 预设目录。同名字面量在 cap/preset.janet 里有一份（`cap/preset-dir`）：
# 核心不能引用 cap/ 的符号（REQ-37 / D-29），所以这里各留一份，改一处要改两处。
(def rb/cli-preset-dir "presets")

(defn rb/cli-show-presets
  "列出可用的 provider 配置预设 + 用户配置文件状态。返回退出码。

   缺能力层（`--core-only`）不是「选项写错」，是**这一层没带**：报 60（REQ-37），
   和 `llm-import` 在核心构建里的处置一致。"
  []
  (def f (rb/cap-get :llm/presets))
  (if (nil? f)
    (do (eprintf "ravel: --presets 需要能力层 cap/preset（REQ-37；--core-only 下没有预设）\n")
        (rb/exit-table :orchestration-base))
    (do
      (def items (f))
      # 目录可能不存在（在别的目录里跑就是这个下场）：realpath 会抛，这里退成 cwd+相对路径，
      # 让「找的是哪个目录」照样是绝对的（D-71）
      (def dir
        (do
          (def rp (protect (os/realpath rb/cli-preset-dir)))
          (if (get rp 0)
            (get rp 1)
            (do
              (def cwd (os/cwd))
              (if (string/has-suffix? "/" cwd)
                (string cwd rb/cli-preset-dir)
                (string cwd "/" rb/cli-preset-dir))))))
      (printf "配置预设（%s）：" dir)
      (if (empty? items)
        (do (printf "  （这个目录里没有 .json 预设）")
            (printf "  预设目录是相对当前目录的：在仓库根目录跑，或 ravel --preset <绝对路径>")
            (printf "  想「到处都能用」请把配置放进用户配置文件（RB_CONFIG 或 ~/.config/ravel/config.json）"))
        (each it items
          (def c (it :config))
          (if (nil? c)
            (printf "  %-14s <读不出来：%s>" (it :name) (or (it :error) "?"))
            (printf "  %-14s provider=%-10s model=%s"
                    (it :name) (or (get c "provider") "-") (or (get c "model") "-")))))
      (def user (rb/config-user-path))
      (cond
        (nil? user) (printf "用户配置文件：已关闭（RB_CONFIG=- / --no-config）")
        (os/stat user) (printf "用户配置文件：%s（启动时自动装载）" user)
        (do (printf "用户配置文件：%s（不存在，跳过）" user)))
      (printf "用法：ravel --preset <名字>  或  ravel --preset presets/<名字>.json（相对当前目录）")
      0)))

(defn rb/cli-show-modes
  "列出预制的处理流程模式（名字 / 说明 / 工具）。返回退出码。"
  []
  (def ms (rb/mode-presets))
  (def names (sort (keys ms)))
  (printf "处理流程模式：")
  (each n names
    (def m (ms n))
    (def tools (sort (keys (or (m :tools) @{}))))
    (printf "  %-10s 工具：%s" n (if (empty? tools) "—" (string/join tools " ")))
    # REQ-67：声明的工具需要什么前置设定，就印出来（"装了就配好"要看得见才可信）
    (def sets @[])
    (eachp [tool gate] (rb/tool-gates)
      (when (and (get (or (m :tools) @{}) tool)
                 (not (nil? (get (or (m :flags) @{}) gate))))
        (array/push sets (string gate "=" (if (get (m :flags) gate) "on" "off")))))
    (when (not (empty? sets))
      (printf "  %-10s 设定：%s" "" (string/join sets " ")))
    (printf "  %-10s %s" "" (or (m :doc) "")))
  (printf "用法：mode \"<名字>\"（在方言里切换；`modes` 词也一样能列名字）")
  0)

# ---- 入口 ---------------------------------------------------------------

(defn rb/cli-main
  [argv]
  (def n (length argv))
  (var i 0)
  (var dump? false)
  (var json? false)
  (var src nil)
  (var file nil)
  (var serve? false)
  (var done? false)
  (var exit 0)
  (while (and (not done?) (= exit 0) (< i n))
    (def a (argv i))
    (cond
      (or (= a "-v") (= a "--version"))
      (do (print rb/version-string) (set done? true) (++ i))

      (or (= a "-h") (= a "--help"))
      (do (rb/cli-usage) (set done? true) (++ i))

      (= a "--dump")
      (do (set dump? true) (++ i))

      (= a "--json")
      (do (set json? true) (++ i))

      (or (= a "-e") (= a "--eval"))
      (if (>= (inc i) n)
        (do (eprintf "ravel: -e 需要一个参数\n") (set exit (rb/exit-table :usage)))
        (do (set src (argv (inc i))) (set i (+ i 2))))

      (= a "--serve")
      (do (set serve? true) (++ i))

      # REQ-62：一键导入配置预设（可重复，按序叠加；后装的覆盖先装的）
      (or (= a "--preset") (= a "-p"))
      (if (>= (inc i) n)
        (do (eprintf "ravel: --preset 需要一个名字或路径\n") (set exit (rb/exit-table :usage)))
        (do (array/push rb/config-presets (argv (inc i))) (set i (+ i 2))))

      # REQ-63：显式关掉用户配置文件（`RB_CONFIG=-` 的等价写法）
      (= a "--no-config")
      (do (os/setenv "RB_CONFIG" "-") (++ i))

      # REQ-64：不启动工作区，只把「有什么可用」打出来（输出即结果，不是诊断）
      (= a "--presets")
      (do (set exit (rb/cli-show-presets)) (set done? true) (++ i))

      (= a "--modes")
      (do (set exit (rb/cli-show-modes)) (set done? true) (++ i))

      (string/has-prefix? "-" a)
      (do (eprintf "ravel: 未知选项 %s\n" a) (set exit (rb/exit-table :usage)))

      (do (set file a) (++ i))))
  (cond
    (not= exit 0) exit
    done? exit
    serve? (do
             (if (or (nil? (rb/cap-get :json/encode)) (nil? (rb/cap-get :json/decode)))
               (do (eprintf "ravel: --serve 需要能力层 cap/json（REQ-37）\n")
                   (set exit (rb/exit-table :internal)))
               nil)
             (if (= exit 0) (rb/cli-serve-loop dump?) exit))
    (not (nil? src)) (rb/cli-run-source src "<-e>" dump? json?)
    (not (nil? file))
    (let [p (protect (slurp file))]
      (if (get p 0)
        (rb/cli-run-source (get p 1) file dump? json?)
        (do (eprintf "ravel: 无法读取 %s：%s\n" file (rb/error-msg (get p 1)))
            (rb/exit-table :io-read))))
    (rb/cli-repl dump? json?)))
