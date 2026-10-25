# tests/conformance/req-24-duplex.janet —— REQ-24 双向不阻塞（NDJSON 协议 v1）
#
# REQ-24 的硬闸门是「收 eval 与推 stream 互不阻塞」。真进程的管道交织由
# tests/e2e/cli.sh 验收；这里验收协议层本身：
#   ① 求值**过程中**就发 chunk（不是等本轮结束才发）
#   ② 一行请求恰好一条 result（不含 chunk 的计数口径）
#   ③ 请求解析：裸文本 = eval 简写；JSON 请求；坏 JSON/非对象 → code 2 但不断服
#   ④ watch 视图流按 tick 推送，且每次至多 64 块（不饿死输入）

(defn collect-proto
  "把协议出口临时接到数组上跑 f；返回发出的消息列表。"
  [f]
  (def got @[])
  (set rb/proto-sink (fn [m] (array/push got m)))
  (set rb/stream-tap rb/proto-tap)
  (def p (protect (f)))
  (set rb/proto-sink nil)
  (set rb/stream-tap nil)
  (when (not (get p 0)) (error (get p 1)))
  got)

(def p24-decode (rb/cap-get :json/decode))

(defn types-of
  [msgs]
  (tuple ;(map (fn [m] (m :type)) msgs)))

(deftest "REQ-24：chunk 在求值过程中就发出，result 最后一条"
  (fn []
    (def env (new-ws))
    (def msgs
      (collect-proto
        (fn [] (rb/serve-eval env "send say \"hi\" agent \"c\" { }" nil false))))
    (def ts (types-of msgs))
    (is (>= (length msgs) 3) "至少 chunk+close+result")
    (is= "result" (last ts) "result 必须最后一条（前端据此判断本轮结束）")
    (is (some |(= $ "chunk") ts) "必须有 chunk")
    (is= "close" (ts (- (length ts) 2)) "close 紧接在 result 之前")
    # chunk 的序号从 0 起连续（REQ-08：到达即 flush，序号让前端排序）
    (def ns (filter (fn [x] (not (nil? x))) (map |(if (= ($ :type) "chunk") ($ :n) nil) msgs)))
    (is (deep= (tup (range (length ns))) (tup ns)) "chunk 序号连续（0,1,2,…）")))

(deftest "REQ-24：一路读一路写——新一轮求值不受上一轮流影响"
  (fn []
    (def env (new-ws))
    (def first-msgs
      (collect-proto
        (fn [] (rb/serve-eval env "send say \"一\" agent \"c\" { }" 1 false))))
    (def second-msgs
      (collect-proto
        (fn [] (rb/serve-eval env "+ 1 2" 2 false))))
    (is (> (length first-msgs) 2))
    (is= 1 (length second-msgs) "第二次求值只有一条 result，不再重放上一轮的 chunk")
    (is= 2 ((first second-msgs) :id))))

(deftest "REQ-24：裸文本 = eval 简写"
  (fn []
    (def req (rb/serve-parse "1 2" p24-decode))
    (is= "eval" (req :type))
    (is= "1 2" (get (req :msg) "src"))))

(deftest "REQ-24：JSON 请求带 type 与 id"
  (fn []
    (def req (rb/serve-parse "{\"type\":\"eval\",\"src\":\"1\",\"id\":9}" p24-decode))
    (is= "eval" (req :type))
    (is= "1" (get (req :msg) "src"))
    (is= 9 (get (req :msg) "id"))))

(deftest "REQ-24：坏 JSON → 协议错误 2，但服务不断"
  (fn []
    (def a (rb/serve-parse "{\"type\":" p24-decode))
    (is= "bad" (a :type))
    (is (string? (a :error)))
    # 也不是 JSON 的「像 JSON」行：同样只报一次错（REQ-42：失败不终止循环）
    (def b (rb/serve-parse "{\"x\": }" p24-decode))
    (is= "bad" (b :type))
    (def c (rb/serve-parse "{}" p24-decode))
    (is= "eval" (c :type) "缺 type 时按 eval 处理（协议 v1）")))

(deftest "REQ-24：`{ 1 2 }` 是字面量源码，不是 JSON 请求"
  (fn []
    (def req (rb/serve-parse "{ 1 2 }" p24-decode))
    (is= "eval" (req :type))
    (is= "{ 1 2 }" (get (req :msg) "src"))))

(deftest "REQ-24：未知请求类型不改协议形状（仍是一条 result）"
  (fn []
    (def msgs (collect-proto (fn [] (rb/serve-bad "未知的请求类型：foo（协议 v1）"))))
    (is= 1 (length msgs))
    (is= "result" ((first msgs) :type))
    (is= 2 ((first msgs) :code))))

(deftest "REQ-24：watch 视图流按 tick 推送"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (is (rb/stream? (eval-top-in env "watch agent \"c\" { }")) "watch 后栈上是视图流")
    (def a ((ws :agents) 0))
    (rb/agent-append! a @{:role "user" :content "一"})
    (def msgs (collect-proto (fn [] (rb/watch-tick! env))))
    (is= 1 (length msgs))
    (is= "chunk" ((first msgs) :type))
    (is= "c" ((first msgs) :stream))
    (is (string/find ":content \"一\"" ((first msgs) :text)) "视图块带上内容")
    (is= 0 (rb/watch-tick! env) "没有新条目时不再推送")))

(deftest "REQ-24：tick 单次上限 64 块（宁可下轮再推，也不饿死输入）"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (eval-stack-in env "watch agent \"c\" { }")
    (def a ((ws :agents) 0))
    (for i 0 100 (rb/agent-append! a @{:role "user" :content (string i)}))
    (def msgs (collect-proto (fn [] (rb/watch-tick! env))))
    (is= 64 (length msgs))
    (def rest (collect-proto (fn [] (rb/watch-tick! env))))
    (is= 36 (length rest) "剩下的下一轮推完")))
