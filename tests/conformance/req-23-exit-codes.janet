# tests/conformance/req-23-exit-codes.janet —— REQ-23 退出码分级

(deftest "REQ-23：成功为 0"
  (fn []
    (is= 0 (eval-exit "1 2"))))

(deftest "REQ-23：词法级 10–19"
  (fn []
    (is= 10 (eval-exit "\"abc"))
    (is= 11 (eval-exit "c23a : [ 1 2"))
    (is= 12 (eval-exit "\"a\\qb\""))))

(deftest "REQ-23：语法级 20–29"
  (fn []
    (is= 20 (eval-exit "nope"))
    (is= 21 (eval-exit "]"))))

(deftest "REQ-23：运行时级 30–39"
  (fn []
    (is= 30 (eval-exit "pop"))
    (is= 31 (eval-exit "apply 3"))
    (is= 33 (eval-exit "fail \"boom\""))))

(deftest "REQ-23：错误值都带 :rb-code（方言层自述）"
  (fn []
    (each [k v] (pairs rb/exit-table)
      (is (number? v) (string "退出码表项非数字：" k)))))

(deftest "REQ-23：宿主原生错误归入 31 类型（len 3）；30 只留给栈下溢（D-53）"
  (fn []
    (is= 31 (eval-exit "len 3"))
    (is= 30 (eval-exit "pop"))))

(deftest "REQ-23：方言层错误携带 :rb-code 与 :rb-msg"
  (fn []
    (def r (try (rb/run-source "nope" "t") ([e] {:error e})))
    (is (rb/rb-error? (r :error)))
    (is= 20 (rb/error-code (r :error)))
    (is (string? (rb/error-msg (r :error))))))
