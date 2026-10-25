# tests/conformance/req-47-51-capabilities.janet —— v1.0d 的 agent 基本能力
#
# REQ-47 角色是字段 + `saysys`
# REQ-48 工具调用（deftool / invoke / @Toolcall / 同一流继续）
# REQ-49 失败重试在钩子层（resend 接受 Stream）
# REQ-50 上下文压缩在钩子层（L1 词 + 新 agent）
# REQ-51 编排三条边（-> / onfail / subscribe）

(defn with-chat
  "临时替换 `:llm/chat` 能力（测试用假 provider），跑完后还原。"
  [f body]
  (def orig (rb/cap-get :llm/chat))
  (rb/cap-put :llm/chat f)
  (def p (protect (body)))
  (rb/cap-put :llm/chat orig)
  (when (not (get p 0)) (error (get p 1)))
  (get p 1))

(defn chat-of-text
  "假 provider：把 text 一次吐出，返回取块函数。"
  [text]
  (fn [messages opts]
    (var sent false)
    (fn []
      (if sent nil (do (set sent true) text)))))

(defn chat-failing
  "假 provider：第一次失败（60），之后给 text。"
  [text state]
  (fn [messages opts]
    (var sent false)
    (fn []
      (if (not (state :failed-once))
        (do
          (put state :failed-once true)
          (rb/raise (rb/exit-table :orchestration-base) "假 provider：第一次失败"))
        (if sent nil (do (set sent true) text))))))

# ---- REQ-47 ----

(deftest "REQ-47: saysys 给出 role=system 的 utter，Utter 可造任意角色"
  (fn []
    (def env (new-ws))
    (is= "system" (eval-top-in env "saysys \"你是助手\"\nRole"))
    (is= "你是助手" (eval-top-in env "saysys \"你是助手\"\nContent"))
    (is= "tool" (eval-top-in env "Utter \"tool\" \"42\"\nRole"))
    (is= "42" (eval-top-in env "Utter \"tool\" \"42\"\nContent"))))

(deftest "REQ-47: system 消息进会话后原样出现在 provider 的消息数组里"
  (fn []
    (def env (new-ws))
    (run-in env "agent \"c\" { }\nappend saysys \"你是助手\"\nappend say \"你好\"")
    (def a (last (ws-agents env)))
    (def ms (rb/messages-of a))
    (is= (tup ["system" "user"]) (tup (map (fn [m] (m :role)) ms)))
    (is= "你是助手" ((ms 0) :content))))

(deftest "REQ-47: 会话仍是同一种值（表），没有新增类型"
  (fn []
    (def env (new-ws))
    (def u (eval-top-in env "saysys \"x\""))
    (is (table? u) "utter 是表")
    (is= (tup [:content :role]) (tup (sort (keys u))) "只有两个字段")))

# ---- REQ-48 ----

(deftest "REQ-48: deftool 注册后 invoke 直接调用（不经模型）"
  (fn []
    (def env (new-ws))
    (is= 42 (eval-top-in env (string "deftool \"add2\" \"加 2\" [ at \"a\"\n+ 2 ]\n"
                                     "invoke \"add2\" H{ \"a\" 40 }")))
    # D-61：能力层默认装了四个文件/进程工具，所以这里是「deftool 的那个必须在」
    (is (not (nil? (get ((env :rb-ws) :tools) "add2"))) "工作区里有一张工具表")))

(deftest "REQ-48: 未注册的工具报 60"
  (fn []
    (def env (new-ws))
    (is= 60 (run-in-exit env "invoke \"nope\" H{ }"))))

(deftest "REQ-48: 模型发起工具调用 → 工具跑一次、@Toolcall 一次、会话四段齐"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_MOCK_TOOL" "add2:{\"a\":40}")
    (def hits @[])
    (hook-on-in env "@Toolcall" (fn [] (array/push hits ((rb/pop) :name))))
    (def r (run-in env (string "deftool \"add2\" \"加 2\" [ at \"a\"\n+ 2 ]\n"
                               "agent \"c\" { }\n"
                               "send say \"算一下\"\n"
                               "drain")))
    (os/setenv "RB_MOCK_TOOL" nil)
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (is= (tup ["add2"]) (tup hits) "钩子被调一次，名字是 add2")
    (def a (last (ws-agents env)))
    (is= (tup ["user" "assistant" "tool" "assistant"])
         (tup (map (fn [u] (u :role)) (a :session))))
    (is= "42" (((a :session) 2) :content) "工具结果以 JSON 追加")
    (is= "abcdefgh" (((a :session) 3) :content) "同一个流继续吐最终文本")
    (def tcs (((a :session) 1) :tool-calls))
    (is= 1 (length tcs) "assistant 消息只带一条 tool_calls")
    (is= "call_mock" (get (tcs 0) "id") "tool_calls 保留 provider 的原始形状")
    (is= 0 (length ((env :rb-ws) :round)) "收尾后本轮清空")))

(deftest "REQ-48: 工具结果真的参与了下一轮请求（会话里能看见 tool 消息）"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_MOCK_TOOL" "add2:{\"a\":1}")
    (run-in env (string "deftool \"add2\" \"加 2\" [ at \"a\"\n+ 2 ]\n"
                        "agent \"c\" { }\nsend say \"算\"\ndrain"))
    (os/setenv "RB_MOCK_TOOL" nil)
    (def a (last (ws-agents env)))
    (def ms (rb/messages-of a))
    (is= (tup ["user" "assistant" "tool" "assistant"]) (tup (map (fn [m] (m :role)) ms)))
    (is= "3" ((ms 2) :content))
    (is= "call_mock" ((ms 2) :tool_call_id) "tool 消息回填 tool_call_id")
    (is (not (nil? ((ms 1) :tool_calls))) "assistant 消息带 tool_calls")))

(deftest "REQ-48: 工具表进 provider 请求（tools 字段）"
  (fn []
    # 空工具表不带 tools 的情形由 core-only 覆盖（能力层默认会装 4 个工具，D-61）；
    # 这里验「表里有的都进请求」，且名字/描述照抄。
    (def env (new-ws))
    (var seen nil)
    (with-chat (fn [messages opts] (set seen (opts :tools)) (chat-of-text "x"))
               (fn [] (run-in env (string "deftool \"t\" \"描述\" [ 1 ]\n"
                                           "agent \"c\" { }\nsend say \"问\""))))
    (def names (map |(($ :function) :name) seen))
    (is (not (nil? (find |(= "t" $) names))) "deftool 的工具进请求")
    (each d seen
      (when (= "t" ((d :function) :name))
        (is= "描述" ((d :function) :description))))))

(deftest "REQ-48: @off @Toolcall 后工具不执行，流停在待外部动作（本轮未完成）"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_MOCK_TOOL" "add2:{\"a\":40}")
    (var called 0)
    (put ((env :rb-ws) :tools) "add2" @{:desc "加 2" :fn (fn [] (++ called) 1)})
    (def r (run-in env (string "@off @Toolcall\nagent \"c\" { }\n"
                               "send say \"算\"\ndrain")))
    (os/setenv "RB_MOCK_TOOL" nil)
    (is= 0 called "钩子关掉后工具不该被调用")
    (is= 60 (if (r :ok) 0 (rb/error-code (r :error))) "停在待外部动作 → 60")
    (is= 0 (length ((env :rb-ws) :round)) "本轮作废、不残留")))

(deftest "REQ-48: 工具本体失败 → 60，且流进入 failed"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_MOCK_TOOL" "boom:{}")
    (def r (run-in env (string "deftool \"boom\" \"炸\" [ fail \"坏了\" ]\n"
                               "agent \"c\" { }\nsend say \"算\"\ndrain")))
    (os/setenv "RB_MOCK_TOOL" nil)
    (is= 60 (if (r :ok) 0 (rb/error-code (r :error))))))

# ---- REQ-49 ----

(deftest "REQ-49: @on @Fail 里 resend 重试；失败流不并入会话，本轮正常收尾"
  (fn []
    (def env (new-ws))
    (def state @{:failed-once false})
    (run-in env "@on @Fail [ pop resend pop ]")
    (with-chat (chat-failing "重试成功" state)
               (fn [] (run-in env "agent \"c\" { }\nsend say \"问\"")))
    (def a (last (ws-agents env)))
    (is= (tup ["问" "重试成功"]) (tup (map (fn [u] (u :content)) (a :session))))
    (is= 0 (length ((env :rb-ws) :round)) "两个流都被收掉")))

(deftest "REQ-49: 不装 @Fail 钩子时不静默重试（同一场景失败）"
  (fn []
    (def env (new-ws))
    (def state @{:failed-once false})
    (def r (with-chat (chat-failing "重试成功" state)
                      (fn [] (run-in env "agent \"c\" { }\nsend say \"问\""))))
    (is= 60 (if (r :ok) 0 (rb/error-code (r :error))))
    (def a (last (ws-agents env)))
    (is= 1 (length (a :session)) "只剩用户那条，失败回复不入会话")))

(deftest "REQ-49: resend 接受 Stream（钩子里不解析标签）"
  (fn []
    (def env (new-ws))
    (def state @{:failed-once false})
    (run-in env "@on @Fail [ pop resend pop ]")
    (with-chat (chat-failing "ok" state)
               (fn [] (run-in env "agent \"c\" { }\nsend say \"问\"")))
    (def a (last (ws-agents env)))
    (is= "ok" ((last (a :session)) :content))))

# ---- REQ-50 ----

(deftest "REQ-50: 压缩 = 钩子里的 L1 词 + 新 agent，老 agent 不变"
  (fn []
    (def env (new-ws))
    (run-in env (string "agent \"old\" { }\n"
                        "append say \"一\"\nappend say \"二\"\nappend say \"三\"\n"
                        "append say \"四\"\n"
                        "session\ntake -2\nagent \"new\""))
    (def old (first (ws-agents env)))
    (def new (last (ws-agents env)))
    (is= 4 (length (old :session)) "老会话只追加、不被裁剪")
    (is= (tup ["三" "四"]) (tup (map (fn [u] (u :content)) (new :session))))))

(deftest "REQ-50: 压缩钩子能在 @RoundDone 里改出摘要会话（策略在用户侧）"
  (fn []
    (def env (new-ws))
    (var summarized 0)
    (hook-on-in env "@RoundDone"
                (fn []
                  (rb/pop)
                  (def a (last (ws-agents env)))
                  (def sess (tuple ;(slice (a :session) 0 (min 1 (length (a :session))))))
                  (rb/agent-add! (rb/agent-new "sum" sess nil))   # 新血缘，不动老会话
                  (++ summarized)))
    (run-in env "agent \"c\" { }\nsend say \"问\"")
    (is= 1 summarized)
    (is= 2 (length (ws-agents env)) "多了一个摘要 agent")
    (is= 1 (length ((last (ws-agents env)) :session)))))

# ---- REQ-51 ----

(deftest "REQ-51: -> 给后者记上线性来源边"
  (fn []
    (def env (new-ws))
    (eval-top-in env "agent \"a\" { }")
    (eval-top-in env "agent \"b\" { }")
    # 书写 `-> a b` = a → b（最左实参先出栈）
    (def r (run-in env "->\norigin"))
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (is= (tup ["a"]) (tup (first (r :stack))) "a 的来源里有 b")))

(deftest "REQ-51: unsubscribe 后 bcast 不达，subscribe 后又能达"
  (fn []
    (def env (new-ws))
    (def r1 (run-in env "agent \"a\" { }\nunsubscribe\npop\nbcast say \"hi\" { }"))
    (is (r1 :ok) (string "应成功：" (if (r1 :ok) "" (rb/error-msg (r1 :error)))))
    (is= 0 (length (last (r1 :stack))) "注销后广播不到它")
    (def r2 (run-in env "agent \"a\" { }\nunsubscribe\nsubscribe\nbcast say \"hi\" { }"))
    (is (r2 :ok) (string "应成功：" (if (r2 :ok) "" (rb/error-msg (r2 :error)))))
    (is= 1 (length (last (r2 :stack))) "订阅后广播能到达")))

(deftest "REQ-51: onfail 让失败的流用替代回复收尾（本轮算完成）"
  (fn []
    (def env (new-ws))
    (def r (with-chat (fn [messages opts]
                        (fn [] (rb/raise (rb/exit-table :orchestration-base) "总是失败")))
                      (fn [] (run-in env (string "agent \"c\" { }\n"
                                                 "onfail [ \"回退回复\" ]\n"
                                                 "send say \"问\"")))))
    (is (r :ok) (string "有 onfail 时本轮应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (def a (last (ws-agents env)))
    (is= "回退回复" ((last (a :session)) :content))
    (is= 0 (length ((env :rb-ws) :round)))))

(deftest "REQ-51: 没有 onfail 时同一场景仍然失败"
  (fn []
    (def env (new-ws))
    (run-in env "agent \"c\" { }")
    (def r (with-chat (fn [messages opts]
                        (fn [] (rb/raise (rb/exit-table :orchestration-base) "总是失败")))
                      (fn [] (run-in env "send say \"问\""))))
    (is= 60 (if (r :ok) 0 (rb/error-code (r :error))))))

(deftest "REQ-48: 默认工具（D-61）经模型工具循环改文件"
  (fn []
    (def env (new-ws))
    (def dir (do (protect (os/mkdir "build/tmp")) "build/tmp"))
    (def p (string dir "/req48-default-tool.txt"))
    (spit p "旧内容")
    (os/setenv "RB_MOCK_TOOL"
               (string "edit:{\"path\":\"" p "\",\"old\":\"旧\",\"new\":\"新\"}"))
    (def r (run-in env (string "agent \"c\" { }\n"
                               "send say \"把文件里的旧改成新\"\n"
                               "drain")))
    (os/setenv "RB_MOCK_TOOL" nil)
    (is (r :ok) (if (r :ok) "" (rb/error-msg (r :error))))
    (is= "新内容" (string (slurp p)) "模型发起的 edit 真的改了文件")
    (def a (last (ws-agents env)))
    (is (string/find "已改 1 处" (((a :session) 2) :content)) "工具结果回到会话")
    (protect (os/rm p))))
