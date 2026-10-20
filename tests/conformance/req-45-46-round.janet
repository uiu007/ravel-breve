# tests/conformance/req-45-46-round.janet —— REQ-45 一轮 = list Stream / REQ-46 Stream → Utter

(deftest "REQ-45: 一轮里多次 send，收尾钩子把每个 stream 都并回各自 agent"
  (fn []
    (def env (new-ws))
    (def r (run-in env (string
                         "agent \"a\" { }\n"
                         "agent \"b\" { }\n"
                         "swap\n"
                         "send say \"给 a\"\n"
                         "swap\n"
                         "send say \"给 b\"")))
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (def as (ws-agents env))
    (def a (as 0))
    (def b (as 1))
    (is= (tup ["给 a" "abcdefgh"]) (tup (map (fn [u] (u :content)) (a :session)))
         "第二次 send 的目标是栈上的 a")
    (is= (tup ["给 b" "abcdefgh"]) (tup (map (fn [u] (u :content)) (b :session))))
    (is= 0 (length ((env :rb-ws) :round)) "收尾后本轮列表清空")))

(deftest "REQ-45: 未取块的 stream 也会在收尾时被取尽并合并"
  (fn []
    (def env (new-ws))
    (run-in env "agent \"c\" { }\ndup\nsend say \"问\"\npop")
    (def a (last (ws-agents env)))
    (is= 2 (length (a :session)))
    (is= "abcdefgh" ((last (a :session)) :content))))

(deftest "REQ-45: 收尾钩子的载荷就是本轮 list Stream"
  (fn []
    (def env (new-ws))
    (def got @[])
    (hook-on-in env "@RoundDone" (fn [] (array/push got (rb/pop))))
    (run-in env "agent \"c\" { }\nsend say \"问\"")
    (is= 1 (length got))
    (def lst (got 0))
    (is= 1 (length lst))
    (is (rb/stream? (lst 0)) "载荷元素是 Stream")))

(deftest "REQ-46: Stream → Utter 是显式词，且给出 assistant 文本"
  (fn []
    (def env (new-ws))
    (def r (run-in env "agent \"c\" { }\n@off @RoundDone\nsend say \"问\"\nutter"))
    (def u (last (r :stack)))
    (is= "assistant" (u :role))
    (is= "abcdefgh" (u :content))))

(deftest "REQ-46: 自动路径与手动路径共用同一个转换（同结果）"
  (fn []
    (def e1 (new-ws))
    (run-in e1 "agent \"c\" { }")
    # 自动：默认收尾钩子做 ① 绑定 → ② 转 utter → ③ append → ④ 退订
    (run-in e1 "dup\nsend say \"问\"")
    (def a1 (last (ws-agents e1)))

    (def e2 (new-ws))
    (run-in e2 "agent \"c\" { }")
    (run-in e2 (string
                 "@off @RoundDone\n"
                 "dup\n"
                 "send say \"问\"\n"
                 "utter\n"
                 "append"))
    (def a2 (last (ws-agents e2)))

    (is= (tup (map (fn [u] (u :content)) (a1 :session)))
         (tup (map (fn [u] (u :content)) (a2 :session)))
         "两条路径应得到同样的会话")
    (is= 2 (length (a2 :session)))))

(deftest "REQ-36: Stream 的四个词都在词表里"
  (fn []
    (def env (new-ws))
    (def r (run-in env (string
                         "agent \"c\" { }\n"
                         "@off @RoundDone\n"
                         "dup\n"
                         "send say \"问\"\n"
                         "dup\n"
                         "next\n"
                         "pop\n"
                         "dup\n"
                         "drain\n"
                         "pop\n"
                         "stop")))
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (is (rb/stream? (last (r :stack))) "stop 保留 Stream 句柄")))

(deftest "REQ-36: 两个流可以交错推进（合作式，不互相阻塞）"
  (fn []
    (def env (new-ws))
    (defn it-of [items]
      (var i 0)
      (fn []
        (when (< i (length items))
          (def x (items i))
          (++ i)
          x)))
    (var a nil)
    (var b nil)
    (in-env env (fn []
                  (set a (rb/stream-new "a" nil (it-of @["a1" "a2"])))
                  (set b (rb/stream-new "b" nil (it-of @["b1" "b2"])))
                  (rb/push (rb/stream-next! a))
                  (rb/push (rb/stream-next! b))
                  (rb/push (rb/stream-next! a))
                  (rb/push (rb/stream-next! b))))
    (is= (tup ["a1" "b1" "a2" "b2"]) (tup (env :rb-stack))
         "交替取块，两个流各自推进")))

(deftest "REQ-36: 推进一个流不影响另一个流的进度"
  (fn []
    (def env (new-ws))
    (defn it-of [items]
      (var i 0)
      (fn []
        (when (< i (length items))
          (def x (items i))
          (++ i)
          x)))
    (var a nil)
    (var b nil)
    (in-env env (fn []
                  (set a (rb/stream-new "a" nil (it-of @["a1" "a2" "a3"])))
                  (set b (rb/stream-new "b" nil (it-of @["b1" "b2"])))
                  (rb/stream-next! a)
                  (rb/stream-next! a)
                  (rb/push (rb/stream-drain! b))))
    (is= "b1b2" (last (env :rb-stack)))
    (is= "a1a2" (string (a :text)))))
