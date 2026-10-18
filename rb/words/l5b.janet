# rb/words/l5b.janet —— L5b 错误 / 调试 / 环境

(defn rb/fail
  "msg -- ；抛出运行时错误（退出码 33）。"
  []
  (rb/raise (rb/exit-table :runtime-fail) (string (rb/pop))))

(defn rb/assert
  "cond msg -- ；cond 为假则失败。"
  []
  (def c (rb/pop))
  (def m (rb/pop))
  (when (not c)
    (rb/raise (rb/exit-table :runtime-fail) (string "断言失败：" m))))

(defn rb/now
  "-- 秒"
  []
  (rb/push (os/time)))

(defn rb/env
  "name -- String|nil"
  []
  (rb/push (os/getenv (rb/pop))))
