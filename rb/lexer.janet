# rb/lexer.janet —— 词法（REQ-03 / REQ-04 / §4.9.2）
#
# 产物：{:stmts @[stmt ...] :incomplete bool :reason kw}
#   stmt = tuple of token，**书写序**（左 → 右）
#   token = @{:kind :num|:str|:word|:block :value v :line n}
#           block 的 value = 块内的语句数组（见下）
#
# 规则（M0 已实现 / M1 待补）：
#   - 空白分隔；换行终结语句（REQ-04）
#   - `\` 行末 = 显式续行（REQ-04）
#   - `[` 未闭合 = 自动续行（REQ-04）
#   - `#` 行注释（规格未定，见 docs/DECISIONS.md D-02）
#   - `"..."` 基本转义；长/原样字符串留待 M1（v0.13）
#   - 块内换行 = 语句分隔（见 docs/DECISIONS.md D-03）
#
# 括号本身不参与反转（REQ-03）：块的内部**逐语句递归反转**，
# 语句之间保持书写序（写下的顺序 = 求值的顺序）。

(defn rb/lx-new
  [src name]
  @{:src src :n (length src) :i 0 :line 1 :name name
    :incomplete false :reason nil})

(defn rb/lx-eof [st] (>= (st :i) (st :n)))

(defn rb/lx-peek
  [st]
  (if (rb/lx-eof st) nil (string/slice (st :src) (st :i) (inc (st :i)))))

(defn rb/lx-adv [st] (++ (st :i)))

(defn rb/lx-nl [st]
  (++ (st :i))
  (++ (st :line)))

(defn rb/lx-space?
  [c]
  (or (= c " ") (= c "\t") (= c "\r")))

(defn rb/lx-term?
  "裸记号终止符。"
  [c]
  (or (nil? c)
      (rb/lx-space? c)
      (= c "\n")
      (= c "[") (= c "]") (= c "\"") (= c "#") (= c "\\")))

(defn rb/lx-string
  "读一个双引号字符串；EOF 未闭合 → incomplete（REPL 可续行）。"
  [st]
  (def line (st :line))
  (rb/lx-adv st) # 跳过开引号
  (def buf @"")
  (var done false)
  (while (not done)
    (def c (rb/lx-peek st))
    (cond
      (nil? c) (do
                 (put st :incomplete true)
                 (put st :reason :unterminated-string)
                 (set done true))
      (= c "\"") (do (rb/lx-adv st) (set done true))
      (= c "\n") (do
                   (put st :incomplete true)
                   (put st :reason :unterminated-string)
                   (set done true))
      (= c "\\") (do
                   (rb/lx-adv st)
                   (def e (rb/lx-peek st))
                   (cond
                     (= e "n") (buffer/push-string buf "\n")
                     (= e "t") (buffer/push-string buf "\t")
                     (= e "\"") (buffer/push-string buf "\"")
                     (= e "\\") (buffer/push-string buf "\\")
                     (nil? e) (do
                                (put st :incomplete true)
                                (put st :reason :unterminated-string)
                                (set done true))
                     (rb/raise (rb/exit-table :lex-bad-escape)
                               (string "非法转义 \\" e "（第 " line " 行）")))
                   (when (not (rb/lx-eof st)) (rb/lx-adv st)))
      (do (buffer/push-string buf c) (rb/lx-adv st))))
  {:kind :str :value (string buf) :line line})

(defn rb/lx-bare
  "读一个裸记号；能解析为数字则为 :num，否则 :word。"
  [st]
  (def line (st :line))
  (def start (st :i))
  (while (not (rb/lx-term? (rb/lx-peek st))) (rb/lx-adv st))
  (def s (string/slice (st :src) start (st :i)))
  (def num (scan-number s))
  (if (nil? num)
    {:kind :word :value s :line line}
    {:kind :num :value num :line line}))

(defn rb/lx-statements
  "读一串语句；in-block 时遇 `]` 结束，EOF 记为 incomplete。"
  [st in-block]
  (def stmts @[])
  (def cur @[])
  (defn flush []
    (when (not (empty? cur))
      (array/push stmts (tuple ;cur))
      (array/clear cur)))
  (var done false)
  (while (not done)
    (def c (rb/lx-peek st))
    (cond
      (nil? c) (do
                 (when in-block
                   (put st :incomplete true)
                   (put st :reason :unterminated-block))
                 (flush)
                 (set done true))
      (= c "]") (if in-block
                  (do (rb/lx-adv st) (flush) (set done true))
                  (rb/raise (rb/exit-table :syntax-unexpected-token)
                            (string "多余的 ]（第 " (st :line) " 行）")))
      (= c "\n") (do (rb/lx-nl st) (flush))
      (= c "\\") (do
                   (rb/lx-adv st)
                   (if (= (rb/lx-peek st) "\n")
                     (rb/lx-nl st)
                     (rb/raise (rb/exit-table :lex-bad-escape)
                               (string "孤立的反斜杠（第 " (st :line) " 行）"))))
      (= c "#") (while (and (not (nil? (rb/lx-peek st)))
                            (not= (rb/lx-peek st) "\n"))
                  (rb/lx-adv st))
      (rb/lx-space? c) (rb/lx-adv st)
      (= c "\"") (array/push cur (rb/lx-string st))
      (= c "[") (do
                  (def line (st :line))
                  (rb/lx-adv st)
                  (array/push cur {:kind :block
                                   :tokens (rb/lx-statements st true)
                                   :line line}))
      (array/push cur (rb/lx-bare st))))
  stmts)

(defn rb/lex
  "把源文本切成语句（书写序）。"
  [src &opt name]
  (def st (rb/lx-new src (or name "input")))
  (def stmts (rb/lx-statements st false))
  {:stmts stmts
   :incomplete (st :incomplete)
   :reason (st :reason)
   :name (st :name)})
