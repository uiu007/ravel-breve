# cap/llm.janet —— 能力层：provider 派发（§4.11 / REQ-37）
#
# 核心只认识能力键 `:llm/chat`：`(messages opts) → 取块函数`。
# 换 provider（nvidia ↔ mock）不改任何方言代码，只改 RB_LLM（REQ-37 验收）。

(defn cap/llm-chat
  "能力 :llm/chat 的实现：按配置选 provider 并转调。"
  [messages opts]
  (def provider (cap/llm-provider))
  (def key (if (= provider "nvidia") :llm/nvidia :llm/mock))
  (def f (rb/cap-get key))
  (when (nil? f)
    (rb/raise (rb/exit-table :orchestration-base)
              (string "provider 未装载：" provider "（" key "）")))
  (def opts2 (merge @{:provider provider :model (cap/llm-model)} (or opts @{})))
  (put opts2 :model (or (opts2 :model) (cap/llm-model)))
  (f messages opts2))

(rb/cap-put :llm/chat cap/llm-chat)
