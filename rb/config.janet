# rb/config.janet —— 工作区级 provider 配置（D-54）
#
# 为什么放在**工作区**里：provider / 模型 / 端点 / 上限 / 温度这些原来是
# 环境变量（`RB_LLM`、`RB_MODEL`……），只能在进程启动前定死。放进工作区后：
#   - **运行中可换**：`llm-set` 之后，下一次 `send` 就用新配置（无需重启）；
#   - **可预置**：脚本开头几行、或载入的工作区里就带着配置；
#   - **可编辑**：`llm` 给出活表，`at` 读、`llm-set` 写；
#   - **可持久化**：随快照保存（rb/store.janet），载入后仍然有效；
#   - **可审计**：`--dump`/`llm` 都看得见，不再是黑箱环境变量。
#
# 取值优先级（解析在能力层 cap/config.janet，核心只存不解析——核心不认识
# provider 名字，也不读环境变量）：**工作区配置 > 环境变量 > 内置缺省**。
#
# 密钥**不在这里**：`key` 不是合法配置项，只从环境变量或 secrets/nvidia.key 读，
# 免得密钥被写进快照/日志（REQ-20 会把工作区整份落盘）。

(def rb/config-keys
  "允许的配置项（字符串键）。列白名单是为了让拼错立刻报错，而不是静默无效。"
  @["provider" "model" "endpoint" "max-tokens" "temperature"])

(defn rb/config
  "当前工作区的 provider 配置表（**活表**：`at` 读、`llm-set` 写）。"
  []
  (def w (rb/ws))
  (def c (w :config))
  (if (table? c)
    c
    (let [t @{}] (put w :config t) t)))

(defn rb/config-normalize
  "配置项名 → 字符串；关键字也收（`:model` 与 `\"model\"` 等价）。"
  [k]
  (cond
    (string? k) k
    (keyword? k) (string k)
    (symbol? k) (string k)
    (rb/raise (rb/exit-table :runtime-type)
              (string "配置项名需要字符串，得到 " (type k)))))

(defn rb/config-check
  "白名单校验；`key` 明确拒绝（密钥不进工作区，D-54）。"
  [k]
  (cond
    (= k "key") (rb/raise (rb/exit-table :orchestration-base)
                          "密钥不是工作区配置项：请用环境变量 NVIDIA_API_KEY 或 secrets/nvidia.key（D-54）")
    (not (some (fn [x] (= x k)) rb/config-keys))
    (rb/raise (rb/exit-table :runtime-type)
              (string "未知的 LLM 配置项：" k "（可用：" (string/join rb/config-keys " ") "）"))
    nil))

(defn rb/config-set
  "写一项；值为 nil = 删除该项（回落到环境变量/内置缺省）。"
  [k v]
  (def key (rb/config-normalize k))
  (rb/config-check key)
  (def c (rb/config))
  (if (nil? v)
    (put c key nil)
    (put c key v))
  nil)

(var rb/llm-resolve nil)  # 能力层注册：配置项 → **生效值**（含环境变量与缺省）

(defn rb/config-get
  "取生效值：能能力层解析就用能力层（配置 > 环境变量 > 缺省），否则只读工作区。"
  [k]
  (def key (rb/config-normalize k))
  (if rb/llm-resolve
    (rb/llm-resolve key)
    (get (rb/config) key)))
