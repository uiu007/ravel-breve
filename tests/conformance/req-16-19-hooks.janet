# tests/conformance/req-16-19-hooks.janet —— REQ-16/17/19：@on / @off 与事件集

(deftest "REQ-17: 事件名是 @ 前缀的字面记号，压栈即值"
  (fn []
    (is= "@Chunk" (eval-top "@Chunk"))
    (is= "@RoundDone" (eval-top "@RoundDone"))
    (each ev rb/event-names
      (is= ev (eval-top ev) (string ev " 应当可作字面量")))))

(deftest "REQ-17: 拼错的事件名在转译期就报未知词（20）"
  (fn []
    (is= 20 (eval-exit "@on @Chnuk [ 1 ]"))))

(deftest "REQ-16: @on 注册的钩子能拿到载荷（第一个操作数在栈顶）"
  (fn []
    # 钩子体 `fail` 会弹出栈顶并把它当错误消息抛出（33）——
    # 能抛出来就证明载荷确实压上了栈。
    (is= 33 (eval-exit "@on @Chunk [ fail ]\nagent \"c\" { }\nsend say \"x\"\ndrain"))))

(deftest "REQ-16: @on 注册后可查询，@off 不给引号 = 清空"
  (fn []
    (def env (new-ws))
    (run-in env "@on @Chunk [ 1 ]")
    (is= 1 (hook-count-in env "@Chunk"))
    (run-in env "@on @Chunk [ 2 ]")
    (is= 2 (hook-count-in env "@Chunk"))
    (run-in env "@off @Chunk")
    (is= 0 (hook-count-in env "@Chunk"))))

(deftest "REQ-19: @off @RoundDone 关掉默认收尾钩子 → 会话不再自动增长"
  (fn []
    (def env (new-ws))
    (def r (run-in env (string
                         "agent \"c\" { }\n"
                         "@off @RoundDone\n"
                         "dup\n"
                         "send say \"问\"\n"
                         "drain\n"
                         "pop\n"
                         "session")))
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (def sess (last (r :stack)))
    (is= 1 (length sess) "只该有用户那条；助手回复没被自动合并")
    (is= "user" ((sess 0) :role))))

(deftest "REQ-19 + REQ-46: 手动路径与自动路径结果一致"
  (fn []
    # 自动：默认收尾钩子做 ① 绑定 → ② Stream → Utter → ③ append → ④ 退订
    (def auto-env (new-ws))
    (run-in auto-env "agent \"c\" { }\ndup\nsend say \"问\"")
    (def auto-a (last (ws-agents auto-env)))

    # 手动：@off 之后自己 utter + append
    (def man-env (new-ws))
    (run-in man-env (string
                      "agent \"c\" { }\n"
                      "@off @RoundDone\n"
                      "dup\n"
                      "send say \"问\"\n"
                      "utter\n"
                      "append"))
    (def man-a (last (ws-agents man-env)))

    (is= (tup (map (fn [u] (u :content)) (auto-a :session)))
         (tup (map (fn [u] (u :content)) (man-a :session)))
         "手动 utter + append 应与钩子等价")
    (is= (tup (map (fn [u] (u :role)) (auto-a :session)))
         (tup (map (fn [u] (u :role)) (man-a :session)))
         "角色序列也应一致")))

(deftest "REQ-16: 默认收尾钩子可以被再次注册而叠加（不清空）"
  (fn []
    (def env (new-ws))
    (run-in env "@on @RoundDone [ 1 ]")
    (is= 2 (hook-count-in env "@RoundDone") "默认钩子 + 用户钩子")))
