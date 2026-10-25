# tests/conformance/req-68-tool-args.janet —— REQ-68 工具的参数模式、别名与「手误回给模型」
#
# 现象（用户实测，OpenCode / DeepSeek）：模型把 `shell` 的参数写成 `command` 而不是 `cmd`，
# 工具报「缺少参数 cmd」，**整轮以 60 收场**——一次参数名的手误报废一次会话回合。
#
# REQ-68 的三条：
#   ① 请求里公示的 `parameters` 必须是**具体 schema**（properties + required），
#      空壳 `additionalProperties: true` 等于让模型猜参数名；
#   ② 参数有**别名**（`command` = `cmd`、`file_path` = `path` …），只做「认」，不做语义变换；
#   ③ 模型发起的调用出错时，**参数错误**（缺参数 / 参数名不对 / 工具名写错）作为
#      `role: "tool"` 的结果回给模型，回合继续；**环境侧失败**（沙箱、执行失败）仍是 60。
#      脚本里的 `invoke` 不走这条——没人替程序员改参数，所以照旧 60。

(deftest "REQ-68：公示的工具都带具体的 parameters（properties + required）"
  (fn []
    (def env (new-ws))
    (def defs (val-in env rb/tool-defs))
    (is (>= (length defs) 6) "默认工具包至少有六个")
    (each d defs
      (def f (d :function))
      (def p (f :parameters))
      (def name (f :name))
      (is (table? p) (string name "：parameters 是表"))
      (is= "object" (p :type))
      (is (table? (p :properties)) (string name "：有 properties"))
      (is (> (length (keys (p :properties))) 0) (string name "：properties 非空"))
      (is (or (tuple? (p :required)) (array? (p :required)))
          (string name "：required 是序列"))
      (each r (p :required)
        (is (not (nil? (get (p :properties) r)))
            (string name "：required 的 " r " 在 properties 里")))
      (is (not (get p :additionalProperties)) (string name "：不再是空壳")))))

(deftest "REQ-68：别名表 —— 规范名与别名指同一件事"
  (fn []
    (def env (new-ws))
    (def read-arg (fn [args k] (val-in env (fn [] (cap/tool-arg args k)))))
    (is= "echo hi" (read-arg @{"cmd" "echo hi"} "cmd"))
    (is= "echo hi" (read-arg @{"command" "echo hi"} "cmd") "command → cmd")
    (is= "echo hi" (read-arg @{"shell_command" "echo hi"} "cmd"))
    (is= "a.md" (read-arg @{"file_path" "a.md"} "path") "file_path → path")
    (is= "a.md" (read-arg @{"filename" "a.md"} "path"))
    (is= "旧" (read-arg @{"old_string" "旧"} "old"))
    (is= "新" (read-arg @{"new_text" "新"} "new"))
    (is= "x" (read-arg @{"query" "x"} "pattern"))
    (is (nil? (read-arg @{"nope" "x"} "cmd")) "不认识的键仍然不认")
    (is= (tup ["cmd" "command" "shell_command"]) (tup (cap/tool-arg-names "cmd"))
         "错误信息里的「接受：」列的就是这张表")))

(deftest "REQ-68：模型把 cmd 写成 command —— 别名认下，回合照常成功"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_MOCK_TOOL" "shell:{\"command\": \"echo hi\"}")
    (def r (run-in env (string "agent \"c\" { }\n"
                               "send say \"跑一下\"\n"
                               "drain")))
    (os/setenv "RB_MOCK_TOOL" nil)
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (def a (last (ws-agents env)))
    (def tool-msg ((a :session) 2))
    (is= "tool" (tool-msg :role))
    (is (string/find "hi" (tool-msg :content)) "shell 真的跑了（结果进了会话）")))

(deftest "REQ-68：参数名彻底写错 —— 错误回给模型，本轮不作废"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_MOCK_TOOL" "read:{\"pth\": \"README.md\"}")
    (def r (run-in env (string "agent \"c\" { }\n"
                               "send say \"读一下\"\n"
                               "drain")))
    (os/setenv "RB_MOCK_TOOL" nil)
    (is (r :ok) "参数错误不再让整轮失败（旧行为：60）")
    (def a (last (ws-agents env)))
    (def tool-msg ((a :session) 2))
    (is= "tool" (tool-msg :role) "错误以 role=tool 回给模型")
    (is (string/find "缺少参数 path" (tool-msg :content)) "说清缺哪个")
    (is (string/find "接受：" (tool-msg :content)) "并列可接受的键")
    (is (string/find "file_path" (tool-msg :content)) "别名也在里面")))

(deftest "REQ-68：工具名写错也是手误 —— 回给模型，不是 60"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_MOCK_TOOL" "shel:{\"cmd\": \"echo hi\"}")
    (def r (run-in env (string "agent \"c\" { }\n"
                               "send say \"跑\"\n"
                               "drain")))
    (os/setenv "RB_MOCK_TOOL" nil)
    (is (r :ok) "未知工具名不再让整轮失败")
    (def a (last (ws-agents env)))
    (is (string/find "未注册的工具"
                     (((a :session) 2) :content)))))

(deftest "REQ-68：脚本里的 invoke 不走这条 —— 参数错误仍是 60（没人替程序员改）"
  (fn []
    (def env (new-ws))
    (def r (run-in env "invoke \"read\" H{ \"pth\" \"README.md\" }"))
    (is (not (r :ok)) "invoke 照旧失败")
    (is= 60 (rb/error-code (r :error)) "编排级错误码")
    (is (string/find "接受：" (rb/error-msg (r :error))) "错误里写清可接受的键")))

(deftest "REQ-68：环境侧失败仍然是 60（策略不变）"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_SANDBOX" "/tmp")
    (def r (run-in env "invoke \"read\" H{ \"path\" \"README.md\" }"))
    (os/setenv "RB_SANDBOX" nil)
    (is (not (r :ok)) "沙箱越界不给过")
    (is= 60 (rb/error-code (r :error)) "工具失败一律编排级（REQ-48）
      ——REQ-68 只放行「参数错误」，执行的失败照样 60")))

(deftest "REQ-68：别名只属于内置工具 —— 用户工具的契约不变"
  (fn []
    (def env (new-ws))
    (def r (run-in env (string "deftool \"add2\" \"加 2\" [ at \"a\"\n+ 2 ]\n"
                               "invoke \"add2\" H{ \"b\" 1 }")))
    (is (not (r :ok)) "`deftool` 的体自己 `at`，别名管不到它")
    (is= 60 (rb/error-code (r :error)) "仍是编排级")
    (is (string/find "add2" (rb/error-msg (r :error))) "错误点名是哪个工具")))
