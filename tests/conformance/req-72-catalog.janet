# tests/conformance/req-72-catalog.janet —— REQ-72 模型目录的兜底、估算与自动更新（v1.0s / D-78）
#
# 守的四条性质：
#
#   ① **目录外兜底照抄 pi 的两个 `??`**：`contextWindow ?? 128000` / `maxTokens ?? 16384`。
#      目录外的模型也有窗口（不再"未知 = 不夹紧"），于是夹紧对所有模型一个口径。
#
#   ② **`est` 两种算法取大者**：A 字节法 `字节/4`（= pi 的 `chars/4`，纯 ASCII 一致）；
#      B 字符法 `ASCII/4 + 非 ASCII 字节/3`（中日韩一个字一个 token）。
#      纯英文两者相等（不为英文多付 4 倍），中文由 B 兜住（A 只有 0.75 token/字）。
#
#   ③ **自动更新只登记名字**：`GET /models` 不报窗口/额度，所以 `catalog-refresh`
#      把没见过的名字记成「知道名字、不知道额度」（`:max-tokens 0`、窗口 128000），
#      人核过的条目一个数都不改，重复刷新幂等（第二次返回 0）。
#
#   ④ **自动与否是钩子的启停**：缺省不装在任何事件上；`@on @Start [ catalog-refresh ]`
#      才有，`@off @Start` 即关（本仓不替用户决定要不要联网）。

(defn- r72-with-env
  "临时设一批环境变量（`[k v]` 的数组，值 nil = 删除），跑 body，最后按**旧值**还原。"
  [pairs body]
  (def old @[])
  (each pair pairs
    (array/push old (os/getenv (pair 0)))
    (os/setenv (pair 0) (pair 1)))
  (def r (protect (body)))
  (var i 0)
  (each pair pairs
    (os/setenv (pair 0) (old i))
    (++ i))
  (if (get r 0) (get r 1) (error (get r 1))))

(defn- r72-forget!
  "把目录里某个名字抹掉（测试用；`put` 给 nil 就是删键）。"
  [name]
  (put cap/model-catalog name nil))

(defn- r72-round
  "跑一轮（一个 user 消息 + send/drain），返回结果；`setup` 是设在 `agent` 之前的方言源。"
  [setup]
  (def env (new-ws))
  (run-in env (string setup "\nagent \"c\" { }\nsend say \"hi\"\ndrain")))

# ---- ① 兜底 ------------------------------------------------------------------

(deftest "REQ-72：目录外的模型走 pi 的 128000 / 16384"
  (fn []
    (def b (cap/model-budget "no-such-model-at-all"))
    (is= 128000 (b :context-window) "pi: `contextWindow ?? 128000`")
    (is= 0 (b :max-tokens) "额度不知道就记 0，不冒充核过")
    (r72-with-env [["RB_LLM" "mock"] ["RB_MODEL" nil] ["RB_MAX_TOKENS" nil]]
      (fn []
        (is= 16384 (cap/llm-max-tokens) "pi: `maxTokens ?? 16384`")
        (def bd (cap/llm-budget @[] @{}))
        (is= :fallback (bd :source))
        (is= 16384 (bd :max-tokens))
        (is= 128000 (bd :context-window) "窗口有了，夹紧才有意义")))))

# ---- ② 估算 ------------------------------------------------------------------

(deftest "REQ-72：est 两种算法取大者（英文不放大，中文不低估）"
  (fn []
    (is= 0 (cap/est-text-tokens "") "空是 0")
    (is= 1 (cap/est-text-tokens "abcd") "4 个 ASCII = 1（字节法 = 字符法）")
    (is= 2 (cap/est-text-tokens "abcdefgh") "8 个 ASCII = 2")
    # 「你好世界你好世界」= 8 个字 = 24 字节：字节法 24/4 = 6，字符法 8 → 取大者 8
    (is= 8 (cap/est-text-tokens "你好世界你好世界") "中文一个字一个 token")
    (is= 6 (max 6 (math/ceil (/ 24 4))) "（对照：只按字节会是 6）")
    # 混排：4 个 ASCII（1）+ 4 个汉字（4）= 5
    (is= 5 (cap/est-text-tokens "abcd你好世界") "混排相加")
    (is (<= (math/ceil (/ (length "你好世界你好世界") 4))
            (cap/est-text-tokens "你好世界你好世界"))
        "恒不小于字节法")))

# ---- ③ 刷新只登记名字 ---------------------------------------------------------

(deftest "REQ-72：catalog-refresh 只登记名字，不改已核过的数，且幂等"
  (fn []
    (r72-with-env [["RB_LLM" "mock"] ["RB_MODEL" nil]]
      (fn []
        (r72-forget! "mock")
        (is= 1 (cap/catalog-refresh) "第一次新增 1 条（mock）")
        (def e (get (cap/catalog) "mock"))
        (is e "目录里有了 mock")
        (is= 0 (e :max-tokens) "额度仍记 0（`/models` 不报额度）")
        (is= 128000 (e :context-window) "窗口记 pi 的缺省")
        (is= 16384 (cap/llm-max-tokens) "预算因此仍走兜底")
        (is= 0 (cap/catalog-refresh) "再刷一次不重复登记")
        (is= 384000 ((cap/model-budget "deepseek-v4.1-flash") :max-tokens)
            "已核过的条目一个数都不改")))))

(deftest "REQ-72：目录是副本（改了不影响预算）"
  (fn []
    (def c (cap/catalog))
    (put c "deepseek-v4.1-flash" @{:context-window 1 :max-tokens 1})
    (is= 384000 ((cap/model-budget "deepseek-v4.1-flash") :max-tokens) "真目录没被改")
    (is= 1000000 ((cap/model-budget "deepseek-v4.1-flash") :context-window))))

# ---- ④ 钩子的启停 -------------------------------------------------------------

(deftest "REQ-72：缺省不装钩子——跑一轮不会联网登记"
  (fn []
    (r72-with-env [["RB_LLM" "mock"] ["RB_MODEL" nil] ["RB_MAX_TOKENS" nil]]
      (fn []
        (r72-forget! "mock")
        (def r (r72-round ""))
        (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
        (is (nil? (get cap/model-catalog "mock")) "没装钩子就不动目录")))))

(deftest "REQ-72：@on @Start [ catalog-refresh ] 开启，@off @Start 关闭"
  (fn []
    (r72-with-env [["RB_LLM" "mock"] ["RB_MODEL" nil] ["RB_MAX_TOKENS" nil]]
      (fn []
        # 开：每轮开始刷新一次
        (r72-forget! "mock")
        (def r1 (r72-round "@on @Start [ catalog-refresh ]"))
        (is (r1 :ok) (string "应成功：" (if (r1 :ok) "" (rb/error-msg (r1 :error)))))
        (is (get cap/model-catalog "mock") "钩子跑了，名字进了目录")
        # 关：再抹掉，装过又卸掉 → 不会回来
        (r72-forget! "mock")
        (def r2 (r72-round "@on @Start [ catalog-refresh ]\n@off @Start"))
        (is (r2 :ok) (string "应成功：" (if (r2 :ok) "" (rb/error-msg (r2 :error)))))
        (is (nil? (get cap/model-catalog "mock")) "@off 之后不再刷新")))))
