# tests/conformance/req-25-meta-commands.janet —— REQ-25 元命令（保留名表）
#
# REQ-25：元命令是**无前缀裸词**，与代码的分界由编辑器 minibuffer 承担。
#         因此后端只需冻结一份保留名表；元命令名不是方言词（在代码里出现即 20）。
#         完整分发（提示符 / 帮助 / 清屏）在 M5。

(deftest "REQ-25：保留名表存在且非空"
  (fn []
    (is (array? rb/meta-commands))
    (is (> (length rb/meta-commands) 0))))

(deftest "REQ-25：元命令名在表中"
  (fn []
    (each w ["quit" "exit" "help" "clear" "agents" "watch"]
      (is (rb/meta-command? w) (string w " 应在保留名表中")))))

(deftest "REQ-25：非元命令名不在表中"
  (fn []
    (is (not (rb/meta-command? "map")))
    (is (not (rb/meta-command? "1")))))

(deftest "REQ-25：元命令是裸词，不带前缀"
  (fn []
    (each w rb/meta-commands
      (is (not (string/has-prefix? ":" w)) (string w " 不应带前缀"))
      (is (not (string/has-prefix? "@" w)) (string w " 不应带前缀")))))

(deftest "REQ-25：元命令名不是方言词（在代码里出现即 20）"
  (fn []
    (is= 20 (eval-exit "quit"))
    (is= 20 (eval-exit "help"))))
