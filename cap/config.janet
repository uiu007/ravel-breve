# cap/config.janet —— 能力层：provider 配置（密钥 / 模型 / 选择）
#
# 取值优先级（D-54）：**工作区配置 > 环境变量 > 内置缺省**
#   工作区配置：方言里 `llm-set`（`llm` 看全表、`llm-get` 看生效值）
#   环境变量：  RB_LLM、RB_MODEL、RB_ENDPOINT、RB_MAX_TOKENS、RB_TEMPERATURE
#               RB_HEADERS、RB_MODEL_PREFER
#               （OpenCode 另有 RB_OC_BASE / RB_OC_SESSION / OPENCODE_API_KEY）
#   密钥**只**从这里来（不入库、不进工作区、不进快照）：
#     NVIDIA_API_KEY，或 secrets/nvidia.key / .nvidia.key / ~/.config/ravel/nvidia.key

(def cap/nv-default-model "meta/llama-3.2-11b-vision-instruct")
(def cap/nv-endpoint "https://integrate.api.nvidia.com/v1/chat/completions")
# D-64：OpenCode Go 的缺省模型 / 基址 / 端点（`llm-set` 可换）
(def cap/oc-model-default "deepseek-v4.1-flash")
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

# ---- 自定义请求头（D-65）------------------------------------------------
#
# 工作区配置 `headers`（`llm-set H{ "X-Foo" "bar" } "headers"`）或环境变量
# `RB_HEADERS`（JSON 对象，或 `X-Foo:bar,X-Baz:qux`）。两种来源都归一成
# `@{"Name" "value"}`，由 provider 的头构造**合并**（自定义可覆盖内置项）。

(def cap/headers-env-raw nil)  # 测试用的注入口（见 tests/unit/llm-models.janet）

(defn cap/headers-raw
  []
  (def v (get (rb/config) "headers"))
  (cond
    (not (nil? v)) v
    (not (nil? cap/headers-env-raw)) cap/headers-env-raw
    (os/getenv "RB_HEADERS") (os/getenv "RB_HEADERS")
    @{}))

(defn cap/headers-parse-env
  "`K:v,K2:v2` → 表；空串 → 空表。"
  [s]
  (def out @{})
  (each part (string/split "," s)
    (def t (string/trim part))
    (when (not (empty? t))
      (def i (string/find ":" t))
      (when i
        (def k (string/trim (string/slice t 0 i)))
        (def v (string/trim (string/slice t (inc i))))
        (when (not (empty? k)) (put out k v)))))
  out)

(defn cap/headers
  "生效的自定义请求头（String → String）。坏输入报 31（配置不是方言程序）。"
  []
  (def raw (cap/headers-raw))
  (def tbl
    (cond
      (dictionary? raw) raw
      (nil? raw) @{}
      (string? raw)
      (do
        (def t (string/trim raw))
        (cond
          (empty? t) @{}
          (string/has-prefix? "{" t)
          (do
            (def dec (rb/cap-get :json/decode))
            (when (nil? dec)
              (rb/raise (rb/exit-table :orchestration-base)
                        "能力层未提供 JSON 解码（cap/json）"))
            (def j (protect (dec t)))
            (if (get j 0)
              (if (dictionary? (get j 1))
                (get j 1)
                (rb/raise (rb/exit-table :runtime-type)
                          "RB_HEADERS 的 JSON 必须是对象"))
              (rb/raise (rb/exit-table :runtime-type)
                        (string "RB_HEADERS 不是合法 JSON：" (rb/error-msg (get j 1))))))
          (cap/headers-parse-env t)))
      (rb/raise (rb/exit-table :runtime-type)
                (string "headers 必须是表或字符串，得到 " (type raw)))))
  (def out @{})
  (eachp [k v] tbl
    (when (not (nil? v))
      (put out (string k) (string v))))
  out)

(defn cap/merge-headers
  "内置头 + 自定义头（自定义覆盖同名项）。"
  [base]
  (def out (table/clone base))
  (eachp [k v] (cap/headers) (put out k v))
  out)

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

(def cap/model-prefer-default
  @{"opencode" @["deepseek-v4.1-flash" "glm-5.3-flash" "kimi-k3" "qwen3.8-plus" "qwen3.8-flash"]
    "nvidia" @["meta/llama-3.2-11b-vision-instruct"]
    "mock" @["mock"]})

(defn cap/model-prefer
  "自动选模型的偏好顺序：`RB_MODEL_PREFER`（逗号分隔）> provider 内置偏好。"
  []
  (def env (os/getenv "RB_MODEL_PREFER"))
  (if (and env (not (empty? (string/trim env))))
    (do
      (def out @[])
      (each p (string/split "," env)
        (def t (string/trim p))
        (when (not (empty? t)) (array/push out t)))
      out)
    (or (get cap/model-prefer-default (cap/llm-provider)) @[])))

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

(defn cap/llm-base-url
  "生效端点的**基址**（去掉 `/chat/completions`）：模型列表要拼 `/models`。"
  []
  (def e (string (cap/llm-endpoint)))
  (def suffix "/chat/completions")
  (if (string/has-suffix? suffix e)
    (string/slice e 0 (- (length e) (length suffix)))
    e))

# ---- 输出预算（REQ-71 / D-77：全面对齐 pi 的口径）------------------------
#
# pi 的每请求预算是
#   `clampMaxTokensToContext(model, context, options?.maxTokens ?? model.maxTokens)`
# 也就是：`min(想要的额度, max(1, 上下文窗口 - 估算输入 tokens - 4096))`。
# 它家的模型目录里 `deepseek-v4.1-flash` 是 1e6 上下文 / 384000 输出，
# 所以实际发出去的是 384000——而 v1.0q 我们发 8192。
# 推理型模型的 `reasoning_content` 算在 completion tokens 里，额度太小 =
# 正文永远没机会出现（D-76 的 60 就是这么来的）。

(def cap/min-max-tokens 1)              # pi: MIN_MAX_TOKENS
(def cap/context-safety-tokens 4096)    # pi: CONTEXT_SAFETY_TOKENS
(def cap/llm-max-tokens-default 32768)  # 模型不在目录里时的保守大值（D-77）

(def cap/model-catalog
  "只收 pi 的模型目录里能核对到数字的模型（`:context-window` / `:max-tokens`）。
   目录外的模型不猜上限，走 `cap/llm-max-tokens-default`。"
  @{"deepseek-v4.1-flash" @{:context-window 1000000 :max-tokens 384000}
    "deepseek-v4.1-flash-free" @{:context-window 200000 :max-tokens 32000}
    "deepseek-v3.2" @{:context-window 128000 :max-tokens 65536}})

(defn cap/model-budget
  "模型 → `@{:context-window n :max-tokens n}`；不认识就是两个 0（= 未知）。"
  [model]
  (or (get cap/model-catalog (string model))
      @{:context-window 0 :max-tokens 0}))

(defn cap/llm-max-tokens-explicit
  "显式配置的额度（工作区配置 > `RB_MAX_TOKENS`）；没设 → nil。"
  []
  (def v (cap/cfg "max-tokens" "RB_MAX_TOKENS" nil))
  (when (not (nil? v))
    (cap/cfg-num "max-tokens" "RB_MAX_TOKENS" cap/llm-max-tokens-default)))

(defn cap/llm-max-tokens
  "生效的输出预算（**未**按上下文裁剪）：显式 > 模型上限 > 缺省。"
  []
  (def e (cap/llm-max-tokens-explicit))
  (if (not (nil? e))
    e
    (do
      (def mb ((cap/model-budget (cap/llm-model)) :max-tokens))
      (if (> mb 0) mb cap/llm-max-tokens-default))))

(defn cap/json-len
  "JSON 编码后的字节数；编不出来就当 0。"
  [enc x]
  (def p (protect (enc x)))
  (if (and (get p 0) (string? (get p 1))) (length (get p 1)) 0))

(defn cap/est-tokens
  "粗估这次请求的**输入** tokens：JSON 字节数 / 4（与 pi 的估算同量级）。"
  [messages tools]
  (def enc (rb/cap-get :json/encode))
  (if (nil? enc)
    0
    (math/ceil (/ (+ (cap/json-len enc messages)
                     (if tools (cap/json-len enc tools) 0))
                  4))))

(defn cap/clamp-max-tokens
  "pi 的 `clampMaxTokensToContext`：窗口未知（<= 0）就原样；否则留出输入与安全余量。"
  [want window est]
  (if (<= window 0)
    (max cap/min-max-tokens want)
    (min want (max cap/min-max-tokens (- window est cap/context-safety-tokens)))))

(defn cap/llm-budget
  "一次请求的输出预算：`@{:max-tokens n :context-window w :est e :source k}`。
   `source` = `:opts` / `:explicit` / `:model` / `:fallback`（预算从哪来）。"
  [messages opts]
  (def model (string (or (opts :model) (cap/llm-model))))
  (def b (cap/model-budget model))
  (def explicit (or (opts :max-tokens) (cap/llm-max-tokens-explicit)))
  (def mw (b :max-tokens))
  (def want (or explicit (if (> mw 0) mw cap/llm-max-tokens-default)))
  (def est (cap/est-tokens messages (opts :tools)))
  @{:max-tokens (cap/clamp-max-tokens want (b :context-window) est)
    :context-window (b :context-window)
    :est est
    :source (cond
              (opts :max-tokens) :opts
              explicit :explicit
              (> mw 0) :model
              :fallback)})

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
         "headers" (cap/headers)
         (get (rb/config) k))))

