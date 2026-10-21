# rb/words/llm.janet —— provider 配置词（D-54；新增于 v1.0d 之后，见 SF-32）
#
#   llm             -- Table           当前工作区的配置（活表）
#   llm-get  Key    -- Value           取**生效值**（配置 > 环境变量 > 缺省）
#   llm-set  Value Key --              写一项；Value 为 nil = 删除（回落）
#
# 书写序：`llm-set "nvidia" "provider"` → 镜像后压 `"provider"`、再压 `"nvidia"`，
# 于是栈顶是**值**、次顶是**键**——与「最左 = 第一个操作数 = 栈顶」一致。

(defn rb/llm
  " -- Table；当前工作区的 provider 配置（`at` 可读，`llm-set` 可写）。"
  []
  (rb/push (rb/config)))

(defn rb/llm-set
  "Value Key -- ；写一项。Key 用字符串（`:model` 也收）；Value 为 nil = 删除。"
  []
  (def v (rb/pop))
  (def k (rb/pop))
  (rb/config-set k v)
  nil)

(defn rb/llm-get
  "Key -- Value；取生效值（工作区配置 > 环境变量 > 内置缺省）。"
  []
  (rb/push (rb/config-get (rb/pop))))
