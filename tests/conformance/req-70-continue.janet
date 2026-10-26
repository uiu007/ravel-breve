# tests/conformance/req-70-continue.janet —— REQ-70 截断与空转（v1.0q / D-76）
#
# 守的是一条性质：**一轮不该被「模型没写完」干掉**。
#
#   provider 每次响应收尾时交一个收尾块 `@{:finish reason :chars n :calls n}`：
#     - `finish = length` → 被输出上限截断（推理内容与正文共用 `max_tokens`，D-76 的病根）
#     - `chars 0`        → 只回了推理内容 / 什么都没回
#   两种情况都在**同一轮内**续写：追加一条带 `:continue true` 的 user 提示、重发一次请求，
#   流接着吐；上限 `RB_CONTINUE_MAX`（缺省 3，0 = 关闭），用尽即 60 并点名退路。
#
# mock 的两条环境变量让这件事可复现（不联网、不花钱）：
#   `RB_MOCK_FINISH` = 逗号序列，如 `length,stop`（第 n 次响应用第 n 项，越界用最后一项）
#   `RB_MOCK_EMPTY`  = 逗号序列的 0/1（1 = 那一次响应正文为空）

(defn- mock-turn
  "设好环境变量，跑一轮（一个 user 消息 + 一次 send/drain），返回 `[agent 结果]`。"
  [vars]
  (def old @{})
  (eachp [k v] vars
    (put old k (os/getenv k))
    (os/setenv k v))
  # 还原：`(os/setenv k nil)` 才是真删除（写成空串只会留下一个空值环境变量）
  (def env (new-ws))
  (def r (run-in env "agent \"c\" { }\nsend say \"hi\"\ndrain"))
  (eachp [k _] vars
    (os/setenv k (get old k)))
  @[(in ((env :rb-ws) :agents) 0) r])

(deftest "REQ-70：正常收尾（stop）不续写"
  (fn []
    (def [a r] (mock-turn @{}))
    (is (r :ok) "应成功")
    (is= 0 (a :continues) "一次响应就收尾")
    (is= 2 (length (a :session)) "会话 = user + assistant")))

(deftest "REQ-70：finish=length → 同一轮内续写一次，然后收尾"
  (fn []
    (def [a r] (mock-turn @{"RB_MOCK_FINISH" "length,stop"}))
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (is= 1 (a :continues) "续写了一次")
    (is= 3 (length (a :session)) "user + 续写提示 + assistant（同一轮）")
    (is= "user" (((a :session) 1) :role) "第二条也是 user 消息")
    (is (string/find "上一段回复被输出上限截断了" (((a :session) 1) :content))
        "提示说清是截断")
    (is (((a :session) 1) :continue) "带 :continue 标记（好与用户原话区分）")))

(deftest "REQ-70：空转（正文 0 字）也续写，提示换成「不要输出推理」"
  (fn []
    (def [a r] (mock-turn @{"RB_MOCK_EMPTY" "1,0"}))
    (is (r :ok) "第二次有正文 → 成功")
    (is= 1 (a :continues))
    (is (string/find "上一段没有正文" (((a :session) 1) :content)) "提示点名空转")))

(deftest "REQ-70：续写到上限 → 60，并点名 RB_MAX_TOKENS 与推理模型"
  (fn []
    (def [a r] (mock-turn @{"RB_MOCK_EMPTY" "1"}))
    (is (not (r :ok)) "一直空转 → 失败")
    (is= 60 (rb/error-code (r :error)) "provider 侧的病 → 60（D-56）")
    (def msg (rb/error-msg (r :error)))
    (is (string/find "续写 3 次仍未收尾" msg) "点名次数（缺省 3）")
    (is (string/find "RB_MAX_TOKENS" msg) "点名退路之一")
    (is (string/find "推理" msg) "点名病根：推理内容与正文共用预算（D-76）")
    (is= 3 (a :continues) "三次都试过了")))

(deftest "REQ-70：RB_CONTINUE_MAX=0 关掉自动续写"
  (fn []
    (def [a r] (mock-turn @{"RB_MOCK_FINISH" "length"
                            "RB_CONTINUE_MAX" "0"}))
    (is (r :ok) "不续写 → 把截断当收尾")
    (is= 0 (a :continues))
    (is= 2 (length (a :session)))))

(deftest "REQ-70：RB_CONTINUE_MAX=1 → 只续一次，第二次截断即 60"
  (fn []
    (def [a r] (mock-turn @{"RB_MOCK_FINISH" "length"
                            "RB_CONTINUE_MAX" "1"}))
    (is (not (r :ok)))
    (is= 60 (rb/error-code (r :error)))
    (is (string/find "续写 1 次仍未收尾" (rb/error-msg (r :error))) "上限取自环境变量")))

(deftest "REQ-70：有工具调用时不续写（先把调用执行完）"
  (fn []
    # mock 的工具批：收尾块 `:calls 1` —— 有调用就不算「没写完」
    # 工具批的收尾块是 `chars 0`：若只看「没有正文」就会误判成空转，必须靠 `calls` 挡住
    (def [a r] (mock-turn @{"RB_MOCK_TOOL" "glob:{\"pattern\":\"*.janet\"}"}))
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (is= 0 (a :continues) "工具批不触发续写")
    (var saw-tool false)
    (each m (a :session) (when (= (m :role) "tool") (set saw-tool true)))
    (is saw-tool "工具确实执行了，结果以 role=tool 进会话")))

(deftest "REQ-70：default 模式带最小系统提示（pi agent 的「直接动手」）"
  (fn []
    (def env (new-ws))
    (def p (eval-top-in env "mode-of\nmode-prompt"))
    (is (string? p) "不再是 nil")
    (is (string/find "直接动手" p) "写着「直接动手」")
    (is (string/find "{{cwd}}" p) "留着占位符，每轮现拼")))
