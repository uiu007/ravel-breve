# cap/llm.janet —— 能力层：provider 派发（§4.11 / REQ-37）
#
# 核心只认识能力键 `:llm/chat`：`(messages opts) → 取块函数`。
# 换 provider（nvidia ↔ mock）不改任何方言代码，只改 RB_LLM（REQ-37 验收）。

# ---- 模型列表与自动配置（D-66）-------------------------------------------
#
# 两家 provider 都是 OpenAI 形状：`GET <基址>/models` → `{"data":[{"id":…}]}`。
# 所以只要 provider 能给出「基址 + 头」，列表就能拉——头复用各自的构造器
# （自定义请求头 D-65 也在里面）。

(defn cap/llm-provider-headers
  "非对话请求（拉模型列表）用的头：按 provider 构造，含自定义头。"
  []
  (def provider (cap/llm-provider))
  (case provider
    "opencode" (do
                 (def key (cap/oc-key))
                 (when (nil? key)
                   (rb/raise (rb/exit-table :orchestration-base)
                             "未找到 OpenCode 密钥（设 OPENCODE_API_KEY，或写 secrets/opencode.key）"))
                 (cap/oc-headers key @{}))
    "nvidia" (do
               (def key (cap/nv-key))
               (when (nil? key)
                 (rb/raise (rb/exit-table :orchestration-base)
                           "未找到 NVIDIA 密钥（设 NVIDIA_API_KEY，或写 secrets/nvidia.key）"))
               (cap/nv-headers key))
    (cap/merge-headers @{})))

(defn cap/llm-models
  "拉一次可用模型列表 → `@[id …]`（字符串）。mock provider 返回 `@[\"mock\"]`。"
  []
  (def provider (cap/llm-provider))
  (if (= provider "mock")
    @["mock"]
    (do
      # 注意别把它叫 `get`：下面还要用核心的 `get` 读 JSON（会把自己遮掉）
      (def fetch (rb/cap-get :http/get-body))
      (when (nil? fetch)
        (rb/raise (rb/exit-table :orchestration-base)
                  "能力层未提供 :http/get-body（cap/http）"))
      (def dec (rb/cap-get :json/decode))
      (when (nil? dec)
        (rb/raise (rb/exit-table :orchestration-base)
                  "能力层未提供 JSON 解码（cap/json）"))
      (def url (string (cap/llm-base-url) "/models"))
      (def body (fetch url (cap/llm-provider-headers)))
      (def j (protect (dec body)))
      (when (not (get j 0))
        (rb/raise (rb/exit-table :orchestration-base)
                  (string "模型列表不是合法 JSON：" (rb/error-msg (get j 1)))))
      (def obj (get j 1))
      (def data (when (dictionary? obj) (get obj "data")))
      (when (not (indexed? data))
        (rb/raise (rb/exit-table :orchestration-base)
                  (string "模型列表形状不对：期望 data 数组，得到 "
                          (string/slice body 0 (min 200 (length body))))))
      (def out @[])
      (each m data
        (when (dictionary? m)
          (def id (get m "id"))
          (when id (array/push out (string id)))))
      out)))

(defn cap/llm-auto
  "拉模型列表 → 按偏好（RB_MODEL_PREFER > provider 内置）挑一个 → **写回工作区**
   `model` → 返回名字。工作区里**显式设过**的模型若仍在列表里就保留（不做惊喜变更）；
   内置缺省不算显式，照样按偏好走。"
  []
  (def models (cap/llm-models))
  (when (empty? models)
    (rb/raise (rb/exit-table :orchestration-base) "模型列表为空"))
  # 「保留」只保护**显式配置**过的模型：内置缺省不算用户意图，
  # 否则 `RB_MODEL_PREFER` 永远轮不到（缺省模型多半就在列表里）。
  (def cur (get (rb/config) "model"))
  (def chosen
    (cond
      (and (string? cur) (not= cur "auto") (find |(= cur $) models)) cur
      (do
        (var hit nil)
        (each p (cap/model-prefer)
          (when (and (nil? hit) (find |(= p $) models)) (set hit p)))
        (or hit (models 0)))))
  (rb/config-set "model" chosen)
  chosen)

(defn cap/llm-chat
  "能力 :llm/chat 的实现：按配置选 provider 并转调。"
  [messages opts]
  (def provider (cap/llm-provider))
  (def key (case provider
             "nvidia" :llm/nvidia
             "opencode" :llm/opencode
             :llm/mock))
  (def f (rb/cap-get key))
  (when (nil? f)
    (rb/raise (rb/exit-table :orchestration-base)
              (string "provider 未装载：" provider "（" key "）")))
  # D-54：模型 / 端点 / 上限 / 温度都由 cap/config 按优先级解析；
  # 显式 opts（能力层内部调用）优先，其次工作区配置、环境变量、缺省。
  (def opts2 (merge @{:provider provider
                      # `model` = "auto" → 先拉一次模型列表并按偏好定下来（D-66）
                      :model (if (= (cap/llm-model) "auto") (cap/llm-auto) (cap/llm-model))
                      :endpoint (cap/llm-endpoint)
                      :max-tokens (cap/llm-max-tokens)
                      :temperature (cap/llm-temperature)}
                    (or opts @{})))
  (f messages opts2))

(rb/cap-put :llm/models cap/llm-models)
(rb/cap-put :llm/auto cap/llm-auto)
(rb/cap-put :llm/chat cap/llm-chat)
