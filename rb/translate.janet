# rb/translate.janet —— 转译：递归反转 + 换名 + 定义行（REQ-01/02/03/05/31/33/34）
#
# 镜像原理：语句内 token 递归反转后逐个映射为宿主序：
#   take 2 "abcde"  →  (do (rb/push "abcde") (rb/push 2) (rb/take))
# 引号块 `[ ... ]` 压栈即数据（不求值，REQ-32），内部**逐语句递归反转**。
# 定义行 `名字 : [ 体 ]` 是**元层**：不参与镜像，顺序固定（REQ-34），
# 在装载期（= 转译期）注册进字典（REQ-33），运行期无栈效果。
#
# 转译期要用**目标工作区的字典**解析用户词（REQ-30：字典属于工作区），
# 因此 `rb/compile-source` 显式把 dict 传下来，转译函数逐层带参。
#
# 注意：块 ↔ 语句序列互为递归，translate-stmts 需要前向声明（var + set）；
# token → ravel 源文本同理（`rb/tokens->src` ↔ `rb/token->src`）。

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
    "doc" "rb/doc"
    # L3 消息流（M3）
    "append" "rb/append"
    "session" "rb/session"
    "send" "rb/send"
    "resend" "rb/resend"
    "bcast" "rb/bcast"
    # L4 名字与 agent（M3）
    "agent" "rb/agent"
    "origin" "rb/origin"
    "unsubscribe" "rb/unsubscribe"
    # L9 前端订阅（M5）
    "watch" "rb/watch"
    "subscribe" "rb/subscribe"
    "->" "rb/->"
    "onfail" "rb/onfail"
    "deftool" "rb/deftool"
    "invoke" "rb/invoke"
    "saysys" "rb/saysys"
    # L8 钩子与流（M3）
    "@on" "rb/hook-on"
    "@off" "rb/hook-off"
    "next" "rb/next"
    "drain" "rb/drain"
    "utter" "rb/utter"
    "stop" "rb/stop"
    # L7 持久化（M4）
    "read" "rb/read"
    "write" "rb/write"
    "save" "rb/save"
    "load" "rb/load"
    "current" "rb/current-ws"
    "compact" "rb/compact"})

(def rb/literals @{"true" "true" "false" "false" "nil" "nil"})

# 前向声明：块内递归需要 translate-stmts；token ↔ 源文本互为递归
(var rb/translate-stmts nil)
(var rb/tokens->src nil)

(defn rb/lit-src
  "把一个字面量值还原为 **ravel 源文本**（D-34：`see` 与快照存源，不存宿主码）。"
  [v]
  (cond
    (tuple? v) (string "{ " (string/join (map rb/lit-src v) " ") " }")
    (table? v)
    (string "H{ "
            (string/join (map (fn [k] (string (rb/lit-src k) " " (rb/lit-src (get v k))))
                              (sort (keys v)))
                         " ")
            " }")
    (string/format "%q" v)))

(defn rb/token->src
  "token → ravel 源文本。"
  [t]
  (case (t :kind)
    :num (string/format "%q" (t :value))
    :str (rb/render-string (t :value))
    :word (t :value)
    :block (string "[ " (rb/tokens->src (t :tokens)) " ]")
    :seq-lit (rb/lit-src (t :value))
    :map-lit (rb/lit-src (t :value))
    (string (t :value))))

(set rb/tokens->src
     (fn [stmts]
       (string/join (map (fn [st] (string/join (map rb/token->src st) " ")) stmts)
                    "\n")))

(defn rb/word-form
  "把一个方言词名转译为宿主调用形式（dict = 目标工作区的字典）。"
  [name &opt dict]
  (def host (get rb/rename name))
  (def lit (get rb/literals name))
  (cond
    (not (nil? host)) (string "(" host ")")
    (rb/dict? name dict) (string "(rb/call-word " (rb/render name) ")")
    (not (nil? lit)) (string "(rb/push " lit ")")
    # 事件名（REQ-16 / REQ-17）：`@Start` … `@RoundDone` 是**字面记号**，压栈即值
    (rb/event? name) (string "(rb/push " (rb/render name) ")")
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
  [t &opt dict]
  (case (t :kind)
    :num (string "(rb/push " (rb/render (t :value)) ")")
    :str (string "(rb/push " (rb/render (t :value)) ")")
    :block (string "(rb/quot (fn [] " (rb/translate-stmts (t :tokens) dict) "))")
    :seq-lit (string "(rb/push " (rb/lit-code (t :value)) ")")
    :map-lit (string "(rb/push " (rb/lit-code (t :value)) ")")
    :word (rb/word-form (t :value) dict)
    (rb/raise (rb/exit-table :syntax-unexpected-token)
              (string "无法转译的记号：" (t :kind)))))

(defn rb/translate-forms
  "一条语句：token 书写序 → 求值序的形式文本数组。"
  [toks &opt dict]
  (def out @[])
  (each t (reverse toks)
    (array/push out (rb/translate-token t dict)))
  out)

(defn rb/definition?
  "定义行 = `名字 : [ 体 ]`（恰好三个 token）。"
  [toks]
  (and (= (length toks) 3)
       (= ((toks 0) :kind) :word)
       (= ((toks 1) :kind) :word)
       (= ((toks 1) :value) ":")
       (= ((toks 2) :kind) :block)))

(defn rb/def-doc?
  "带文档串的定义行 = `名字 : \"说明\" [ 体 ]`（D-52）。"
  [toks]
  (and (= (length toks) 4)
       (= ((toks 0) :kind) :word)
       (= ((toks 1) :kind) :word)
       (= ((toks 1) :value) ":")
       (= ((toks 2) :kind) :str)
       (= ((toks 3) :kind) :block)))

(defn rb/translate-def
  "元层特例：`名字 : [ 体 ]`（REQ-33/34）。
   同时产出两份文本：宿主序（执行用，D-35）与 ravel 源（see/快照用，D-34）。"
  [toks &opt dict]
  (def name ((toks 0) :value))
  (def doc (if (rb/def-doc? toks) ((toks 2) :value) nil))
  (def body ((if (rb/def-doc? toks) (toks 3) (toks 2)) :tokens))
  (def body-src (rb/tokens->src body))
  # 先占位再转译体：体内的**自引用**（递归）在转译期就能解析到（D-51）
  (rb/dict-declare name body-src dict)
  (def body-code (string "(fn [] " (rb/translate-stmts body dict) ")"))
  (string "(rb/define-word " (rb/render name) " " body-code " " (rb/render doc) " "
          (rb/render body-src) " " (rb/render body-code) ")"))

(def rb/stack-variants
  "语句只由「词 + 若干引号」组成时，条件/次数**已在栈上**（D-51）：
   词 → [宿主变体, 需要的引号数]"
  @{"if" @["rb/if-stack" 2]
    "when" @["rb/when-stack" 1]
    "unless" @["rb/unless-stack" 1]
    "loop" @["rb/loop-stack" 1]})

(defn rb/stack-form?
  "该语句是不是「词 + 恰好 n 个引号」的栈上形式？"
  [toks v]
  (and (= (length toks) (inc (v 1)))
       (all (fn [t] (= (t :kind) :block)) (slice toks 1))))

(defn rb/stmt-forms
  "一条语句 → 形式文本数组（定义行是元层，不参与镜像）。"
  [toks &opt dict]
  (cond
    (or (rb/definition? toks) (rb/def-doc? toks)) @[(rb/translate-def toks dict)]
    (let [v (get rb/stack-variants ((toks 0) :value))]
      (and v (rb/stack-form? toks v)))
    (do
      (def host ((get rb/stack-variants ((toks 0) :value)) 0))
      (def out @[])
      (each t (reverse (slice toks 1))
        (array/push out (rb/translate-token t dict)))
      (array/push out (string "(" host ")"))
      out)
    (rb/translate-forms toks dict)))

(set rb/translate-stmts
     (fn [stmts &opt dict]
       # 语句序列 → 扁平的 (do form ...)；语句之间保持书写序。
       (def out @[])
       (each s stmts
         (each f (rb/stmt-forms s dict)
           (array/push out f)))
       (string "(do " (string/join out " ") ")")))
