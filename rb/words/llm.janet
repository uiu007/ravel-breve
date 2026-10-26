# rb/words/llm.janet —— provider 配置词（D-54；新增于 v1.0d 之后，见 SF-32）
#
#   llm             -- Table           当前工作区的配置（活表）
#   llm-get  Key    -- Value           取**生效值**（配置 > 环境变量 > 缺省）
#   llm-set  Value Key --              写一项；Value 为 nil = 删除（回落）
#   llm-models      -- Seq             拉一次当前 provider 的可用模型名（D-66）
#   llm-auto        -- String          拉模型列表 → 按偏好选一个 → 写回 `model`（D-66）
#   catalog         -- Table           当前的模型目录（副本；名字 → 窗口/额度）
#   catalog-refresh -- Int             拉一次模型列表，把没见过的名字登记进目录（REQ-72）
#   llm-import NameOrPath -- Table     一键导入预设（presets/<名字>.json 或路径，REQ-62）
#   llm-export Path       -- Int       把**生效**配置导出成预设文件（REQ-62）
#   usage           -- Table           本次会话累计的用量（P2：prompt / completion / total / calls）
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

(defn rb/llm-models
  " -- Seq；当前 provider 的模型名列表（每次调用都真的请求一次：列表会变）。"
  []
  (def f (rb/cap-get :llm/models))
  (when (nil? f)
    (rb/raise (rb/exit-table :orchestration-base)
              "能力层未提供 :llm/models（REQ-37：核心不含网络实现）"))
  (rb/push (f)))

(defn rb/llm-auto
  " -- String；按偏好自动选模型并写进工作区配置，压回选中的名字。
   偏好顺序：`RB_MODEL_PREFER`（逗号分隔）> provider 内置偏好 > 列表第一个。
   当前 `model` 已经在列表里时保留它（不做惊喜变更）。"
  []
  (def f (rb/cap-get :llm/auto))
  (when (nil? f)
    (rb/raise (rb/exit-table :orchestration-base)
              "能力层未提供 :llm/auto（REQ-37：核心不含网络实现）"))
  (rb/push (f)))

(defn rb/catalog
  " -- Table；模型目录的副本。可以用 `at` 读某个模型的窗口与额度（键名同模型名）。"
  []
  (def f (rb/cap-get :llm/catalog))
  (when (nil? f)
    (rb/raise (rb/exit-table :orchestration-base)
              "能力层未提供 :llm/catalog（REQ-37：核心不含网络实现）"))
  (rb/push (f)))

(defn rb/catalog-refresh
  " -- Int；拉一次当前 provider 的模型列表，把目录里没有的名字登记进去，压回**新增条数**。
   只登记名字，不登记额度（`GET /models` 不报窗口/额度）：额度仍走 pi 的兜底。
   缺省**不装**在任何事件上——要自动更新就 `@on @Start [ catalog-refresh ]`，
   `@off @Start` 即关（REQ-72：自动与否是钩子的启停，不是本仓的缺省偏好）。"
  []
  (def f (rb/cap-get :llm/catalog-refresh))
  (when (nil? f)
    (rb/raise (rb/exit-table :orchestration-base)
              "能力层未提供 :llm/catalog-refresh（REQ-37：核心不含网络实现）"))
  (rb/push (f)))

(defn rb/llm-import
  "NameOrPath -- Table；把预设写进工作区配置（只覆盖预设里出现的键），压回配置表。
   名字先找 `presets/<名字>.json`；带 `/` 或以 `.json` 结尾就当路径。受沙箱约束（REQ-53）。"
  []
  (def f (rb/cap-get :llm/import))
  (when (nil? f)
    (rb/raise (rb/exit-table :orchestration-base)
              "能力层未提供 :llm/import（REQ-37：核心不含文件/JSON 实现）"))
  (rb/push (f (rb/pop))))

(defn rb/llm-export
  "Path -- Int；把**生效**配置写成预设文件，压回写入项数。
   密钥永不落盘：`headers` 里带 Authorization / api-key 之类 → 60（D-54）。"
  []
  (def f (rb/cap-get :llm/export))
  (when (nil? f)
    (rb/raise (rb/exit-table :orchestration-base)
              "能力层未提供 :llm/export（REQ-37：核心不含文件/JSON 实现）"))
  (rb/push (f (rb/pop))))

(defn rb/usage
  " -- Table；工作区累计用量。字段与 provider 一致：prompt-tokens / completion-tokens /
   total-tokens / calls（工具调用与重试各算一次）。"
  []
  (rb/push (rb/usage-of)))
