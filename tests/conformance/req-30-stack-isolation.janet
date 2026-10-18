# tests/conformance/req-30-stack-isolation.janet —— REQ-30 fiber-local 数据栈

(deftest "REQ-30：两次独立求值互不污染"
  (fn []
    (def a (rb/run-source "1 2" "a"))
    (def b (rb/run-source "3 4" "b"))
    (is= [2 1] (tup (a :stack)))
    (is= [4 3] (tup (b :stack)))))

(deftest "REQ-30：交叉求值不串栈"
  (fn []
    (def a (rb/run-source "1" "a"))
    (rb/run-source "2" "b")
    (is= [1] (tup (a :stack)))))

(deftest "REQ-30：显式复用 env 时栈跨次保留（REPL 语义）"
  (fn []
    (def env (rb/new-env))
    (rb/run-source "1" "r" env)
    (def r (rb/run-source "2" "r" env))
    (is= [1 2] (tup (r :stack)))))

(deftest "REQ-30：env 原型链指向核心环境（词表可见）"
  (fn []
    (def env (rb/new-env))
    (is (not (nil? (rb/env-get "rb/take" env))))
    (is (not (nil? (rb/env-get "rb/take"))))))

(deftest "REQ-30：两个 env 的栈对象互不相同（不是共享全局）"
  (fn []
    (def a (rb/new-env))
    (def b (rb/new-env))
    (is (not= (a :rb-stack) (b :rb-stack)))))
