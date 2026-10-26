# tests/conformance/req-71-budget.janet —— REQ-71 输出预算（v1.0r / D-77）
#
# 守的两条性质（都是 pi agent 的口径）：
#
#   ① **每请求的额度不是写死的**：`clampMaxTokensToContext(model, context, 想要的额度)`
#      = `min(想要的额度, max(1, 上下文窗口 - 估算输入 - 4096))`，
#      「想要的额度」= 显式配置 > 模型的 `maxTokens`（目录）> 缺省。
#      pi 对 `deepseek-v4.1-flash` 发 384000；v1.0q 的 8192 是正文被推理吃光的直接原因。
#
#   ② **截断按 pi 的 `isRecoverableLength` 判**：
#      `length` 且 `out < max` → 可恢复（同轮续写）；
#      `out >= max` → 额度真的用完了 → 立刻 60，不再空转三轮烧钱。
#      收尾块因此多两个字段：`:out`（usage.completion_tokens）与 `:max`（请求里的 max_tokens）。

(defn- r71-env-set!
  "设一个环境变量（nil = 删除）；返回旧值。"
  [k v]
  (def old (os/getenv k))
  (os/setenv k v)
  old)

(defn- r71-with-env
  "临时设一批环境变量（`[k v]` 的数组，值 nil = 删除），跑 body，最后按**旧值**还原。"
  [pairs body]
  (def old @[])
  (each pair pairs
    (array/push old (r71-env-set! (pair 0) (pair 1))))
  (def r (protect (body)))
  (var i 0)
  (each pair pairs
    (os/setenv (pair 0) (old i))
    (++ i))
  (if (get r 0) (get r 1) (error (get r 1))))

(defn- r71-line-src
  "把一串 SSE 行做成行源（取尽返回 nil）。"
  [xs]
  (var i 0)
  (fn []
    (when (< i (length xs))
      (def s (xs i))
      (++ i)
      s)))

(defn- r71-pull-all
  "把取块函数拉干净，返回块数组。"
  [pull]
  (def out @[])
  (var go true)
  (while go
    (def v (pull))
    (if (nil? v) (set go false) (array/push out v)))
  out)

(defn- r71-mock-turn
  "设好环境变量跑一轮（一个 user 消息 + send/drain），返回 `[agent 结果]`。"
  [vars]
  (def old @{})
  (eachp [k v] vars
    (put old k (os/getenv k))
    (os/setenv k v))
  (def env (new-ws))
  (def r (run-in env "agent \"c\" { }\nsend say \"hi\"\ndrain"))
  # 还原：`(os/setenv k nil)` 才是真删除；必须遍历**旧键**，不能遍历 vars（会写成刚设的值）
  (eachp [k _] vars
    (os/setenv k (get old k)))
  @[(in ((env :rb-ws) :agents) 0) r])

# ---- ① 额度从哪来 -------------------------------------------------------

(deftest "REQ-71：模型目录（上下文窗口 + 输出上限）"
  (fn []
    (def b (cap/model-budget "deepseek-v4.1-flash"))
    (is= 1000000 (b :context-window) "pi 目录里是 1e6")
    (is= 384000 (b :max-tokens) "pi 目录里是 384000")
    (is= 0 ((cap/model-budget "no-such-model") :max-tokens) "目录外不猜上限")
    (is= 0 ((cap/model-budget "no-such-model") :context-window) "窗口未知 = 0")))

(deftest "REQ-71：clampMaxTokensToContext（窗口未知不裁剪；已知则留出输入与 4096 安全余量）"
  (fn []
    (is= 32768 (cap/clamp-max-tokens 32768 0 12) "窗口未知 → 原样")
    (is= 4904 (cap/clamp-max-tokens 1000000 10000 1000) "10000 - 1000 - 4096 = 4904")
    (is= 1 (cap/clamp-max-tokens 100000 5000 4900) "余量为负 → 夹到下限 1（pi 的 MIN_MAX_TOKENS）")
    (is= 4000 (cap/clamp-max-tokens 4000 1000000 10) "额度本身小就照发，不放大")))

(deftest "REQ-71：预算来源 = 显式 > 模型上限 > 缺省"
  (fn []
    # 缺省：目录外的模型（mock 的缺省模型不在目录里）
    (r71-with-env [["RB_LLM" "mock"] ["RB_MODEL" nil] ["RB_MAX_TOKENS" nil]]
      (fn []
        (is= 32768 (cap/llm-max-tokens) "缺省是够推理用的大值，不再写死 8192")
        (def b (cap/llm-budget @[] @{}))
        (is= :fallback (b :source))
        (is= 32768 (b :max-tokens))))
    # 模型上限：目录里的模型
    (r71-with-env [["RB_LLM" "opencode"] ["RB_MODEL" "deepseek-v4.1-flash"]
                   ["RB_MAX_TOKENS" nil]]
      (fn []
        (is= 384000 (cap/llm-max-tokens))
        (def b (cap/llm-budget @[] @{}))
        (is= :model (b :source))
        (is= 384000 (b :max-tokens))
        (is= 1000000 (b :context-window))))
    # 显式配置压过模型上限（但仍要过 clamp）
    (r71-with-env [["RB_LLM" "opencode"] ["RB_MODEL" "deepseek-v4.1-flash"]
                   ["RB_MAX_TOKENS" "16000"]]
      (fn []
        (is= 16000 (cap/llm-max-tokens))
        (def b (cap/llm-budget @[] @{}))
        (is= :explicit (b :source))
        (is= 16000 (b :max-tokens))))
    # 调用方直接给的额度最高优先
    (is= :opts ((cap/llm-budget @[] @{:max-tokens 99}) :source))))

(deftest "REQ-71：请求体里的 max_tokens 取自预算"
  (fn []
    (def msgs @[@{:role "user" :content "hi"}])
    (def small (cap/json/decode (cap/oc-body msgs @{:model "deepseek-v4.1-flash"}
                                               @{:max-tokens 4242})))
    (is= 4242 (get small "max_tokens") "预算值原样进请求体")
    (r71-with-env [["RB_LLM" "opencode"] ["RB_MODEL" "deepseek-v4.1-flash"]
                   ["RB_MAX_TOKENS" nil]]
      (fn []
        (def b (cap/llm-budget msgs @{}))
        (def j (cap/json/decode (cap/oc-body msgs @{:model "deepseek-v4.1-flash"} b)))
        (is= 384000 (get j "max_tokens") "缺省就发模型上限（pi 的做法）")))))

# ---- ② 收尾块带 out / max，截断按 out < max 判 ---------------------------

(deftest "REQ-71：收尾块带 :out（usage.completion_tokens）与 :max（请求额度）"
  (fn []
    (def lines (r71-line-src
                 @["data: {\"choices\":[{\"delta\":{\"content\":\"hi\"},\"finish_reason\":null}]}"
                   "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"length\"}]}"
                   "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":16000,\"total_tokens\":16010}}"
                   "data: [DONE]"]))
    (def pull (cap/oai-pull lines (fn [s] (cap/json/decode s)) "mock" 16000))
    (def blocks (r71-pull-all pull))
    (is= "hi" (blocks 0) "先交文本")
    (def f (blocks 1))
    (is= "length" (f :finish))
    (is= 16000 (f :out) "out = usage 里的 completion_tokens")
    (is= 16000 (f :max) "max = 这次请求发出的额度")
    (is= 2 (f :chars) "正文长度照旧")
    (is ((blocks 2) :usage) "用量块还在收尾块之后")))

(deftest "REQ-71：provider 不报 usage 时 :out 为 nil（截断按可恢复处理）"
  (fn []
    (def lines (r71-line-src
                 @["data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"length\"}]}"
                   "data: [DONE]"]))
    (def pull (cap/oai-pull lines (fn [s] (cap/json/decode s)) "mock" 8192))
    (def f (first (r71-pull-all pull)))
    (is= "length" (f :finish))
    (is (nil? (f :out)) "没有 usage 帧就没有 out")
    (is= 8192 (f :max))))

(deftest "REQ-71：额度真的用完（out >= max）→ 立刻 60，一次都不续写"
  (fn []
    # 额度 1：mock 的正文（5 个字符）必然 >= 1 → 不是「没写完」，是「真用完了」
    (def [a r] (r71-mock-turn @{"RB_MAX_TOKENS" "1" "RB_MOCK_FINISH" "length"}))
    (is (not (r :ok)) "失败")
    (is= 60 (rb/error-code (r :error)) "编排层 60")
    (def msg (rb/error-msg (r :error)))
    (is (string/find "输出额度真的用完了" msg) "说得出病根")
    # 正文 8 个字符（引导设的 RB_MOCK_REPLY），额度 1 → 8/1
    (is (string/find "/1 tokens" msg) "点名 out/max")
    (is= 0 (a :continues) "不再空转三轮")))

(deftest "REQ-71：可恢复的截断（out < max）→ 照旧同轮续写"
  (fn []
    (def [a r] (r71-mock-turn @{"RB_MAX_TOKENS" "100000"
                                "RB_MOCK_FINISH" "length,stop"}))
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (is= 1 (a :continues) "第一次 out < max → 续写一次")
    (is= 3 (length (a :session)) "同一轮里多了一对提示与回复")))
