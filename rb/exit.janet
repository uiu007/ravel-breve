# rb/exit.janet —— 退出码分级（REQ-23）与方言层错误约定
#
# 分级：0 / 1 / 2 / 10–19 词法 / 20–29 语法 / 30–39 运行时 /
#       40–49 IO / 50–59 内部 / 60–69 编排预留 / 70+
#
# 方言层错误一律以「字典」抛出：@{:rb-code <整数> :rb-msg <字符串>}
# 宿主原生错误（未带 :rb-code）由 rb/error-code 归入运行时(30)。

(def rb/exit-table
  {:ok 0
   :failure 1
   :usage 2
   # 10–19 词法
   :lex-unterminated-string 10
   :lex-unterminated-block 11
   :lex-bad-escape 12
   # 20–29 语法
   :syntax-unknown-word 20
   :syntax-unexpected-token 21
   :syntax-bad-definition 22
   :syntax-compile 23
   # 30–39 运行时
   :runtime-stack-underflow 30
   :runtime-type 31
   :runtime-arity 32
   :runtime-fail 33
   # 40–49 IO
   :io-read 40
   :io-write 41
   # 50–59 内部
   :internal 50
   :internal-host 51
   # 60–69 编排预留 / 70+
   :orchestration-base 60
   :reserved-base 70})

(defn rb/raise
  "抛出一个带退出码的方言层错误。"
  [code msg]
  (error @{:rb-code code :rb-msg msg}))

(defn rb/rb-error?
  [e]
  (and (dictionary? e) (not (nil? (get e :rb-code)))))

(defn rb/error-code
  "把任意错误值映射为退出码。宿主原生错误归入运行时(30)。"
  [e]
  (if (rb/rb-error? e) (get e :rb-code) 30))

(defn rb/error-msg
  [e]
  (cond
    (rb/rb-error? e) (get e :rb-msg)
    (string? e) e
    (dictionary? e) (or (get e :error) (get e :rb-msg) (string/format "%q" e))
    (string/format "%q" e)))
