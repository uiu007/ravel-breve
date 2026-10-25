# rb/line.janet —— REPL 的行编辑器（D-57）
#
# 目标：`ravel` 交互模式里能像在 shell 里那样编辑当前行，而且**两套键位共用一套状态**：
#
#   Emacs 模式（缺省）  单模式：C-a/C-e/C-b/C-f、M-b/M-f（或 C-←/C-→）、C-k/C-u/C-w…
#   Vim 模式            用 Vim 的「模式切换」思想：normal 下 i/a/I/A 进插入，
#                       插入下 Esc 回 normal，normal 下再 Esc 回 Emacs
#
# 「如无必要勿增实体」：只收每套里**最常用**的编辑动作。不实现 kill ring、
# 不实现补全、不做多行编辑、不做语法高亮。删除即丢弃（Vim 模式按 `u` 可撤销一步）。
#
# 键位表是**公开数据**（下面的三个 `*-keys` 表）：值是 `(fn [st] 动作)`，
# 动作 ∈ nil（继续）/ `:submit` / `:eof` / `:abort`。加键只需 `put`，不必改本文件。
#
# 错误处理（简单，但留好 API）：
#   - 行编辑器里任何异常 → 退回行模式（`getline`），stderr 提示一次；
#   - 扩展点：`rb/line-reader`（换整个读取器）、`rb/line-on-error`（换提示）、
#     三张键位表（加键）、`rb/line-edit` 的 `read-key` 参数（测试注入键序列）。

# 终端原语由宿主提供（src/main.c 的 `rb-term`）；没有它（裸 janet / 单元测试）
# 就退回行模式，本文件仍能装载 —— 间接层，见 D-29。
(def rb/line-term (dyn :rb-term))

(defn rb/line-tty?
  []
  (if rb/line-term (not (not ((rb/line-term :tty)))) false))

# ---- 键码 → 关键字（宿主侧约定见 src/main.c 顶部注释）---------------------

(def rb/line-keys
  @{-1 :eof -2 :esc -3 :unknown
    -101 :up -102 :down -103 :right -104 :left
    -105 :home -106 :end -107 :delete
    -108 :word-right -109 :word-left
    1 :ctrl-a 2 :ctrl-b 3 :ctrl-c 4 :ctrl-d 5 :ctrl-e 6 :ctrl-f
    9 :tab 10 :enter 11 :ctrl-k 12 :ctrl-l 13 :enter
    8 :backspace 14 :ctrl-n 16 :ctrl-p 21 :ctrl-u 23 :ctrl-w 127 :backspace})

(defn rb/line-key
  "宿主键码（整数）→ 关键字；可打印码位仍是整数（≥ 32）。"
  [code]
  (or (rb/line-keys code)
      (if (>= code 32) code :unknown)))

# ---- 码位 ↔ 文本 ---------------------------------------------------------

(defn rb/line-utf8
  "一个码位 → 字节数组。"
  [cp]
  (cond
    (< cp 0x80) @[cp]
    (< cp 0x800) @[(bor 0xc0 (brshift cp 6))
                   (bor 0x80 (band cp 0x3f))]
    (< cp 0x10000) @[(bor 0xe0 (brshift cp 12))
                     (bor 0x80 (band (brshift cp 6) 0x3f))
                     (bor 0x80 (band cp 0x3f))]
    @[(bor 0xf0 (brshift cp 18))
      (bor 0x80 (band (brshift cp 12) 0x3f))
      (bor 0x80 (band (brshift cp 6) 0x3f))
      (bor 0x80 (band cp 0x3f))]))

(defn rb/line-text
  "码位数组 → 字符串。"
  [cps]
  (def b (buffer/new 32))
  (each cp cps
    (each byte (rb/line-utf8 cp) (buffer/push-byte b byte)))
  (string b))

(defn rb/line-cps-of
  "字符串 → 码位数组（自己解 UTF-8，不依赖宿主的字符串库）。"
  [s]
  (def bs (string/bytes s))
  (def n (length bs))
  (def out @[])
  (var i 0)
  (while (< i n)
    (def b (bs i))
    (def d (cond
             (< b 0x80) [b 1]
             (= 0xc0 (band b 0xe0)) [(band b 0x1f) 2]
             (= 0xe0 (band b 0xf0)) [(band b 0x0f) 3]
             (= 0xf0 (band b 0xf8)) [(band b 0x07) 4]
             [0xfffd 1]))
    (def step (d 1))
    (var cp (d 0))
    (var k 1)
    (while (and (< k step) (< (+ i k) n))
      (set cp (bor (blshift cp 6) (band (bs (+ i k)) 0x3f)))
      (set k (+ k 1)))
    (array/push out cp)
    (set i (+ i step)))
  out)

(defn rb/line-key-name
  "键 → 便于文档/调试的名字。"
  [k]
  (cond
    (keyword? k) (string k)
    (number? k) (rb/line-text @[k])
    (string k)))

(defn rb/line-wide?
  "宽字符（东亚）粗判：只影响光标列号，不做换行计算。"
  [cp]
  (or (and (>= cp 0x1100) (<= cp 0x115f))
      (and (>= cp 0x2e80) (<= cp 0xa4cf))
      (and (>= cp 0xac00) (<= cp 0xd7a3))
      (and (>= cp 0xf900) (<= cp 0xfaff))
      (and (>= cp 0xff00) (<= cp 0xff60))
      (and (>= cp 0xffe0) (<= cp 0xffe6))
      (>= cp 0x20000)))

(defn rb/line-width
  "显示宽度（宽字符算 2 列）。"
  [s]
  (var w 0)
  (each cp (rb/line-cps-of s)
    (set w (+ w (if (rb/line-wide? cp) 2 1))))
  w)

(defn rb/line-word?
  "词字符：ASCII 字母数字、下划线、以及所有非 ASCII（CJK 当词字符）。"
  [cp]
  (or (and (>= cp 48) (<= cp 57))
      (and (>= cp 65) (<= cp 90))
      (and (>= cp 97) (<= cp 122))
      (= cp 95)
      (> cp 127)))

(defn rb/line-word-left
  "从 i 往左跳到上一个词的起点。"
  [cps i]
  (var j i)
  (while (and (> j 0) (not (rb/line-word? (cps (- j 1))))) (set j (- j 1)))
  (while (and (> j 0) (rb/line-word? (cps (- j 1)))) (set j (- j 1)))
  j)

(defn rb/line-word-right
  "从 i 往右跳过当前词与间隔，落在下一个词的起点（没有则行尾）。"
  [cps i]
  (def n (length cps))
  (var j i)
  (while (and (< j n) (rb/line-word? (cps j))) (set j (+ j 1)))
  (while (and (< j n) (not (rb/line-word? (cps j)))) (set j (+ j 1)))
  j)

# ---- 状态 -----------------------------------------------------------------

(defn rb/line-state
  "新建一行编辑状态。`mode` ∈ :emacs / :vim-normal / :vim-insert。"
  [&opt hist]
  @{:cps @[] :cur 0 :mode :emacs :pending nil
    :hist (or hist @[]) :hist-i (length (or hist @[])) :saved ""
    :undo @[] :action nil})

(defn- rb/line-undo!
  "改动前记一笔（只留最近 32 步）。"
  [st]
  (def u (st :undo))
  (array/push u @{:cps (array/slice (st :cps)) :cur (st :cur)})
  (when (> (length u) 32) (array/remove u 0))
  nil)

(defn rb/line-set!
  "整体替换文本（光标夹在合法范围）。"
  [st cps cur]
  (put st :cps (array/slice cps))
  (put st :cur (max 0 (min (length (st :cps)) cur)))
  st)

(defn rb/line-insert!
  [st cp]
  (rb/line-undo! st)
  (array/insert (st :cps) (st :cur) cp)
  (put st :cur (+ 1 (st :cur)))
  nil)

(defn rb/line-delete!
  "删除 [from, to)；返回删掉的码位。

  光标跟着走：**只**回退「删掉的码位里本来在光标左边的那些」（D-68）。
  少了这一步，退格删掉光标左边的字后光标不动，看上去就成了「光标停在原地、
  文字从它底下往左缩」——用起来和 Delete（删光标右边）几乎分辨不出来，
  而且连按退格会一个个吃掉光标已经越过的字。"
  [st from to]
  (def cps (st :cps))
  (def a (max 0 (min from (length cps))))
  (def b (max a (min to (length cps))))
  (if (>= a b)
    @[]
    (do
      (rb/line-undo! st)
      (def cur (st :cur))
      (def cut (array/slice cps a b))
      (repeat (- b a) (array/remove cps a))
      # 落在光标左侧的删除量：删 [cur, …)（Delete/C-k）时为 0，光标不动；
      # 删 [.., cur)（退格/C-u/C-w）时为全部，光标左移同样的距离。
      (def left (max 0 (- (min cur b) a)))
      (put st :cur (max 0 (min (- cur left) (length cps))))
      cut)))

# ---- 历史 -----------------------------------------------------------------

(defn rb/line-hist-goto
  "i = -1 表示「未进入历史」（空行）；越界下滑时恢复 saved。"
  [st i]
  (def h (st :hist))
  (cond
    (empty? h) nil
    (< i 0) (do (put st :hist-i -1) (rb/line-set! st @[] 0))
    (>= i (length h))
    (do
      (put st :hist-i (length h))
      (rb/line-set! st (rb/line-cps-of (st :saved)) 0))
    (do
      (when (= (st :hist-i) (length h))
        (put st :saved (rb/line-text (st :cps))))
      (put st :hist-i i)
      (rb/line-set! st (rb/line-cps-of (h i)) 0)))
  nil)

(defn rb/line-hist-prev
  [st]
  (def i (st :hist-i))
  (rb/line-hist-goto st (if (< i 1) 0 (- i 1))))

(defn rb/line-hist-next
  [st]
  (def i (st :hist-i))
  (when (>= i 0) (rb/line-hist-goto st (+ i 1))))

# ---- Emacs 键位 -----------------------------------------------------------

(def rb/line-emacs-keys @{})

(defn- emacs! [k f] (put rb/line-emacs-keys k f) nil)

(emacs! :ctrl-a (fn [st] (put st :cur 0) nil))
(emacs! :ctrl-e (fn [st] (put st :cur (length (st :cps))) nil))
(emacs! :ctrl-b (fn [st] (put st :cur (max 0 (- (st :cur) 1))) nil))
(emacs! :ctrl-f (fn [st] (put st :cur (min (length (st :cps)) (+ 1 (st :cur)))) nil))
(emacs! :left (get rb/line-emacs-keys :ctrl-b))
(emacs! :right (get rb/line-emacs-keys :ctrl-f))
(emacs! :home (get rb/line-emacs-keys :ctrl-a))
(emacs! :end (get rb/line-emacs-keys :ctrl-e))
(emacs! :word-left (fn [st] (put st :cur (rb/line-word-left (st :cps) (st :cur))) nil))
(emacs! :word-right (fn [st] (put st :cur (rb/line-word-right (st :cps) (st :cur))) nil))
(emacs! :ctrl-k (fn [st] (rb/line-delete! st (st :cur) (length (st :cps))) nil))
(emacs! :ctrl-u (fn [st] (rb/line-delete! st 0 (st :cur)) nil))
(emacs! :ctrl-w (fn [st]
                  (rb/line-delete! st (rb/line-word-left (st :cps) (st :cur)) (st :cur))
                  nil))
(emacs! :backspace (fn [st]
                     (when (> (st :cur) 0)
                       (rb/line-delete! st (- (st :cur) 1) (st :cur)))
                     nil))
(emacs! :delete (fn [st] (rb/line-delete! st (st :cur) (+ 1 (st :cur))) nil))
(emacs! :ctrl-d (fn [st]
                  (if (empty? (st :cps))
                    :eof
                    (do (rb/line-delete! st (st :cur) (+ 1 (st :cur))) nil))))
(emacs! :ctrl-l (fn [st] nil))
(emacs! :ctrl-c (fn [st] :abort))
(emacs! :enter (fn [st] :submit))
(emacs! :tab (fn [st] (rb/line-insert! st 32) (rb/line-insert! st 32) nil))
(emacs! :up (fn [st] (rb/line-hist-prev st) nil))
(emacs! :down (fn [st] (rb/line-hist-next st) nil))
(emacs! :ctrl-p (get rb/line-emacs-keys :up))
(emacs! :ctrl-n (get rb/line-emacs-keys :down))
# Esc = 切到 Vim 模式（「用 Vim 的模式切换思想」的入口）
(emacs! :esc (fn [st] (put st :mode :vim-normal) (put st :pending nil) nil))

# ---- Vim normal 键位 ------------------------------------------------------

(def rb/line-vim-normal-keys @{})

(defn- vim! [k f] (put rb/line-vim-normal-keys k f) nil)

(defn- vim-cancel [st] (put st :pending nil) nil)

(vim! 104 (fn [st] (put st :cur (max 0 (- (st :cur) 1))) nil))                  # h
(vim! 108 (fn [st] (put st :cur (min (length (st :cps)) (+ 1 (st :cur)))) nil)) # l
(vim! 48 (fn [st] (put st :cur 0) nil))                                         # 0
(vim! 36 (fn [st] (put st :cur (length (st :cps))) nil))                        # $
(vim! 119 (fn [st] (put st :cur (rb/line-word-right (st :cps) (st :cur))) nil)) # w
(vim! 98 (fn [st] (put st :cur (rb/line-word-left (st :cps) (st :cur))) nil))   # b
(vim! 105 (fn [st] (put st :mode :vim-insert) nil))                             # i
(vim! 97 (fn [st]                                                               # a
           (put st :cur (min (length (st :cps)) (+ 1 (st :cur))))
           (put st :mode :vim-insert) nil))
(vim! 73 (fn [st] (put st :cur 0) (put st :mode :vim-insert) nil))              # I
(vim! 65 (fn [st]                                                               # A
           (put st :cur (length (st :cps)))
           (put st :mode :vim-insert) nil))
(vim! 120 (fn [st] (rb/line-delete! st (st :cur) (+ 1 (st :cur))) nil))          # x
(vim! 68 (fn [st] (rb/line-delete! st (st :cur) (length (st :cps))) nil))        # D
(vim! 100 (fn [st]                                                              # d
            (if (= (st :pending) :d)
              (do (rb/line-delete! st 0 (length (st :cps)))
                  (put st :cur 0)
                  (put st :pending nil))
              (put st :pending :d))
            nil))
(vim! 117 (fn [st]                                                             # u
            (def u (st :undo))
            (when (> (length u) 0)
              (def s (last u))
              (array/remove u (- (length u) 1))
              (put st :cps (array/slice (s :cps)))
              (put st :cur (s :cur)))
            nil))
(vim! :left (get rb/line-vim-normal-keys 104))
(vim! :right (get rb/line-vim-normal-keys 108))
(vim! :home (get rb/line-vim-normal-keys 48))
(vim! :end (get rb/line-vim-normal-keys 36))
(vim! :word-left (get rb/line-vim-normal-keys 98))
(vim! :word-right (get rb/line-vim-normal-keys 119))
(vim! :backspace (get rb/line-vim-normal-keys 104))
(vim! :delete (get rb/line-vim-normal-keys 120))
(vim! :enter (fn [st] :submit))
(vim! :ctrl-c (fn [st] :abort))
(vim! :ctrl-d (fn [st] (if (empty? (st :cps)) :eof nil)))
(vim! :up (fn [st] (rb/line-hist-prev st) nil))
(vim! :down (fn [st] (rb/line-hist-next st) nil))
(vim! :unknown vim-cancel)
# normal 下再按 Esc = 回 Emacs 模式（两级退出，不新增按键）
(vim! :esc (fn [st] (put st :mode :emacs) (put st :pending nil) nil))

# ---- Vim 插入键位 ---------------------------------------------------------

(def rb/line-vim-insert-keys @{})

(defn- ins! [k f] (put rb/line-vim-insert-keys k f) nil)

(ins! :esc (fn [st]                                # 同 Vim：退出插入时光标左移一格
            (put st :cur (max 0 (- (st :cur) 1)))
            (put st :mode :vim-normal)
            (put st :pending nil)
            nil))
(ins! :enter (fn [st] :submit))
(ins! :ctrl-c (fn [st] :abort))
(ins! :ctrl-d (fn [st] (if (empty? (st :cps)) :eof nil)))
(ins! :backspace (fn [st]
                   (when (> (st :cur) 0)
                     (rb/line-delete! st (- (st :cur) 1) (st :cur)))
                   nil))
(ins! :delete (fn [st] (rb/line-delete! st (st :cur) (+ 1 (st :cur))) nil))
(ins! :left (get rb/line-emacs-keys :ctrl-b))
(ins! :right (get rb/line-emacs-keys :ctrl-f))
(ins! :home (get rb/line-emacs-keys :ctrl-a))
(ins! :end (get rb/line-emacs-keys :ctrl-e))
(ins! :word-left (get rb/line-emacs-keys :word-left))
(ins! :word-right (get rb/line-emacs-keys :word-right))
(ins! :ctrl-a (get rb/line-emacs-keys :ctrl-a))
(ins! :ctrl-e (get rb/line-emacs-keys :ctrl-e))
(ins! :ctrl-k (get rb/line-emacs-keys :ctrl-k))
(ins! :up (get rb/line-emacs-keys :up))
(ins! :down (get rb/line-emacs-keys :down))

(defn rb/line-keymap
  "模式的键位表（扩展点：`put` 进去即可加键）。"
  [mode]
  (case mode
    :vim-normal rb/line-vim-normal-keys
    :vim-insert rb/line-vim-insert-keys
    rb/line-emacs-keys))

(defn rb/line-apply-key!
  "一个键 → 动作，并写回 `(st :action)`。**公开**：键位可扩展。"
  [st code]
  (def k (rb/line-key code))
  (def f (get (rb/line-keymap (st :mode)) k))
  (def act
    (cond
      (= k :eof) :eof                                  # 键源耗尽 / stdin 关闭
      f (f st)
      (number? k)
      (if (= (st :mode) :vim-normal)
        (vim-cancel st)                              # normal 下字符不是输入
        (do (rb/line-insert! st k) nil))
      (do (put st :pending nil) nil)))
  (put st :action act)
  act)

# ---- 绘制 ---------------------------------------------------------------

(defn rb/line-prompt
  "提示符 + 模式标记：Vim 的两级模式必须**看得见**，否则会误按。"
  [prompt mode]
  (case mode
    :vim-normal (string prompt "-- NORMAL -- ")
    :vim-insert (string prompt "-- INSERT -- ")
    prompt))

(defn rb/line-draw
  [prompt st]
  (def p (rb/line-prompt prompt (st :mode)))
  (def cps (st :cps))
  (def before (rb/line-text (array/slice cps 0 (st :cur))))
  (def out (buffer/new 64))
  (buffer/push-string out "\r\e[K")
  (buffer/push-string out p)
  (buffer/push-string out (rb/line-text cps))
  (buffer/push-string out "\r")
  (def col (+ (rb/line-width p) (rb/line-width before)))
  (when (> col 0) (buffer/push-string out (string "\e[" col "C")))
  (file/write stdout out)
  (file/flush stdout)
  st)

# ---- 主循环 -------------------------------------------------------------

(defn rb/line-raw-key
  "读一个键码（宿主原语）；没有宿主原语时返回 -1（EOF）。"
  []
  (if rb/line-term ((rb/line-term :read-key)) -1))

(defn rb/line-edit
  "编辑一行，返回字符串；EOF / C-c 返回 nil。

  `hist`     历史数组（只读；追加由调用方负责）
  `read-key` 键源，缺省用宿主原语。测试可注入 `(fn [] 键码)`，无需终端。"
  [prompt &opt hist read-key]
  (def st (rb/line-state hist))
  (def keyfn (or read-key rb/line-raw-key))
  (def draw? (rb/line-tty?))
  (when draw? (rb/line-draw prompt st))
  (var running true)
  (while running
    (def act (rb/line-apply-key! st (keyfn)))
    (case act
      :submit (set running false)
      :eof (set running false)
      :abort (set running false)
      (when draw? (rb/line-draw prompt st))))
  (when draw?
    (file/write stdout "\r\n")
    (file/flush stdout))
  (def act (st :action))
  (if (or (= act :eof) (= act :abort))
    nil
    (rb/line-text (st :cps))))

# ---- 对外：REPL 用它读一行（含兜底与扩展点）-----------------------------

(def rb/line-on-error
  "行编辑器出错时的提示方式（扩展点）。"
  (fn [e]
    (eprintf "ravel: 行编辑器不可用（%s），改用行模式\n" (rb/error-msg e))))

(defn rb/line-plain
  "行模式：`getline` 并去掉尾部换行；EOF 返回 nil。"
  [prompt]
  (def raw (getline prompt))
  (when (not (empty? raw))
    (string (string/trimr (string raw)))))

(defn rb/line-read-tty
  "原始终端读一行：原始模式只在这一行读取期间开启，求值期间回到熟模式。"
  [prompt hist]
  (if (not ((rb/line-term :raw-on)))
    (rb/line-plain prompt)
    (do
      (def r (try
               (rb/line-edit prompt hist)
               ([e] (rb/line-on-error e) :__fallback__)))
      ((rb/line-term :raw-off))
      (if (= r :__fallback__) (rb/line-plain prompt) r))))

(var rb/line-reader
  (fn [prompt hist]
    (if (rb/line-tty?)
      (rb/line-read-tty prompt hist)
      (rb/line-plain prompt))))

(defn rb/line-read
  "读一行的**唯一入口**（扩展点：`(set rb/line-reader (fn [prompt hist] ...))`）。

  读一行并返回字符串；EOF 返回 nil。"
  [prompt &opt hist]
  (rb/line-reader prompt (or hist @[])))
