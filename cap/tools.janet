# cap/tools.janet —— 能力层：默认工具包（P1，D-61）
#
# 为什么在能力层：`edit` / `grep` / `glob` / `shell` 都要碰文件系统与进程，
# 而核心词表**不含** net / file / http（附录 D、REQ-37）。它们在核心里只体现为
# **工具表里的表项**（REQ-48 的 `deftool` 契约同构）：名字 + 描述 + 一个 0 元函数，
# 参数由 `rb/tool-run` 先 `(rb/push args)` 压栈，函数自己 `rb/pop` 取。
#
# 装载方式：本文件注册能力键 `:tools/install`；`rb/ws-new` 建工作区时若该能力在场，
# 就把这四个工具装进新工作区的工具表（`--core-only` 剔除 cap/ 后自然没有）。
#
# 安全（D-60 + D-61）：
#   - 三个文件工具一律先过 `cap/fs-check`（沙箱根 = RB_SANDBOX 或当前目录）。
#   - `shell` 需要一个**前置设定** `allow-shell`（REQ-67）：由模式声明，缺省开；
#     `flag-set false "allow-shell"` 或 `RB_ALLOW_SHELL=0` 关掉它。

# ---- 小工具 ---------------------------------------------------------------

(def cap/tool-aliases
  "参数别名表：规范名 → 模型常写的别的叫法（REQ-68）。
   只做「认」不做语义变换——`command` 与 `cmd` 指同一件事，程序不该因为它换了个
   名字就报废一整轮（用户在 DeepSeek/OpenCode 上正是踩了 `command` 这个坑）。"
  @{"cmd" @["command" "shell_command"]
    "path" @["file_path" "filepath" "file" "filename"]
    "old" @["old_string" "old_text"]
    "new" @["new_string" "new_text"]
    "content" @["contents"]
    "pattern" @["query" "regex"]
    "dir" @["directory" "base"]
    "offset" @["start_line" "start"]
    "limit" @["max_lines" "count"]
    "src" @["source" "code" "program"]
    "plan" @["plan_text"]
    "url" @[]})

(defn cap/tool-arg-names
  "某个参数可接受的键（规范名 + 别名），错误信息与工具描述都用它。"
  [k]
  (def out @[k])
  (each a (get cap/tool-aliases k @[]) (array/push out a))
  (tuple ;out))

(defn cap/tool-arg
  "从工具参数表里取一个字符串字段（缺省 nil）；别名也认（REQ-68）。"
  [args k]
  (var v (if (dictionary? args) (get args k) nil))
  (when (and (nil? v) (dictionary? args))
    (each alt (get cap/tool-aliases k @[])
      (when (nil? v) (set v (get args alt)))))
  (if (nil? v) nil (string v)))

(defn cap/tool-num
  "取一个数字参数（模型有时给字符串 3，也认）。缺省/认不出 → nil。别名也认。"
  [args k]
  (def s (cap/tool-arg args k))
  (def v (if (nil? s) (if (dictionary? args) (get args k) nil) s))
  (cond
    (number? v) v
    (string? v) (scan-number v)
    true nil))

(defn cap/tool-join
  [xs sep]
  (var out "")
  (var first true)
  (each x xs
    (when (not first) (set out (string out sep)))
    (set out (string out x))
    (set first false))
  out)

(defn cap/tool-require
  "必填字段；缺了就抛**参数错误**（REQ-68）：`rb/tool-run` 认 `:rb-arg`，
   模型发起的调用会把它当工具结果回给模型（可自纠），`invoke` 仍按 60 报错。"
  [args k]
  (def v (cap/tool-arg args k))
  (when (nil? v)
    (error @{:rb-arg true
             :rb-msg (string "缺少参数 " k "（接受："
                             (cap/tool-join (cap/tool-arg-names k) " / ") "）")}))
  v)

(defn cap/tool-str
  "把工具结果变成字符串（结果会以 role \"tool\" 的 content 回给模型）。"
  [v]
  (if (string? v) v (string/format "%q" v)))

(defn cap/tool-lines
  "按行切（保留空行；不用 PEG）。"
  [text]
  (def out @[])
  (var cur @"")
  (each b (string/bytes text)
    (if (= b 10)
      (do (array/push out (string cur)) (set cur @""))
      (buffer/push-byte cur b)))
  (array/push out (string cur))
  (tuple ;out))

(defn cap/tool-dir?
  [p]
  (def st (os/stat p))
  (and st (= (st :mode) :directory)))

# ---- edit -----------------------------------------------------------------

(defn cap/tool-edit
  "edit：{ path, old, new } —— 把文件里**所有** old 换成 new（字面量，非正则）。
   返回一行摘要；一处都没找到 → 报错（模型通常把 old 抄错了）。"
  []
  (def args (rb/pop))
  (def path (cap/tool-require args "path"))
  (def old (cap/tool-require args "old"))
  (def new (cap/tool-arg args "new"))
  (cap/fs-check path "write")
  (def text (slurp path))
  (def hits (length (string/find-all old text)))
  (when (= hits 0) (error (string "edit：文件里找不到 old（" path "）")))
  (spit path (string/replace-all old (or new "") text))
  (rb/push (string "已改 " hits " 处：" path))
  nil)

(defn cap/tool-read
  "read：{ path, offset?, limit? } —— 带行号读文本（dsh 的 read）。
   offset 从 1 起；limit 缺省 400、上限 2000；被截断时尾附续读提示。"
  []
  (def args (rb/pop))
  (def path (cap/tool-require args "path"))
  (cap/fs-check path)
  (def text (cap/fs-read path))
  (when (nil? text) (error (string "read：读不到 " path)))
  (def lines0 (cap/tool-lines text))
  # 末尾的换行不该算成「又一行」（`a\n` 是一行，不是两行）
  (def total (if (and (> (length lines0) 1) (= "" (get lines0 (dec (length lines0)))))
               (dec (length lines0))
               (length lines0)))
  (def lines lines0)
  (def off (max 1 (or (cap/tool-num args "offset") 1)))
  (def lim (min 2000 (max 1 (or (cap/tool-num args "limit") 400))))
  (def out @[])
  (var i off)
  (while (and (<= i total) (< (length out) lim))
    (array/push out (string i "  " (lines (dec i))))
    (++ i))
  (def tail (if (< i total)
              (string "\n[还有 " (- total (dec i)) " 行：用 offset " i " 接着读]")
              ""))
  (rb/push (string (cap/tool-join out "\n") tail))
  nil)

(defn cap/tool-write
  "write：{ path, content } —— 原子替换整个文件（同目录临时文件 + rename）。
   返回写入的字节数（dsh 的 write）。"
  []
  (def args (rb/pop))
  (def path (cap/tool-require args "path"))
  (def content (or (cap/tool-arg args "content") ""))
  (cap/fs-check path "write")
  (def tmp (string path ".rb-tmp-" (os/getpid)))
  (def f (file/open tmp :w))
  (when (nil? f) (error (string "write：写不进临时文件 " tmp)))
  (file/write f content)
  (file/close f)
  (def r (protect (os/rename tmp path)))
  (when (not (get r 0))
    (protect (os/rm tmp))
    (error (string "write：替换失败 " path "（" (get r 1) "）")))
  (rb/push (length content))
  nil)

# ---- glob（`*` / `?` 段内匹配，`**` 任意层）--------------------------------

(defn cap/tool-glob-seg
  "段内匹配：`*` = 任意串，`?` = 一个字符；其余字面量。"
  [pat s]
  (def p (string/bytes pat))
  (def t (string/bytes s))
  (var pi 0)
  (var si 0)
  (var star -1)
  (var mark 0)
  (while (< si (length t))
    (cond
      (and (< pi (length p)) (or (= (p pi) (t si)) (= (p pi) 63)))
      (do (++ pi) (++ si))

      (and (< pi (length p)) (= (p pi) 42))
      (do (set star pi) (set mark si) (++ pi))

      (>= star 0)
      (do (set pi (inc star)) (++ mark) (set si mark))

      true (break)))
  (while (and (< pi (length p)) (= (p pi) 42)) (++ pi))
  (= pi (length p)))

(defn cap/tool-glob-walk
  "把 pattern 按 `/` 切段，递归走文件树；把命中路径推进 out。"
  [segs i dir out limit]
  (when (>= (length out) limit) (break))
  (if (= i (length segs))
    (when (os/stat dir) (array/push out dir))
    (do
      (def seg (segs i))
      (if (= seg "**")
        (do
          # `**` 吃掉零层或多层
          (cap/tool-glob-walk segs (inc i) dir out limit)
          (when (< (length out) limit)
            (each e (os/dir dir)
              (if (not (or (= e ".") (= e "..")))
                (let [p (string dir "/" e)]
                  (when (cap/tool-dir? p)
                    (cap/tool-glob-walk segs i p out limit)))))))
        (do
          (each e (os/dir dir)
            (when (and (not (or (= e ".") (= e "..")))
                       (cap/tool-glob-seg seg e))
              (cap/tool-glob-walk segs (inc i) (string dir "/" e) out limit))))))))

(defn cap/tool-glob
  "glob：{ pattern, dir? } —— 从 dir（缺省 = 沙箱根/当前目录）出发按 pattern 找路径。
   结果一行一个，最多 200 条。"
  []
  (def args (rb/pop))
  (def pattern (cap/tool-require args "pattern"))
  (def dir0 (or (cap/tool-arg args "dir") "."))
  (cap/fs-check dir0)
  (def segs (string/split "/" pattern))
  (def out @[])
  (cap/tool-glob-walk segs 0 dir0 out 200)
  (def rel @[])
  (each p out
    (array/push rel (if (string/has-prefix? "./" p) (string/slice p 2) p)))
  (rb/push (if (empty? rel) "" (cap/tool-join rel "\n")))
  nil)

# ---- grep -----------------------------------------------------------------

(defn cap/tool-grep-scan
  "在一棵树下按**字面量**找；每行输出 `path:行号: 文本`，最多 limit 条。"
  [path needle out limit bytes?]
  (when (>= (length out) limit) (break))
  (if (cap/tool-dir? path)
    (each e (os/dir path)
      (when (not (or (= e ".") (= e "..") (string/has-prefix? "." e)))
        (cap/tool-grep-scan (string path "/" e) needle out limit bytes?)))
    (do
      (def text (cap/fs-read path))
      (when text
        (var n 0)
        (each line (cap/tool-lines text)
          (++ n)
          (when (and (< (length out) limit) (string/find needle line))
            (array/push out (string path ":" n ": " line))))))))

(defn cap/tool-grep
  "grep：{ pattern, path? } —— 字面量搜索（不是正则）；path 缺省 `.`。"
  []
  (def args (rb/pop))
  (def needle (cap/tool-require args "pattern"))
  (def path (or (cap/tool-arg args "path") "."))
  (cap/fs-check path)
  (def out @[])
  (cap/tool-grep-scan path needle out 200 false)
  (rb/push (if (empty? out) "" (cap/tool-join out "\n")))
  nil)

# ---- shell（默认关闭）-----------------------------------------------------

(var cap/tool-sh-seq 0)

(defn cap/tool-tmp-file
  "一个临时文件路径（janet 1.42 没有 os/tmpname）：TMPDIR/pid/序号。"
  []
  (++ cap/tool-sh-seq)
  (string (or (os/getenv "TMPDIR") "/tmp") "/rb-sh-" (os/getpid) "-" cap/tool-sh-seq))

(defn cap/shell-timeout
  "shell 工具的超时秒数（D-79）：`RB_SHELL_TIMEOUT`，缺省 60；<=0 表示不限（回归旧行为）。"
  []
  (def v (os/getenv "RB_SHELL_TIMEOUT"))
  (def n (if v (scan-number v) nil))
  (if (and (number? n) (> n 0)) (math/floor n) 60))

(defn cap/tool-shell
  "shell：{ cmd } —— 跑一句 `sh -c`，返回 stdout（+ stderr）。
   需要前置设定 `allow-shell`（模式声明，缺省开；REQ-67）：一句 sh -c 等于绕过文件沙箱，
   所以它有自己的开关，而不是跟文件工具共用沙箱。

   超时（D-79）：方言是**单线程**的，一句挂住的命令（`sleep 600`、等 stdin 的 `cat`、
   交互式程序）会把整个进程连同桥一起钉死，前端表现为「发送后卡死」。
   所以缺省挂 60 秒的闸，超时就杀掉并**把超时当结果还给模型**
   （模型能自己改主意，用户也能看到原因），而不是让进程消失。"
  []
  (def args (rb/pop))
  (def cmd (cap/tool-require args "cmd"))
  (when (not (rb/flag-on? "allow-shell"))
    (error (string "shell 已被关掉：allow-shell 设定为 false（它等价于绕过文件沙箱，D-61）；"
                   "打开：flag-set true \"allow-shell\"，或置 RB_ALLOW_SHELL=1")))
  # 要**捕获**输出：os/execute 会把子进程 stdio 直接接给本进程（janet 1.42 的 :p 只是查 PATH），
  # 所以这里自己开一根管道（os/spawn + 读完再 wait）。
  (def secs (cap/shell-timeout))
  (def tmp (cap/tool-tmp-file))
  (def f (file/open tmp :w))
  (var gated (> secs 0))
  # `timeout`（coreutils）是闸；-k 5 保证 TERM 不走时还有 KILL。没有它的系统退化成旧行为。
  (def argv (if gated
              @["timeout" "-k" "5" "-s" "TERM" (string secs) "/bin/sh" "-c" cmd]
              @["/bin/sh" "-c" cmd]))
  (def r (protect (os/spawn argv :p {:out f :err f})))
  (def proc (if (get r 0) (get r 1) nil))
  (def code
    (cond
      proc (os/proc-wait proc)
      gated (do   # 没有 timeout 命令：退回不限时的老路
              (set gated false)
              (os/proc-wait (os/spawn ["/bin/sh" "-c" cmd] :p {:out f :err f})))
      (do
        (file/close f)
        (protect (os/rm tmp))
        (error (string "shell 起不来：" (get r 1))))))
  (file/close f)
  (def out (string (slurp tmp)))
  (protect (os/rm tmp))
  (rb/push
    (cond
      (= code 0) out
      (and gated (or (= code 124) (= code 137)))
      (string out "\n[超时 " secs "s，已杀掉；要更久就设 RB_SHELL_TIMEOUT=<秒>（<=0 不限）]")
      (string out "\n[退出码 " code "]")))
  nil)

# ---- 安装 -----------------------------------------------------------------

(defn cap/tool-param-desc
  "参数描述：正文 + 「（别名：…）」（没有别名就不写空括号）。"
  [k d]
  (def alts (tuple/slice (cap/tool-arg-names k) 1))
  (if (= 0 (length alts))
    d
    (string d "（别名：" (cap/tool-join alts " / ") "）")))

(defn cap/tool-str-param
  [k d]
  @{:type "string" :description (cap/tool-param-desc k d)})

(defn cap/tool-num-param
  [k d]
  @{:type "number" :description (cap/tool-param-desc k d)})

(def cap/tools-built
  # 只建一次：函数对象在 `ws-new`、预置 `default` 模式、`mode-of` 之间**共享**，
  # 于是模式的 round-trip 可以用 `deep=` 直接比（D-59 / D-61）。
  #
  # `:params` 是给模型的**参数模式**（JSON Schema，REQ-68）：写了模型就按名字填，
  # 没写（v1.0n 之前）等于让模型猜——猜 `command` 而不是 `cmd`，整轮 60。
  @{"read" @{:desc "读文件，一行一个「行号 + 文本」，超长会截断并提示续读。"
            :params @{:type "object"
                      :properties @{"path" (cap/tool-str-param "path" "文件路径")
                                    "offset" (cap/tool-num-param "offset" "起始行号，从 1 起")
                                    "limit" (cap/tool-num-param "limit" "读多少行，缺省 400")}
                      :required @["path"]}
            :fn cap/tool-read}
    "write" @{:desc "写文件，原子替换整个文件，返回写入的字节数。"
             :params @{:type "object"
                       :properties @{"path" (cap/tool-str-param "path" "文件路径")
                                     "content" (cap/tool-str-param "content" "完整的新内容")}
                       :required @["path" "content"]}
             :fn cap/tool-write}
    "edit" @{:desc "改文件，把 old 的所有出现换成 new（字面量，不是正则）。"
            :params @{:type "object"
                      :properties @{"path" (cap/tool-str-param "path" "文件路径")
                                    "old" (cap/tool-str-param "old" "要替换掉的原文")
                                    "new" (cap/tool-str-param "new" "替换成什么")}
                      :required @["path" "old"]}
            :fn cap/tool-edit}
    "grep" @{:desc "搜内容（字面量匹配），输出 path:行号: 文本。"
            :params @{:type "object"
                      :properties @{"pattern" (cap/tool-str-param "pattern" "要找的文本")
                                    "path" (cap/tool-str-param "path" "在哪个目录/文件里找，缺省当前目录")}
                      :required @["pattern"]}
            :fn cap/tool-grep}
    "glob" @{:desc "找文件，支持 * / ? / **，一行一个路径。"
            :params @{:type "object"
                      :properties @{"pattern" (cap/tool-str-param "pattern" "路径模式，如 src/**/*.janet")
                                    "dir" (cap/tool-str-param "dir" "从哪个目录开始，缺省当前目录")}
                      :required @["pattern"]}
            :fn cap/tool-glob}
    "shell" @{:desc "跑一条 shell 命令，返回 stdout + stderr；需要 allow-shell 设定（怕绕过沙箱时可关）。"
             :params @{:type "object"
                       :properties @{"cmd" (cap/tool-str-param "cmd" "要执行的命令，交给 sh -c")}
                       :required @["cmd"]}
             :fn cap/tool-shell}})

(defn cap/tools-default
  "默认工具表的一份浅拷贝（函数对象共享）。"
  []
  (table/clone cap/tools-built))

(defn cap/tools-install!
  "把默认工具装进一个工作区的工具表（ws-new 调用；重复调用无副作用）。"
  [tools]
  (eachp [n d] cap/tools-built (put tools n d))
  tools)

(def cap/tools-gates
  "工具的前置设定：这个工具需要一个开关生效（REQ-67）。
   目前只有 shell——其余文件工具靠 REQ-53 的沙箱约束，不需要开关。
   模式声明了带前置设定的工具，就该把设定一起带上（`--modes` 会印出来）。"
  @{"shell" "allow-shell"})

(defn cap/tools-gate-table
  "前置设定表的一份拷贝（能力键 `:tools/gates`）。"
  []
  (table/clone cap/tools-gates))

(rb/cap-put :tools/gates cap/tools-gate-table)
(rb/cap-put :tools/install cap/tools-install!)
(rb/cap-put :tools/defaults cap/tools-default)
