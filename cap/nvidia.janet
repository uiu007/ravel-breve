# cap/nvidia.janet —— 能力层：NVIDIA NIM（OpenAI 兼容 /chat/completions）
#
# 注册键 `:llm/nvidia`：`(messages opts) → 取块函数`。
# 流式：请求 `stream: true`；SSE 解析与用量/工具累积在 `cap/oai.janet`（D-64），
# 本文件只管三样：密钥、请求体、请求头。

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

(defn cap/nv-body
  [messages opts]
  (def enc (rb/cap-get :json/encode))
  (when (nil? enc)
    (rb/raise (rb/exit-table :orchestration-base) "能力层未提供 :json/encode"))
  (enc @{:model (opts :model)
         :messages messages
         :stream true
         # D-54：温度与上限也走「工作区配置 > 环境变量 > 缺省」
         :temperature (or (opts :temperature) (cap/llm-temperature))
         :max_tokens (or (opts :max-tokens) (cap/llm-max-tokens))
         :top_p 1
         # REQ-48：工具表非空才带 `tools`（空表 = 纯文本对话）
         :tools (when (and (opts :tools) (> (length (opts :tools)) 0)) (opts :tools))}))

(defn cap/nv-headers
  [key]
  @{"Authorization" (string "Bearer " key)
    "Content-Type" "application/json"
    "Accept" "text/event-stream"})

(defn cap/nv-chat
  "messages opts → 取块函数"
  [messages opts]
  (def key (cap/nv-key))
  (when (nil? key)
    (rb/raise (rb/exit-table :orchestration-base)
              "未找到 NVIDIA 密钥（设 NVIDIA_API_KEY，或写 secrets/nvidia.key）"))
  (def enc (rb/cap-get :json/encode))
  (def dec (rb/cap-get :json/decode))
  (when (or (nil? enc) (nil? dec))
    (rb/raise (rb/exit-table :orchestration-base) "能力层未提供 JSON 编解码（cap/json）"))
  (def post (rb/cap-get :http/post-lines))
  (when (nil? post)
    (rb/raise (rb/exit-table :orchestration-base) "能力层未提供 :http/post-lines（cap/http）"))
  (def body (cap/nv-body messages opts))
  (when (os/getenv "RB_DEBUG_BODY") (eprintf "BODY| %s" body))
  (def lines (post (or (opts :endpoint) (cap/llm-endpoint))
                   (cap/nv-headers key)
                   body))
  (cap/oai-pull lines dec "NVIDIA"))

(rb/cap-put :llm/nvidia cap/nv-chat)
