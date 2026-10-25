# tests/conformance/req-52-modes.janet —— REQ-52 处理流程（模式）层
#
# REQ-52（v1.0f 新增，D-59）：一轮请求「怎么被处理」有**显式表示**——
#   模式 = 一张表（钩子 + 开关 + 系统提示 + 声明的工具），
#   与工作区现状可以双向转换（`mode` 装进去、`mode-of` 取出来）。
#
# 预制模式 `ptc` 仿 DeepSeek harness 的 Programmatic Tool Calling：
# 模型不发 tool_call，而是把它要做的**一串**工具编排写成一段 ravel 程序，
# 交给唯一的工具 `eval` 执行——于是「多步工具编排」不再依赖模型的回合数。

(deftest "REQ-52：mode-of 与 mode 互逆（default 往返）"
  (fn []
    (def env (new-ws))
    (def m (eval-top-in env "mode-of"))
    (is (table? m) "mode-of 交出模式表")
    (is= :mode (m :kind) "有类型标记（D-59）")
    (is= "default" (m :name))
    (is= 8 (length (keys (m :hooks))) "8 个事件齐全（未声明 = 空数组）")
    (is= (rb/mode-get "default") m "与预制 default 相等")
    (is= 0 (run-in-exit env "mode mode-of"))))

(deftest "REQ-52：modes 列预制模式；未知名字 → 20"
  (fn []
    (def env (new-ws))
    (is= (tup ["default" "ptc"]) (tup (eval-top-in env "modes")))
    (is= 20 (run-in-exit env "mode \"nope\""))))

(deftest "REQ-52：ptc 模式只留一个 eval 工具，并注入系统提示"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (is= 0 (run-in-exit env "mode \"ptc\""))
    (is= (tup ["eval"]) (tup (sort (keys (ws :tools)))) "工具表只剩 eval")
    (is (string/find "PTC" (ws :mode-prompt)) "系统提示就位")
    (is= "ptc" (ws :mode))
    (def m (eval-top-in env "mode-of"))
    (is= (rb/mode-get "ptc") m "往返相等")))

(deftest "REQ-52：ptc 一轮 —— 模型发一次 eval，程序里串起两次工具调用"
  (fn []
    (def env (new-ws))
    (is= 0 (run-in-exit env "mode \"ptc\""))   # 先切模式：切模式会整体替换钩子
    (os/setenv "RB_MOCK_TOOL" "eval:{\"src\": \"+ 1 2\"}")
    (def hits @[])
    (hook-on-in env "@Toolcall" (fn [] (array/push hits ((rb/pop) :name))))
    (def r (run-in env (string "agent \"c\" { }\n"
                               "send say \"算一下\"\n"
                               "drain")))
    (os/setenv "RB_MOCK_TOOL" nil)
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (is= (tup ["eval"]) (tup hits) "只发生一次工具调用（模型不再逐步发）")
    (def a (last (ws-agents env)))
    (is= (tup ["user" "assistant" "tool" "assistant"])
         (tup (map (fn [u] (u :role)) (a :session))))
    (is= "3" (((a :session) 2) :content) "程序结果以 JSON 追加（栈顶 = 工具结果）")
    (is= "abcdefgh" (((a :session) 3) :content) "同一个流继续吐最终文本")
    (is= 4 (length (a :session)) "提示只进请求，不进会话历史（D-59）")))

(deftest "REQ-52：ptc 程序里能用 invoke 串多个工具（程序内编排）"
  (fn []
    (def env (new-ws))
    (is= 0 (run-in-exit env "mode \"ptc\""))
    (os/setenv "RB_MOCK_TOOL" "eval:{\"src\": \"invoke \\\"add2\\\" H{ \\\"a\\\" 40 }\"}")
    (def n @[0])
    (hook-on-in env "@Toolcall" (fn [] (++ (n 0))))
    (def r (run-in env (string "deftool \"add2\" \"加 2\" [ at \"a\"\n+ 2 ]\n"
                               "agent \"c\" { }\n"
                               "send say \"算\"\n"
                               "drain")))
    (os/setenv "RB_MOCK_TOOL" nil)
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (is= 1 (n 0) "外层只发一次 eval")
    (def a (last (ws-agents env)))
    (is= "42" (((a :session) 2) :content) "程序里的 invoke 打通了 add2")))

(deftest "REQ-52：ptc 的程序失败 → 60，本轮作废、栈不脏"
  (fn []
    (def env (new-ws))
    (is= 0 (run-in-exit env "mode \"ptc\""))
    (os/setenv "RB_MOCK_TOOL" "eval:{\"src\": \"pop pop\"}")
    (def r (run-in env (string "agent \"c\" { }\n"
                               "send say \"算\"\n"
                               "drain")))
    (os/setenv "RB_MOCK_TOOL" nil)
    (is (not (r :ok)) "工具失败不算完成")
    (is= 60 (rb/error-code (r :error)) "编排级错误码")
    (is= 0 (length (env :rb-stack)) "失败不留栈效果（D-55）")))

(deftest "REQ-52：历史标记（turn / from / mode）默认开，可按项关闭"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (run-in env "agent \"c\" { }")
    (def a (last (ws-agents env)))
    (val-in env (fn [] (rb/agent-append! a @{:role "user" :content "x"})))
    (def u ((a :session) 0))
    (is= 1 (u :turn))
    (is= "c" (u :from))
    (is= "default" (u :mode))
    (is= 0 (run-in-exit env "flag-set false \"history-origin\""))
    (val-in env (fn [] (rb/agent-append! a @{:role "assistant" :content "y"})))
    (is= nil (((a :session) 1) :from) "来源标记被关掉")
    (is= 2 (((a :session) 1) :turn) "轮次标记照旧")))

(deftest "REQ-52：标记不改变 provider 看到的请求（只多出 system 提示这一条）"
  (fn []
    (def env (new-ws))
    (run-in env "agent \"c\" { }")
    (def a (last (ws-agents env)))
    (rb/agent-append! a @{:role "user" :content "x"})
    (def ms (rb/messages-of a))
    (is= (tup ["user"]) (tup (map (fn [m] (m :role)) ms)) "标记不是消息")
    (is= (tup [:content :role]) (tup (sort (keys (ms 0)))) "请求里只有 role / content")))
