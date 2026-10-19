# rb/words/l1d.janet —— L1d 类型转换（附录 A）

(defn rb/to-string
  "x -- String；nil → 空串；Utter → content；错误值 → 消息；其余走宿主 string"
  []
  (def x (rb/pop))
  (rb/push (cond
             (nil? x) ""
             (and (table? x) (string? (get x :rb-msg))) (get x :rb-msg)
             (and (table? x) (string? (get x :content))) (get x :content)
             (string x))))

(defn rb/to-int
  "String|num -- n；失败为运行时类型错误（31）"
  []
  (def x (rb/pop))
  (cond
    (number? x) (rb/push (math/floor x))
    (string? x) (do
                  (def n (scan-number (string/trim x)))
                  (if (nil? n)
                    (rb/raise (rb/exit-table :runtime-type)
                              (string "to-int 无法解析：" x))
                    (rb/push (math/floor n))))
    (rb/raise (rb/exit-table :runtime-type)
              (string "to-int 需要字符串或数字，得到 " (type x)))))
