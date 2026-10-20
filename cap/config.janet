# cap/config.janet —— 能力层：provider 配置（密钥 / 模型 / 选择）
#
# 密钥**不入库**（.gitignore 已排除 secrets/）。
#   环境变量优先：NVIDIA_API_KEY、RB_MODEL、RB_LLM、RB_ENDPOINT
#   文件次之：secrets/nvidia.key / .nvidia.key / ~/.config/ravel/nvidia.key

(def cap/nv-default-model "meta/llama-3.2-11b-vision-instruct")
(def cap/nv-endpoint "https://integrate.api.nvidia.com/v1/chat/completions")

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

(defn cap/llm-model
  []
  (or (os/getenv "RB_MODEL") cap/nv-default-model))

(defn cap/llm-provider
  "RB_LLM：nvidia / mock / auto（缺省）。"
  []
  (def want (string (or (os/getenv "RB_LLM") "auto")))
  (cond
    (= want "mock") "mock"
    (= want "nvidia") "nvidia"
    (cap/nv-key) "nvidia"
    "mock"))

