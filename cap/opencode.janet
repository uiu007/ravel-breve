# cap/opencode.janet —— 能力层：OpenCode Zen / Go（OpenAI 兼容 /chat/completions）
#
# 注册键 `:llm/opencode`：`(messages opts) → 取块函数`。
# 与 NVIDIA 的区别只有三处（其余解析复用 `cap/oai.janet`，D-64）：
#   ① 端点：`https://opencode.ai/zen/go/v1/chat/completions`（`RB_OC_BASE` 可换）
#   ② 密钥：`OPENCODE_API_KEY` 或 `secrets/opencode.key`
#   ③ 头：`User-Agent` 必须自称客户端（不许是通用 SDK 名），且必须带
#      `x-opencode-session`（一次会话一个稳定值，供其路由与提示缓存）。
#      缺 `x-opencode-session` 会被拒：`{"type":"error","error":{"type":"MissingSessionID"}}`。

# 密钥（`cap/oc-key`）、基址（`cap/oc-url`）、缺省模型在 cap/config.janet（D-54 的优先级）

(defn cap/oc-session
  "一次会话一个稳定 id（`opts :session`，缺省 `RB_OC_SESSION`，再缺省固定串）。"
  [opts]
  (def s (or (opts :session) (os/getenv "RB_OC_SESSION") "ravel-breve"))
  (string "rb-" s))

(defn cap/oc-headers
  "内置头 + 自定义头（D-65：自定义可覆盖同名项，例如换 User-Agent）。"
  [key opts]
  (cap/merge-headers @{"Authorization" (string "Bearer " key)
                       "Content-Type" "application/json"
                       "Accept" "text/event-stream"
                       # HTTP 头是单行 token：不能带空格/非 ASCII（所以不用 version-string）
                       "User-Agent" (string "ravel-breve/" rb/version)
                       "x-opencode-session" (cap/oc-session opts)}))

(defn cap/oc-body
  [messages opts]
  (def enc (rb/cap-get :json/encode))
  (when (nil? enc)
    (rb/raise (rb/exit-table :orchestration-base) "能力层未提供 :json/encode"))
  (enc @{:model (opts :model)
         :messages messages
         :stream true
         :temperature (or (opts :temperature) (cap/llm-temperature))
         :max_tokens (or (opts :max-tokens) (cap/llm-max-tokens))
         :tools (when (and (opts :tools) (> (length (opts :tools)) 0)) (opts :tools))
         # Go 的用量里带账单字段；不主动关掉，方便上层看 `opencode.allowance`
         :stream_options @{:include_usage true}}))

(defn cap/oc-chat
  "messages opts → 取块函数"
  [messages opts]
  (def key (cap/oc-key))
  (when (nil? key)
    (rb/raise (rb/exit-table :orchestration-base)
              "未找到 OpenCode 密钥（设 OPENCODE_API_KEY，或写 secrets/opencode.key）"))
  (def dec (rb/cap-get :json/decode))
  (when (nil? dec)
    (rb/raise (rb/exit-table :orchestration-base) "能力层未提供 JSON 解码（cap/json）"))
  (def post (rb/cap-get :http/post-lines))
  (when (nil? post)
    (rb/raise (rb/exit-table :orchestration-base) "能力层未提供 :http/post-lines（cap/http）"))
  (def body (cap/oc-body messages opts))
  (when (os/getenv "RB_DEBUG_BODY") (eprintf "BODY| %s" body))
  (def lines (post (or (opts :endpoint) (cap/oc-url))
                   (cap/oc-headers key opts)
                   body))
  (cap/oai-pull lines dec "OpenCode"))

(rb/cap-put :llm/opencode cap/oc-chat)
