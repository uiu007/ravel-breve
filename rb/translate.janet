# rb/translate.janet —— 转译：递归反转 + 换名 + 定义行（REQ-01/02/03/05/31/33/34）
#
# 镜像原理：语句内 token 递归反转后逐个映射为宿主序：
#   take 2 "abcde"  →  (do (rb/push "abcde") (rb/push 2) (rb/take))
# 引号块 `[ ... ]` 压栈即数据（不求值，REQ-32），内部**逐语句递归反转**。
# 定义行 `名字 : [ 体 ]` 是**元层**：不参与镜像，顺序固定（REQ-34），
# 在装载期（= 转译期）注册进字典（REQ-33），运行期无栈效果。
#
# 注意：块 ↔ 语句序列互为递归，translate-stmts 需要前向声明（var + set）。

# ---- 换名表：ravel 词名 → 宿主符号（一张表，便于审计与 see）----
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
    "len" "rb/len"
    "first" "rb/first"
    "last" "rb/last"
    "take" "rb/take"
    "drop" "rb/drop"
    "reverse" "rb/reverse"
    "at" "rb/at"
    "nth" "rb/at"
    "show" "rb/show"
    "print" "rb/show"
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

(defn rb/translate-token
  [t]
  (case (t :kind)
    :num (string "(rb/push " (rb/render (t :value)) ")")
    :str (string "(rb/push " (rb/render (t :value)) ")")
    :block (string "(rb/quot (fn [] " (rb/translate-stmts (t :tokens)) "))")
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
