# rb/words/l2.janet —— L2 消息与 JSON（附录 A）
#
# REQ-06：`Utter` = @{:role String :content String}；`Session` = list Utter（array）。
# REQ-10：Session 不另设类型，直接复用 L1 多态序列词。
#
# JSON 的**实现**不在核心（附录 D）：`to-json` / `from-json` 只通过能力层
# 注册表（§4.11）取用；剔除 cap/ 后核心仍可装载，调用时给出明确的运行时错误。

(defn rb/utter?
  "是不是一条消息（REQ-06：Utter = role + content）。"
  [x]
  (and (dictionary? x) (not (nil? (get x :role))) (not (nil? (get x :content)))))

(defn rb/utter-ensure
  [x]
  (when (not (rb/utter? x))
    (rb/raise (rb/exit-table :runtime-type)
              (string "需要一条 Utter（H{ \"role\" \"…\" \"content\" \"…\" }），得到 " (type x))))
  x)

(defn rb/Utter
  "Role String -- Utter（低层构造；名词大写，附录 A）"
  []
  (def role (rb/pop))
  (def content (rb/pop))
  (rb/push @{:role role :content content}))

(defn rb/say
  "String -- Utter；缺省 Role = \"user\"（REQ-29：用户输入）"
  []
  (rb/push @{:role "user" :content (rb/pop)}))

(defn rb/Role
  "Utter -- String"
  []
  (rb/push (get (rb/pop) :role)))

(defn rb/Content
  "Utter -- String"
  []
  (rb/push (get (rb/pop) :content)))

(defn rb/cap-call
  "按注册表键取能力函数并调用；缺失为明确的运行时错误。"
  [key x]
  (def f (rb/cap-get key))
  (when (nil? f)
    (rb/raise (rb/exit-table :runtime-type)
              (string "能力层未提供 " key "（核心不含 JSON 实现，附录 D）")))
  (f x))

(defn rb/to-json
  "x -- String"
  []
  (rb/push (rb/cap-call :json/encode (rb/pop))))

(defn rb/from-json
  "String -- Json"
  []
  (rb/push (rb/cap-call :json/decode (rb/pop))))
