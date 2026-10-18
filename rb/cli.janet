# rb/cli.janet —— CLI 与前后端分离骨架（REQ-22 / REQ-23 / REQ-24）
#
# 形态：ravel（REPL）/ ravel -e "<一行>" / ravel script.breve / ravel --serve
# 退出码由 rb/exit.janet 分级（REQ-23）。
# --serve 为 NDJSON over stdio 的 M0 骨架：每行一条 ravel 源码，
#   回一行 JSON 结果；每个请求使用**独立栈环境**（REQ-30 验收）。

(def rb/version-string "ravel breve 1.0c · janet 1.42.1")

(defn rb/cli-usage
  []
  (print "用法：")
  (print "  ravel                     REPL（提示符 ravel> ）")
  (print "  ravel -e \"<一行>\"           求值一行，打印剩余栈")
  (print "  ravel script.breve        执行脚本")
  (print "  ravel --serve             NDJSON over stdio（REQ-24）")
  (print "  ravel --dump ...          打印转译产物（REQ-31）")
  (print "  ravel -v | -h"))

(defn rb/cli-report
  "把一次求值结果写到 stdout/stderr，返回退出码。"
  [r dump?]
  (when dump?
    (print (get r :code "")))
  (if (r :ok)
    (do
      (each v (r :stack) (print (rb/render v)))
      0)
    (do
      (eprintf "ravel: %s\n" (rb/error-msg (r :error)))
      (rb/error-code (r :error)))))

(defn rb/cli-run-source
  [src name dump? &opt env]
  (def r (try
           (rb/run-source src name env)
           ([e] {:ok false :error e :stack @[]})))
  (rb/cli-report r dump?))

(defn rb/cli-repl
  [dump?]
  (def env (rb/new-env)) # REPL 内栈跨行保留
  (var buf "")
  (var running true)
  (while running
    (def raw (getline (if (empty? buf) "ravel> " "     > ")))
    # 注意：janet 的 getline 在 EOF 返回空 buffer（不是 nil），且含尾部换行
    (if (empty? raw)
      (set running false)
      (do
        (set buf (string buf (string/trimr (string raw)) "\n"))
        (def p (try (rb/lex buf "repl") ([e] {:error e})))
        (cond
          (get p :error)
          (do (eprintf "ravel: %s\n" (rb/error-msg (p :error)))
              (set buf ""))

          (p :incomplete) nil

          (do
            (when (> (length (p :stmts)) 0)
              (def r (try
                       (rb/run-source buf "repl" env)
                       ([e] {:ok false :error e :stack (env :rb-stack)})))
              # REPL 也报告栈（同 -e），错误走 stderr 且不退出
              (rb/cli-report r dump?))
            (set buf ""))))))
  0)

(defn rb/cli-serve-loop
  [dump?]
  # 能力层走显式注册表（§4.11）：核心不静态依赖 cap/，剔除 cap/ 后仍可装载
  (def encode (rb/cap-get :json/encode))
  (def env (rb/new-env)) # REQ-42：工作区（字典 + 栈）跨请求保留
  (var running true)
  (while running
    (def raw (getline ""))
    (if (empty? raw)
      (set running false)
      (do
        (def line (string/trimr (string raw)))
        (when (not (empty? line))
          (def r (try
                   (rb/run-source line "<serve>" env)
                   ([e] {:ok false :error e :stack @[]})))
          (when dump?
            (eprintf "dump: %s\n" (get r :code "")))
          (def msg (if (r :ok)
                     @{:type "result"
                       :ok true
                       :stack (map rb/render (r :stack))}
                     @{:type "result"
                       :ok false
                       :code (rb/error-code (r :error))
                       :error (rb/error-msg (r :error))}))
          (print (encode msg))
          (flush)))))
  0)

(defn rb/cli-main
  [argv]
  (def n (length argv))
  (var i 0)
  (var dump? false)
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

      (or (= a "-e") (= a "--eval"))
      (if (>= (inc i) n)
        (do (eprintf "ravel: -e 需要一个参数\n") (set exit (rb/exit-table :usage)))
        (do (set src (argv (inc i))) (set i (+ i 2))))

      (= a "--serve")
      (do (set serve? true) (++ i))

      (string/has-prefix? "-" a)
      (do (eprintf "ravel: 未知选项 %s\n" a) (set exit (rb/exit-table :usage)))

      (do (set file a) (++ i))))
  (cond
    (not= exit 0) exit
    done? exit
    serve? (do
             (if (nil? (rb/cap-get :json/encode))
               (do (eprintf "ravel: --serve 需要能力层 cap/json（REQ-37）\n")
                   (set exit (rb/exit-table :internal)))
               nil)
             (if (= exit 0) (rb/cli-serve-loop dump?) exit))
    (not (nil? src)) (rb/cli-run-source src "<-e>" dump?)
    (not (nil? file))
    (let [p (protect (slurp file))]
      (if (get p 0)
        (rb/cli-run-source (get p 1) file dump?)
        (do (eprintf "ravel: 无法读取 %s：%s\n" file (rb/error-msg (get p 1)))
            (rb/exit-table :io-read))))
    (rb/cli-repl dump?)))
