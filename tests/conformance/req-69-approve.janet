# tests/conformance/req-69-approve.janet —— REQ-69 临时授权与审批
#
# 现象（用户实测）：模型要读 `~/project/shader-learning/README.md`，沙箱根是 cwd，
# 于是 `read` 报「沙箱拒绝」→ 60 → 整轮 `@RoundDone 失败`。用户的判词：
# 「这种终止应该加入临时审批机制」。
#
# REQ-69 的四条：
#   ① 策略拒绝带**请求表**（`:rb-denied` + `:rb-request`），不就地变成 60；
#   ② 模型发起的调用遇到它先发 `@Approve`（载荷 `Request Stream`），钩子填 `:decision`
#      与 `:grant`；允许 → 登记**临时**授权 → 重试一次；拒绝 → 60（消息点名怎么预先授权）；
#   ③ 授权是临时的：`uses` 有限或到本工作区结束；`grant` / `grants` / `ungrant` 三个词
#      让脚本 / CI 不必等人；
#   ④ 非交互（管道 / `--serve` / 测试）**不能**审批：默认钩子拒绝并说明预先授权的两条路；
#      `@off @Approve` 之后回到 v1.0o 的行为（直接 60）。

(deftest "REQ-69：@Approve 是第 9 个事件，缺省钩子里就有它"
  (fn []
    (def env (new-ws))
    (is= 9 (length rb/event-names))
    (is (rb/event? "@Approve"))
    (is= 1 (length (get (ws-hooks env) "@Approve")) "缺省工作区装了默认审批钩子")
    (is= 3 (length (keys (ws-hooks env))) "@RoundDone / @Toolcall / @Approve 三个缺省钩子")))

(deftest "REQ-69：沙箱拒绝带请求表（kind / path / dir / root）"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_SANDBOX" nil)
    (def r (val-in env (fn [] (protect (cap/fs-check "/tmp/rb-req-69-no.txt")))))
    (is (not (get r 0)) "根外 → 拒绝")
    (def e (get r 1))
    (is (true? (get e :rb-denied)) "带 :rb-denied 标记")
    (def req (get e :rb-request))
    (is (table? req) "带请求表")
    (is= "fs" (req :kind))
    (is= "/tmp/rb-req-69-no.txt" (req :path))
    (is= "/tmp" (req :dir) "请人点头的最小单位是目录")
    (is (not (nil? (req :root))) "请求里写明沙箱根，好让人看懂")))

(deftest "REQ-69：授权覆盖按目录段对齐，且用完即销"
  (fn []
    (def env (new-ws))
    (def g0 (val-in env (fn [] (rb/grant-add! "fs" "/tmp/rb-x" nil))))
    (is= "/tmp/rb-x" (g0 :key))
    (def inside (val-in env (fn [] (rb/grant-find "fs" "/tmp/rb-x/a.txt"))))
    (is (not (nil? inside)) "目录之下算覆盖")
    (is (nil? (val-in env (fn [] (rb/grant-find "fs" "/tmp/rb-x2/a.txt"))))
        "`/tmp/rb-x` 不覆盖 `/tmp/rb-x2`（按段对齐）")
    # uses = 1：查不扣（一次工具调用会查好几遍），**扣**在重试收尾
    (val-in env (fn [] (rb/grant-add! "fs" "/tmp/rb-once" 1)))
    (is (not (nil? (val-in env (fn [] (rb/grant-find "fs" "/tmp/rb-once/a.txt"))))) "第一次命中")
    (is (not (nil? (val-in env (fn [] (rb/grant-find "fs" "/tmp/rb-once/a.txt"))))) "再查还在（查不扣）")
    (is= 1 (val-in env (fn [] (rb/grant-consume! "fs" "/tmp/rb-once"))) "扣一次")
    (is (nil? (val-in env (fn [] (rb/grant-find "fs" "/tmp/rb-once/a.txt")))) "扣完就没了")
    (is= 0 (val-in env (fn [] (rb/grant-consume! "fs" "/tmp/rb-words"))) "不存在的授权扣 0 次")
    (is= 1 (val-in env (fn [] (rb/grant-clear!))) "撤销返回条数")
    (is (empty? (val-in env (fn [] (rb/grants-of)))) "撤销后空")))

(deftest "REQ-69：授权的效果 —— 越界检查放行"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_SANDBOX" nil)
    (val-in env (fn [] (rb/grant-add! "fs" "/tmp" nil)))
    (def r (val-in env (fn [] (protect (cap/fs-check "/tmp/rb-req-69-ok.txt")))))
    (is (get r 0) (string "授权过的越界应放行：" (if (get r 0) "" (rb/error-msg (get r 1)))))
    (is= "/tmp/rb-req-69-ok.txt" (get r 1))))

(deftest "REQ-69：非交互 → 默认审批钩子拒绝，并点名预先授权的两条路"
  (fn []
    (def env (new-ws))
    (is (not (val-in env (fn [] (rb/approve-tty?)))) "测试环境没有终端")
    (def req @{:kind "fs" :path "/tmp/rb-no.txt" :dir "/tmp" :root "/x" :tool "read"})
    (val-in env (fn [] (rb/emit "@Approve" [req])))
    (is= :deny (req :decision))
    (is (string/find "非交互" (req :msg)) "消息说明非交互")
    (is (string/find "grant" (req :msg)) "消息给出 grant 的写法")
    (is (string/find "RB_SANDBOX" (req :msg)) "消息给出 RB_SANDBOX 这条退路")))

(deftest "REQ-69：模型发起 → 默认拒绝（60）；自定义钩子 accept-dir → 本轮成功"
  (fn []
    (def p "/tmp/rb-req-69-tool.txt")
    (spit p "hello\n")
    (os/setenv "RB_SANDBOX" nil)
    # ① 默认审批钩子：非交互 → 拒绝 → 60
    (def env1 (new-ws))
    (os/setenv "RB_MOCK_TOOL" (string "read:{\"path\": \"" p "\"}"))
    (def r1 (run-in env1 (string "agent \"c\" { }\nsend say \"读\"\ndrain")))
    (is (not (r1 :ok)) "拒绝时本轮失败（60）")
    (is (string/find "非交互" (rb/error-msg (r1 :error))) "错误消息来自审批")
    # ② 换掉默认钩子：accept-dir 自动批准
    (def env2 (new-ws))
    (def r2 (run-in env2 (string "@off @Approve\n"
                                 "@on @Approve [ accept-dir ]\n"
                                 "agent \"c\" { }\nsend say \"读\"\ndrain")))
    (os/setenv "RB_MOCK_TOOL" nil)
    (is (r2 :ok) (string "自动批准后应成功：" (if (r2 :ok) "" (rb/error-msg (r2 :error)))))
    (def a (last (ws-agents env2)))
    (def tm (get (a :session) 2))
    (is= "tool" (tm :role) "工具结果照常回给模型")
    (is (string/find "hello" (tm :content)) "读到的是真内容")
    (is= "/tmp" (get (get (val-in env2 (fn [] (rb/grants-of))) 0) :key)
        "留下一条目录授权")
    (os/rm p)))

(deftest "REQ-69：`accept` 只放一次 —— 重试收尾就扣掉，不留尾巴"
  (fn []
    (def p "/tmp/rb-req-69-once.txt")
    (spit p "hi\n")
    (os/setenv "RB_SANDBOX" nil)
    (def env (new-ws))
    (os/setenv "RB_MOCK_TOOL" (string "read:{\"path\": \"" p "\"}"))
    (def r (run-in env (string "@off @Approve\n"
                               "@on @Approve [ accept ]\n"
                               "agent \"c\" { }\nsend say \"读\"\ndrain")))
    (os/setenv "RB_MOCK_TOOL" nil)
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (is (empty? (val-in env (fn [] (rb/grants-of)))) "uses = 1 的授权在重试后被扣掉")
    (os/rm p)))

(deftest "REQ-69：脚本里的 invoke 不走审批（没人替程序员点头）"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_SANDBOX" nil)
    (def before (val-in env (fn [] (length (rb/stack)))))
    (def r (run-in env (string "invoke \"read\" H{ \"path\" \"/tmp/rb-req-69-invoke.txt\" }")))
    (is (not (r :ok)) "仍然是失败")
    (is= 60 (rb/error-code (r :error)) "仍然是 60")
    (is (empty? (val-in env (fn [] (rb/grants-of)))) "没有产生授权")
    (is= before (val-in env (fn [] (length (rb/stack)))))))

(deftest "REQ-69：@off @Approve 之后拒绝（回到 v1.0o 的行为）"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_SANDBOX" nil)
    (os/setenv "RB_MOCK_TOOL" "read:{\"path\": \"/tmp/rb-req-69-off.txt\"}")
    (def r (run-in env (string "@off @Approve\nagent \"c\" { }\nsend say \"读\"\ndrain")))
    (os/setenv "RB_MOCK_TOOL" nil)
    (is (not (r :ok)))
    (is (string/find "沙箱拒绝" (rb/error-msg (r :error))) "原样报沙箱拒绝")))

(deftest "REQ-69：三个授权词 —— grant / grants / ungrant"
  (fn []
    (def env (new-ws))
    (is (string/find "已授权"
                     (eval-top-in env (string "grant \"fs\" \"/tmp/rb-words\""))))
    (is= "/tmp/rb-words" (get (get (eval-top-in env "grants") 0) :key))
    (is= 1 (eval-top-in env "ungrant"))
    (is (empty? (eval-top-in env "grants")))
    (is= 31 (run-in-exit env "grant 1 2") "非字符串 → 31")))
