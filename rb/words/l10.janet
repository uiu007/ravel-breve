# rb/words/l10.janet —— L10 处理流程（模式）与历史标记开关（D-59）
#
# 这一层把「一轮请求怎么被处理」显式化：模式（数据） ⇄ 钩子（工作区现状）。
# 词性（REQ-09）：`mode` / `flag-set` 是动词；`modes` / `mode-of` / `flag` 是名词。

(defn rb/mode
  "Name|Mode -- ；切换处理流程。
   给字符串 = 取预制模式（`default` / `ptc`）；给模式表 = 用它（可用 `mode-of` 造）。
   未知名字 → 20（未知的词），未知模式值 → 31。"
  []
  (def x (rb/pop))
  (def m (if (string? x)
           (do
             (def p (rb/mode-get x))
             (when (nil? p)
               (rb/raise (rb/exit-table :syntax-unknown-word)
                         (string "未知的模式：" x "（可用："
                                 (string/join (sort (keys (rb/mode-presets))) " ") "）")))
             p)
           x))
  (rb/mode-apply! m)
  nil)

(defn rb/modes
  "-- list ; 预制模式名（升序）。"
  []
  (rb/push (tuple ;(sort (keys (rb/mode-presets))))))

(defn rb/mode-of
  "-- Mode ；把当前工作区的钩子与开关导出成模式表（可与 `mode` 互逆）。"
  []
  (rb/push (rb/mode-capture)))

(defn rb/flag
  "Key -- Bool ；读一个历史标记开关（`history-turn` / `history-origin` / `history-mode`）。"
  []
  (def k (rb/pop))
  (rb/push (rb/flag-get k)))

(defn rb/flag-set
  "Value Key -- ；写一个历史标记开关（值必须是布尔；nil = 删除该项）。"
  []
  (def v (rb/pop))
  (def k (rb/pop))
  (rb/flag-set! k v)
  nil)

# ---- 模式的自省（名词，只读；全是 0 元）--------------------------------

(defn rb/mode-name
  "Mode -- String ；模式名。"
  []
  (rb/push ((rb/pop) :name)))

(defn rb/mode-prompt
  "Mode -- String|nil ；模式的系统提示（只进请求，不进会话）。"
  []
  (rb/push ((rb/pop) :prompt)))

(defn rb/mode-tools
  "Mode -- list String ；模式声明的工具名（升序）。"
  []
  (def m (rb/pop))
  (rb/push (tuple ;(sort (keys (or (m :tools) @{}))))))
