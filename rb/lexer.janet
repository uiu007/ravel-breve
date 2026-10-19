# rb/lexer.janet —— 词法（REQ-03 / REQ-04 / §4.9.2）
#
# 产物：{:stmts @[stmt ...] :incomplete bool :reason kw}
#   stmt = tuple of token，**书写序**（左 → 右）
#   token = @{:kind :num|:str|:word|:block :value v :line n}
#           block 的 value = 块内的语句数组（见下）
#
# 规则（M0/M2 已实现）：
#   - 空白分隔；换行终结语句（REQ-04）
#   - `\` 行末 = 显式续行（REQ-04）
#   - `[` 未闭合 = 自动续行（REQ-04）
#   - `#` 行注释（REQ-39）
#   - `"..."` 基本转义；长/原样字符串留待后续
#   - `{ … }` 序列字面量、`H{ … }` 映射字面量（REQ-44：内部**只允许字面量**）
#   - 块内换行 = 语句分隔（REQ-40）
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

(defn rb/lx-peek-at
  "向前看第 k 个字符（k=0 等价 peek）。"
  [st k]
  (def i (+ (st :i) k))
  (if (>= i (st :n)) nil (string/slice (st :src) i (inc i))))

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
      (= c "[") (= c "]") (= c "{") (= c "}") (= c "\"") (= c "#") (= c "\\")))

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

# ---- 字面量（REQ-44）--------------------------------------------------
#
# 字面量是**数据**：不参与镜像、不被求值，整体压栈。
# 内部**只允许字面量**（数字 / 字符串 / 布尔 / nil / 嵌套字面量）；
# 出现词名即为语法错误（退出码 22）。

(defn rb/lx-lit-bad
  [st what]
  (rb/raise (rb/exit-table :syntax-bad-definition)
            (string "字面量非法：" what "（第 " (st :line) " 行）")))

(defn rb/lx-lit-skip
  "跳过字面量内部的空白 / 换行 / 注释。"
  [st]
  (var go true)
  (while go
    (def c (rb/lx-peek st))
    (cond
      (nil? c) (set go false)
      (rb/lx-space? c) (rb/lx-adv st)
      (= c "\n") (rb/lx-nl st)
      (= c "#") (while (and (not (nil? (rb/lx-peek st)))
                            (not= (rb/lx-peek st) "\n"))
                  (rb/lx-adv st))
      (set go false))))

(var rb/lx-lit-value nil)

(defn rb/lx-lit-seq
  "已消费 `{`；读到 `}` 为止，返回 tuple。"
  [st]
  (def items @[])
  (var done false)
  (while (not done)
    (rb/lx-lit-skip st)
    (def c (rb/lx-peek st))
    (cond
      (nil? c) (rb/lx-lit-bad st "序列未闭合（缺 }）")
      (= c "}") (do (rb/lx-adv st) (set done true))
      (array/push items (rb/lx-lit-value st))))
  (tuple ;items))

(defn rb/lx-lit-map
  "已消费 `H{`；读到 `}` 为止，返回 table（重复键：后者覆盖并告警，REQ-44）。"
  [st]
  (def t @{})
  (var done false)
  (while (not done)
    (rb/lx-lit-skip st)
    (def c (rb/lx-peek st))
    (cond
      (nil? c) (rb/lx-lit-bad st "映射未闭合（缺 }）")
      (= c "}") (do (rb/lx-adv st) (set done true))
      (do
        (def k (rb/lx-lit-value st))
        (rb/lx-lit-skip st)
        (def v (rb/lx-lit-value st))
        (when (has-key? t k)
          (eprintf "ravel: 警告：字面量重复键 %q\n" k))
        (put t k v))))
  t)

(set rb/lx-lit-value
     (fn [st]
       (rb/lx-lit-skip st)
       (def c (rb/lx-peek st))
       (cond
         (nil? c) (rb/lx-lit-bad st "意外的结束")
         (= c "\"") ((rb/lx-string st) :value)
         (= c "{") (do (rb/lx-adv st) (rb/lx-lit-seq st))
         (and (= c "H") (= (rb/lx-peek-at st 1) "{"))
         (do (rb/lx-adv st) (rb/lx-adv st) (rb/lx-lit-map st))
         (= c "}") (rb/lx-lit-bad st "多余的 }")
         (= c "]") (rb/lx-lit-bad st "字面量内不允许 ]")
         (= c "[") (rb/lx-lit-bad st "字面量内不允许引号块 [ ]")
         (do
           (def tok (rb/lx-bare st))
           (case (tok :kind)
             :num (tok :value)
             :word (case (tok :value)
                     "true" true
                     "false" false
                     "nil" nil
                     (rb/lx-lit-bad st (string "词名 " (tok :value) " 不能出现在字面量里")))
             (rb/lx-lit-bad st (string "记号 " (tok :kind))))))))

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
      (= c "}") (rb/raise (rb/exit-table :syntax-unexpected-token)
                           (string "多余的 }（第 " (st :line) " 行）"))
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
      (= c "{") (do
                  (def line (st :line))
                  (rb/lx-adv st)
                  (array/push cur {:kind :seq-lit
                                   :value (rb/lx-lit-seq st)
                                   :line line}))
      (and (= c "H") (= (rb/lx-peek-at st 1) "{")) (do
                  (def line (st :line))
                  (rb/lx-adv st)
                  (rb/lx-adv st)
                  (array/push cur {:kind :map-lit
                                   :value (rb/lx-lit-map st)
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
