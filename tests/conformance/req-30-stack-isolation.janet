# tests/conformance/req-30-stack-isolation.janet —— REQ-30：工作区 = 字典 + 栈
#
# REQ-30（v1.0c）的定义：**工作区 = 字典绑定（函数与常量）+ 栈（变量）**。
# 因此“栈是临时空间”“并发求值需隔离栈”都不是本规格的约束：
#   栈就是工作区的变量空间；并发在流层（Stream ≡ fiber），不在求值层。
# 本文件验证实现手段：一个 env 携带一份栈；**复用 env = 同一个工作区**，
#   新 env = 新工作区。

(deftest "REQ-30：两个独立工作区互不影响"
  (fn []
    (def a (rb/run-source "1 2" "a"))
    (def b (rb/run-source "3 4" "b"))
    (is= [2 1] (tup (a :stack)))
    (is= [4 3] (tup (b :stack)))))

(deftest "REQ-30：一个工作区的求值互不影响另一个工作区"
  (fn []
    (def a (rb/run-source "1" "a"))
    (rb/run-source "2" "b")
    (is= [1] (tup (a :stack)))))

(deftest "REQ-30：复用 env = 同一个工作区，栈（变量）跨次保留"
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

(deftest "REQ-30：两个工作区的栈对象互不相同"
  (fn []
    (def a (rb/new-env))
    (def b (rb/new-env))
    (is (not= (a :rb-stack) (b :rb-stack)))))
