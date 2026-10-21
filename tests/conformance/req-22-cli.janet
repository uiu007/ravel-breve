# tests/conformance/req-22-cli.janet —— REQ-22 CLI 形态与结果输出
#
# REQ-22 的四种形态（REPL / -e / 脚本 / --serve）由 tests/e2e/cli.sh 跑真进程验收；
# 这里验收**结果 → 输出**这一层的可测部分：
#   ① 结果消息的形状（协议 v1，附录 F）
#   ② `--json` 输出就是那条消息的 JSON 行（REQ-22「输出 JSON」）
#   ③ 退出码透传（REQ-23：失败仍给分级码，而不是 0）

(deftest "REQ-22：成功结果消息形状（type/ok/stack）"
  (fn []
    (def r (rb/run-source "+ 1 2" "test"))
    (def m (rb/cli-result-msg r))
    (is= "result" (m :type))
    (is= true (m :ok))
    (is= @["3"] (m :stack) "栈元素是**已渲染文本**（附录 F）")
    (is= nil (m :id) "没有 id 就不带 id 字段")))

(deftest "REQ-22：失败结果消息形状（type/ok/code/error）"
  (fn []
    (def r (try (rb/run-source "nope" "test") ([e] {:ok false :error e :stack @[]})))
    (def m (rb/cli-result-msg r))
    (is= "result" (m :type))
    (is= false (m :ok))
    (is= 20 (m :code))
    (is (string? (m :error)))))

(deftest "REQ-22：id 原样回显（REQ-24 请求/响应配对）"
  (fn []
    (def r (rb/run-source "1" "test"))
    (is= 7 ((rb/cli-result-msg r 7) :id))
    (is= "abc" ((rb/cli-result-msg r "abc") :id))))

(deftest "REQ-22：--json 输出是一条 JSON 行"
  (fn []
    (def line (rb/cli-encode (rb/cli-result-msg (rb/run-source "1" "test"))))
    (is (string? line))
    (is (string/has-prefix? "{" line))
    (def back ((rb/cap-get :json/decode) line))
    (is= "result" (get back "type"))
    (is= true (get back "ok"))))

(deftest "REQ-22：REPL 的栈跨行保留（同 -e 的一次会话）"
  (fn []
    (def env (rb/new-env))
    (is= [1] (eval-stack-in env "1"))
    (is= [1 2] (eval-stack-in env "2") "第二行看到第一行留下的 1")))

(deftest "REQ-22：REPL 出错不退出（错误只报不中断）"
  (fn []
    (def env (rb/new-env))
    (def bad (run-in env "nope"))
    (is= false (bad :ok))
    (is= [7] (eval-stack-in env "7") "出错之后同一工作区还能继续用")))

(deftest "REQ-22：-v 有版本串、help 有用法（都不是方言词）"
  (fn []
    (is (string? rb/version-string))
    (is (> (length rb/version-string) 0))
    (each w ["quit" "exit" "help" "clear"]
      (is= 20 (eval-exit w) (string w " 在代码里应报 20（REQ-25）")))))
