# tests/conformance/req-08-stream.janet —— REQ-08：Stream 是独立类型、惰性增量、到达即 flush
#
# 「到达即 flush」的观测办法：在 @Chunk 钩子里记录时间戳/顺序，证明
# 每取到一块就立刻通知，而不是等整个回复拼好再通知。

(deftest "REQ-08: 取一块 = 收到一次 @Chunk，且与自增计数一一对应"
  (fn []
    (def env (new-ws))
    (def seen @[])
    (hook-on-in env "@Chunk" (fn [] (array/push seen (rb/pop))))
    (def r (run-in env "agent \"c\" { }\nsend say \"问题\"\ndrain"))
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    # mock provider 把 "abcdefgh" 切成 ab / cd / ef / gh 四块
    (is= (tup ["ab" "cd" "ef" "gh"]) (tup seen))
    (is= "abcdefgh" (last (r :stack)))))

(deftest "REQ-08: Stream 是独立类型（不是字符串、不是数组）"
  (fn []
    (def env (new-ws))
    (def r (run-in env "agent \"c\" { }\nsend say \"x\""))
    (def s (last (r :stack)))
    (is (rb/stream? s) "send 的产物应是 Stream")
    (is (not (string? s)))
    (is (not (array? s)))
    (is= "c" (s :label))))

(deftest "REQ-08: 未取块时不会自己跑（惰性）"
  (fn []
    (def env (new-ws))
    (def pulled @[])
    (in-env env (fn []
                  # 手动造一个流：取块函数记录被调用次数
                  (def s (rb/stream-new "c" nil (fn [] (array/push pulled :tick) nil)))
                  (rb/push s)))
    (is= 0 (length pulled) "建流不等于取块")
    (in-env env (fn [] (rb/stream-next! (last (env :rb-stack)))))
    (is= 1 (length pulled) "取一次 = 调一次")))

(deftest "REQ-08: 流结束时 Done/Close 各一次，之后再取不再触发"
  (fn []
    (def env (new-ws))
    (def log @[])
    (each ev @["@Start" "@Done" "@Close"]
      (hook-on-in env ev (fn [] (array/push log ev))))
    (run-in env "agent \"c\" { }\nsend say \"x\"\ndup\ndrain\npop\ndrain")
    (is= (tup ["@Start" "@Done" "@Close"]) (tup log))))
