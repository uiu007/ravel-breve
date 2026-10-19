# rb/translate.janet —— 转译：递归反转 + 换名 + 定义行（REQ-01/02/03/05/31/33/34）
#
# 镜像原理：语句内 token 递归反转后逐个映射为宿主序：
#   take 2 "abcde"  →  (do (rb/push "abcde") (rb/push 2) (rb/take))
# 引号块 `[ ... ]` 压栈即数据（不求值，REQ-32），内部**逐语句递归反转**。
# 定义行 `名字 : [ 体 ]` 是**元层**：不参与镜像，顺序固定（REQ-34），
# 在装载期（= 转译期）注册进字典（REQ-33），运行期无栈效果。
#
# 注意：块 ↔ 语句序列互为递归，translate-stmts 需要前向声明（var + set）。

# 换名表：ravel 词名 → 宿主符号（一张表，便于审计与 see）
# 约定：**一个名字只有一种词性**（REQ-09）；本表优先于字典，
# 因此内置词不可被用户定义遮蔽。
(def rb/rename
  @{"dup" "rb/dup"
    "pop" "rb/pop"
    "swap" "rb/swap"
    "rot" "rb/rot"
    "-rot" "rb/-rot"
    "keep" "rb/keep"
    "dip" "rb/dip"
    "apply" "rb/apply"
    "call" "rb/apply"
    "," "rb/join2"
    ",," "rb/join3"
    "len" "rb/len"
    "first" "rb/first"
    "last" "rb/last"
    "take" "rb/take"
    "drop" "rb/drop"
    "reverse" "rb/reverse"
    "sort" "rb/sort"
    "at" "rb/at"
    "nth" "rb/at"
    "map" "rb/map"
    "filter" "rb/filter"
    "fold" "rb/fold"
    "split" "rb/split"
    "zip" "rb/zip"
    "show" "rb/show"
    "print" "rb/show"
    "wait" "rb/wait"
    "sleep" "rb/wait"
    "retry" "rb/retry"
    "log" "rb/log"
    "trim" "rb/trim"
    "replace" "rb/replace"
    "contains" "rb/contains"
    "starts-with" "rb/starts-with"
    "ends-with" "rb/ends-with"
    "lines" "rb/lines"
    "words" "rb/words"
    "to-string" "rb/to-string"
    "to-int" "rb/to-int"
    "say" "rb/say"
    "Utter" "rb/Utter"
    "to-json" "rb/to-json"
    "from-json" "rb/from-json"
    "Role" "rb/Role"
    "Content" "rb/Content"
    "=" "rb/eq"
    "!=" "rb/ne"
    "<" "rb/lt"
    ">" "rb/gt"
    "<=" "rb/le"
    ">=" "rb/ge"
    "not" "rb/not"
    "and" "rb/and"
    "or" "rb/or"
    "+" "rb/add"
    "-" "rb/sub"
    "*" "rb/mul"
    "/" "rb/div"
    "mod" "rb/mod"
    "abs" "rb/abs"
    "min" "rb/min"
    "max" "rb/max"
    "sum" "rb/sum"
    "if" "rb/if"
    "when" "rb/when"
    "unless" "rb/unless"
    "loop" "rb/loop"
    "while" "rb/while"
    "try" "rb/try"
    "recover" "rb/recover"
    "fail" "rb/fail"
    "assert" "rb/assert"
    "depth" "rb/depth"
    "dump" "rb/dump"
    "now" "rb/now"
    "env" "rb/env"
    "see" "rb/see"
    "doc" "rb/doc"})

(def rb/literals @{"true" "true" "false" "false" "nil" "nil"})

# 前向声明：块内递归需要 translate-stmts
(var rb/translate-stmts nil)

(defn rb/word-form
  "把一个方言词名转译为宿主调用形式。"
  [name]
  (def host (get rb/rename name))
  (cond
    (not (nil? host)) (string "(" host ")")
    (rb/dict? name) (string "(rb/call-word " (rb/render name) ")")
    (not (nil? (get rb/literals name))) (string "(rb/push " name ")")
    (rb/raise (rb/exit-table :syntax-unknown-word) (string "未知的词：" name))))

(defn rb/lit-code
  "把一个字面量值渲染为**构造该值的宿主序文本**（REQ-44）。
  注意：不能直接用 %q —— Janet 的 %q 把 tuple 打印成 (…)，回读会变成函数调用。"
  [v]
  (cond
    (tuple? v) (string "(tuple " (string/join (map rb/lit-code v) " ") ")")
    (table? v)
    (let [pairs (map (fn [k] [k (get v k)]) (keys v))
          sorted (sort pairs (fn [a b] (< (rb/lit-code (a 0)) (rb/lit-code (b 0)))))]
      (string "@{"
              (string/join (map (fn [p] (string (rb/lit-code (p 0)) " " (rb/lit-code (p 1))))
                                sorted)
                           " ")
              "}"))
    (rb/render v)))

(defn rb/translate-token
  [t]
  (case (t :kind)
    :num (string "(rb/push " (rb/render (t :value)) ")")
    :str (string "(rb/push " (rb/render (t :value)) ")")
    :block (string "(rb/quot (fn [] " (rb/translate-stmts (t :tokens)) "))")
    :seq-lit (string "(rb/push " (rb/lit-code (t :value)) ")")
    :map-lit (string "(rb/push " (rb/lit-code (t :value)) ")")
    :word (rb/word-form (t :value))
    (rb/raise (rb/exit-table :syntax-unexpected-token)
              (string "无法转译的记号：" (t :kind)))))

(defn rb/translate-forms
  "一条语句：token 书写序 → 求值序的形式文本数组。"
  [toks]
  (def out @[])
  (each t (reverse toks)
    (array/push out (rb/translate-token t)))
  out)

(defn rb/definition?
  "定义行 = `名字 : [ 体 ]`（恰好三个 token）。"
  [toks]
  (and (= (length toks) 3)
       (= ((toks 0) :kind) :word)
       (= ((toks 1) :kind) :word)
       (= ((toks 1) :value) ":")
       (= ((toks 2) :kind) :block)))

(defn rb/translate-def
  "元层特例：`名字 : [ 体 ]`（REQ-33/34）。"
  [toks]
  (def name ((toks 0) :value))
  (def body ((toks 2) :tokens))
  (def body-code (string "(fn [] " (rb/translate-stmts body) ")"))
  (rb/dict-declare name body-code)
  (string "(rb/define-word " (rb/render name) " " body-code " nil "
          (rb/render body-code) ")"))

(defn rb/stmt-forms
  "一条语句 → 形式文本数组（定义行是元层，不参与镜像）。"
  [toks]
  (if (rb/definition? toks)
    @[(rb/translate-def toks)]
    (rb/translate-forms toks)))

(set rb/translate-stmts
     (fn [stmts]
       # 语句序列 → 扁平的 (do form ...)；语句之间保持书写序。
       (def out @[])
       (each s stmts
         (each f (rb/stmt-forms s)
           (array/push out f)))
       (string "(do " (string/join out " ") ")")))
