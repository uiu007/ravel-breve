# tests/conformance/req-25-meta-commands.janet —— REQ-25 元命令（保留名表 + 分发）
#
# REQ-25：元命令是**无前缀裸词**，与代码的分界由编辑器 minibuffer 承担。
#         后端因此只需冻结一份保留名表；保留名**不是**方言词（在代码里出现即 20），
#         并且**不得**与词表重名（REQ-09：一个名字只有一种词性）。

(deftest "REQ-25：保留名表存在且非空"
  (fn []
    (is (array? rb/meta-commands))
    (is (> (length rb/meta-commands) 0))))

(deftest "REQ-25：元命令名在表中"
  (fn []
    (each w ["quit" "exit" "help" "clear"]
      (is (rb/meta-command? w) (string w " 应在保留名表中")))))

(deftest "REQ-25：非元命令名不在表中"
  (fn []
    (is (not (rb/meta-command? "map")))
    (is (not (rb/meta-command? "1")))
    (is (not (rb/meta-command? "")))))

(deftest "REQ-25：元命令是裸词，不带前缀"
  (fn []
    (each w rb/meta-commands
      (is (not (string/has-prefix? ":" w)) (string w " 不应带前缀"))
      (is (not (string/has-prefix? "@" w)) (string w " 不应带前缀")))))

(deftest "REQ-25：元命令名不是方言词（在代码里出现即 20）"
  (fn []
    (each w rb/meta-commands
      (is= 20 (eval-exit w) (string w " 在代码里应报 20")))))

(deftest "REQ-25：保留名不与词表重名（REQ-09）"
  (fn []
    # `watch`/`save`/`load` 是方言词（L9/L7），因此**不能**在保留名表里
    (each w ["watch" "save" "load" "current" "compact"]
      (is (not (rb/meta-command? w)) (string w " 是方言词，不能当元命令")))
    (each w rb/meta-commands
      (is (nil? (get rb/rename w)) (string w " 不在换名表里")))))

(deftest "REQ-25：clear 清栈但保留字典"
  (fn []
    (def env (rb/new-env))
    (eval-stack-in env "f : [ + 1 ]")
    (eval-stack-in env "1 2")
    (is= 2 (length (env :rb-stack)))
    (is= nil (rb/cli-meta "clear" env) "clear 不是退出命令")
    (is= 0 (length (env :rb-stack)))
    (is= 3 (eval-top-in env "f 2") "字典还在（REQ-20：字典是工作区的一部分）")))

(deftest "REQ-25：quit / exit 返回 0，help 只打印不退出"
  (fn []
    (def env (rb/new-env))
    (is= 0 (rb/cli-meta "quit" env))
    (is= 0 (rb/cli-meta "exit" env))
    (is= nil (rb/cli-meta "help" env))))
