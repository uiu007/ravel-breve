# cap/llm.janet —— 能力层：provider 派发（§4.11 / REQ-37）
#
# 核心只认识能力键 `:llm/chat`：`(messages opts) → 取块函数`。
# 换 provider（nvidia ↔ mock）不改任何方言代码，只改 RB_LLM（REQ-37 验收）。

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
                      :model (cap/llm-model)
                      :endpoint (cap/llm-endpoint)
                      :max-tokens (cap/llm-max-tokens)
                      :temperature (cap/llm-temperature)}
                    (or opts @{})))
  (f messages opts2))

(rb/cap-put :llm/chat cap/llm-chat)
