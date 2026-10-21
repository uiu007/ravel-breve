# tests/conformance/req-28-show-watch.janet —— REQ-28 `show` / `watch`
#
# REQ-28：`show` = 平铺打印（逐元素）；`watch` = 语法糖（查询绑定 + 把对应
#         stream 交给前端）。REQ-27 的「末尾追加最新 stream」在栈层的对应物
#         就是**视图流**：先补历史，再随 append 吐新增条目。
#
# 视图流是**只读观察者**：不进本轮列表，因此默认收尾钩子不会把它 append 回
# 会话（否则会话会自我膨胀）。

(deftest "REQ-28：show 逐元素（序列 → 每元素一行）"
  (fn []
    (def env (new-ws))
    (def out @"")
    (put env :out out)                       # print 走 (dyn :out)
    (run-in env "show { 1 \"two\" }")
    (is= "1\n\"two\"\n" (string out))))

(deftest "REQ-28：show 非序列 → 一行"
  (fn []
    (def env (new-ws))
    (def out @"")
    (put env :out out)
    (run-in env "show H{ \"a\" 1 }")
    (is= "@{\"a\" 1}\n" (string out))))

(deftest "REQ-28：watch 吃掉 Agent、交出 Stream"
  (fn []
    (def env (new-ws))
    (def r (run-in env "watch agent \"c\" { }"))
    (is= true (r :ok))
    (def s (last (r :stack)))
    (is (rb/stream? s) "watch 的产物是流")
    (is= true (s :watch))
    (is= nil (s :agent) "视图流不绑定 agent（不进收尾钩子，REQ-18）")
    (is= "c" (s :label))))

(deftest "REQ-28：视图流先补历史"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (def r (run-in env "watch agent \"c\" { }"))
    (def s (last (r :stack)))
    (def a ((ws :agents) 0))
    (rb/agent-append! a @{:role "user" :content "一"})
    (rb/agent-append! a @{:role "assistant" :content "二"})
    (is= "@{:content \"一\" :role \"user\"}" (rb/stream-next! s))
    (is= "@{:content \"二\" :role \"assistant\"}" (rb/stream-next! s))
    (is= nil (rb/stream-next! s) "取尽 = 暂时没有新条目")
    (is= :open (s :state) "视图流不因取尽而关闭（REQ-08 的 close 留给真流）")))

(deftest "REQ-28：视图流随后续 append 增长"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (def s (last ((run-in env "watch agent \"c\" { }") :stack)))
    (def a ((ws :agents) 0))
    (rb/agent-append! a @{:role "user" :content "一"})
    (is= "@{:content \"一\" :role \"user\"}" (rb/stream-next! s))
    (rb/agent-append! a @{:role "assistant" :content "二"})
    (is= "@{:content \"二\" :role \"assistant\"}" (rb/stream-next! s) "新增条目才出现")))

(deftest "REQ-28：两个 watch 的游标互不影响"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (run-in env "watch agent \"c\" { }")
    (def a ((ws :agents) 0))
    # 同一 agent 上开两个视图：都用宿主 API，避免再 `agent` 造出新的血亲
    (defn view []
      (val-in env (fn [] (rb/push a) (rb/watch) (rb/peek))))
    (def s1 (view))
    (def s2 (view))
    (rb/agent-append! a @{:role "user" :content "一"})
    (is= "@{:content \"一\" :role \"user\"}" (rb/stream-next! s1))
    (is= "@{:content \"一\" :role \"user\"}" (rb/stream-next! s2) "第二个视图从头开始")))

(deftest "REQ-28：视图流不会被收尾钩子并回会话"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (run-in env "watch agent \"c\" { }")
    (def a ((ws :agents) 0))
    (rb/agent-append! a @{:role "user" :content "一"})
    (def before (length (a :session)))
    (run-in env "1")                       # 再跑一轮，触发 @RoundDone 判定
    (is= before (length (a :session)) "会话不因视图流而增长")
    (is= 0 (length (ws :round)) "视图流不进本轮列表")))

(deftest "REQ-28：视图流登记进工作区的 watch 列表（--serve 推送用）"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (run-in env "watch agent \"c\" { }")
    (is= 1 (length (ws :watch)))
    (is= "c" (((ws :watch) 0) :label))
    (run-in env "watch agent \"d\" { }")
    (is= 2 (length (ws :watch)))))
