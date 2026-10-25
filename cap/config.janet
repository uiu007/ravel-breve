# cap/config.janet —— 能力层：provider 配置（密钥 / 模型 / 选择）
#
# 取值优先级（D-54）：**工作区配置 > 环境变量 > 内置缺省**
#   工作区配置：方言里 `llm-set`（`llm` 看全表、`llm-get` 看生效值）
#   环境变量：  RB_LLM、RB_MODEL、RB_ENDPOINT、RB_MAX_TOKENS、RB_TEMPERATURE
#               （OpenCode 另有 RB_OC_BASE / RB_OC_SESSION / OPENCODE_API_KEY）
#   密钥**只**从这里来（不入库、不进工作区、不进快照）：
#     NVIDIA_API_KEY，或 secrets/nvidia.key / .nvidia.key / ~/.config/ravel/nvidia.key

(def cap/nv-default-model "meta/llama-3.2-11b-vision-instruct")
(def cap/nv-endpoint "https://integrate.api.nvidia.com/v1/chat/completions")
# D-64：OpenCode Go 的缺省模型 / 基址 / 端点（`llm-set` 可换）
(def cap/oc-model-default "glm-5.3-flash")
(def cap/oc-base-default "https://opencode.ai/zen/go/v1")

(defn cap/read-first-line
  "读一个文件的第一个非空行（密钥文件可能有尾换行）；读不到返回 nil。"
  [path]
  (def p (protect (slurp path)))
  (if (get p 0)
    (let [s (string/trim (string (get p 1)))]
      (if (empty? s) nil s))
    nil))

(defn cap/nv-key-paths
  []
  (def home (or (os/getenv "HOME") ""))
  @["secrets/nvidia.key"
    ".nvidia.key"
    (string home "/.config/ravel/nvidia.key")])

(defn cap/nv-key
  "环境变量优先，其次本地密钥文件（只在项目内 secrets/ 里，不入库）。"
  []
  (or (os/getenv "NVIDIA_API_KEY")
      (do
        (var found nil)
        (each p (cap/nv-key-paths)
          (when (nil? found)
            (def k (cap/read-first-line p))
            (when k (set found k))))
        found)))

(defn cap/oc-key-paths
  []
  (def home (or (os/getenv "HOME") ""))
  @["secrets/opencode.key"
    ".opencode.key"
    (string home "/.config/ravel/opencode.key")])

(defn cap/oc-key
  []
  (or (os/getenv "OPENCODE_API_KEY")
      (do
        (var found nil)
        (each p (cap/oc-key-paths)
          (when (nil? found)
            (def k (cap/read-first-line p))
            (when k (set found k))))
        found)))

(defn cap/oc-url
  "OpenCode 的端点：`RB_OC_BASE` 换基址；也接受已是完整 `/chat/completions` 的串。"
  []
  (def base (string (or (os/getenv "RB_OC_BASE") cap/oc-base-default)))
  (if (string/has-suffix? "/chat/completions" base)
    base
    (string (if (string/has-suffix? "/" base) base (string base "/"))
            "chat/completions")))

# ---- 工作区配置 > 环境变量 > 缺省（D-54）--------------------------------

(defn cap/cfg
  "取一项配置的原始值：工作区配置（llm-set）> 环境变量 > 缺省。"
  [k envname default]
  (def v (get (rb/config) k))
  (if (not (nil? v))
    v
    (do
      (def e (os/getenv envname))
      (if (nil? e) default e))))

(defn cap/cfg-num
  "同 cap/cfg，但要求数值（环境变量是字符串，故允许 scan-number）。"
  [k envname default]
  (def v (cap/cfg k envname default))
  (cond
    (number? v) v
    (string? v) (or (scan-number (string/trim v)) default)
    default))

(defn cap/llm-provider
  "provider：nvidia / opencode / mock / auto（缺省）。工作区配置优先，其次 RB_LLM。
   `auto` 时按密钥可用性选：nvidia > opencode > mock（D-64）。"
  []
  (def want (string (cap/cfg "provider" "RB_LLM" "auto")))
  (cond
    (= want "mock") "mock"
    (= want "nvidia") "nvidia"
    (= want "opencode") "opencode"
    (= want "auto") (cond
                      (cap/nv-key) "nvidia"
                      (cap/oc-key) "opencode"
                      "mock")
    (rb/raise (rb/exit-table :runtime-type)
              (string "provider 只能是 nvidia / opencode / mock / auto，得到 " want))))

(defn cap/llm-model
  "生效模型：显式配置 > 环境变量 > 按 provider 的缺省（D-64）。"
  []
  (def fallback (if (= (cap/llm-provider) "opencode")
                  cap/oc-model-default
                  cap/nv-default-model))
  (string (cap/cfg "model" "RB_MODEL" fallback)))

(defn cap/llm-endpoint
  "生效端点：显式配置 > 环境变量 > 按 provider 的缺省（D-64）。"
  []
  (def fallback (if (= (cap/llm-provider) "opencode")
                  (cap/oc-url)
                  cap/nv-endpoint))
  (string (cap/cfg "endpoint" "RB_ENDPOINT" fallback)))

(defn cap/llm-max-tokens
  []
  (cap/cfg-num "max-tokens" "RB_MAX_TOKENS" 512))

(defn cap/llm-temperature
  []
  (cap/cfg-num "temperature" "RB_TEMPERATURE" 0.2))

# `llm-get` 的生效值：核心只存不解析，解析在这里注册（D-29 的间接层）
(set rb/llm-resolve
     (fn [k]
       (case k
         "provider" (cap/llm-provider)
         "model" (cap/llm-model)
         "endpoint" (cap/llm-endpoint)
         "max-tokens" (cap/llm-max-tokens)
         "temperature" (cap/llm-temperature)
         (get (rb/config) k))))

