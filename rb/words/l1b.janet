# rb/words/l1b.janet —— L1b 布尔 / 比较 / 算术
#
# 操作数次序沿用 `- 5 3` 读作「5 减 3」的约定：a = 栈顶 = 书写序最左实参。
# （比较运算的次序见 docs/DECISIONS.md D-04，CHK-1 裁决）

(defn rb/eq [] (def a (rb/pop)) (def b (rb/pop)) (rb/push (= a b)))
(defn rb/ne [] (def a (rb/pop)) (def b (rb/pop)) (rb/push (not= a b)))
(defn rb/lt [] (def a (rb/pop)) (def b (rb/pop)) (rb/push (< a b)))
(defn rb/gt [] (def a (rb/pop)) (def b (rb/pop)) (rb/push (> a b)))
(defn rb/le [] (def a (rb/pop)) (def b (rb/pop)) (rb/push (<= a b)))
(defn rb/ge [] (def a (rb/pop)) (def b (rb/pop)) (rb/push (>= a b)))

(defn rb/not [] (rb/push (not (rb/pop))))

(defn rb/and
  []
  (def a (rb/pop))
  (def b (rb/pop))
  (rb/push (and a b)))

(defn rb/or
  []
  (def a (rb/pop))
  (def b (rb/pop))
  (rb/push (or a b)))

(defn rb/add [] (def a (rb/pop)) (def b (rb/pop)) (rb/push (+ a b)))
(defn rb/sub [] (def a (rb/pop)) (def b (rb/pop)) (rb/push (- a b)))
(defn rb/mul [] (def a (rb/pop)) (def b (rb/pop)) (rb/push (* a b)))
(defn rb/div [] (def a (rb/pop)) (def b (rb/pop)) (rb/push (/ a b)))
(defn rb/mod [] (def a (rb/pop)) (def b (rb/pop)) (rb/push (mod a b)))
(defn rb/abs [] (rb/push (math/abs (rb/pop))))

(defn rb/min [] (def a (rb/pop)) (def b (rb/pop)) (rb/push (min a b)))
(defn rb/max [] (def a (rb/pop)) (def b (rb/pop)) (rb/push (max a b)))

(defn rb/sum
  "seq -- n"
  []
  (def s (rb/pop))
  (rb/push (reduce + 0 s)))
