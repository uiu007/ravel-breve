# rb/words/l1c.janet —— L1c 字符串工具（附录 A）
#
# 记法：左 = 栈顶 = 先被消费。

(defn rb/trim
  "String -- String"
  []
  (rb/push (string/trim (rb/pop))))

(defn rb/replace
  "from to String -- String"
  []
  (def from (rb/pop))
  (def to (rb/pop))
  (def s (rb/pop))
  (rb/push (string/replace-all from to s)))

(defn rb/contains
  "needle String -- bool"
  []
  (def needle (rb/pop))
  (def s (rb/pop))
  (rb/push (not (nil? (string/find needle s)))))

(defn rb/starts-with
  "prefix String -- bool"
  []
  (def p (rb/pop))
  (def s (rb/pop))
  (rb/push (string/has-prefix? p s)))

(defn rb/ends-with
  "suffix String -- bool"
  []
  (def p (rb/pop))
  (def s (rb/pop))
  (rb/push (string/has-suffix? p s)))

(defn rb/lines
  "String -- seq；按换行拆分"
  []
  (rb/push (string/split "\n" (rb/pop))))

(defn rb/words
  "String -- seq；按空白拆分（连续空白折叠，首尾空白忽略）"
  []
  (def s (rb/pop))
  (def flat (string/replace-all "\n" " "
                               (string/replace-all "\r" " "
                                                   (string/replace-all "\t" " " s))))
  (rb/push (filter (fn [w] (> (length w) 0)) (string/split " " flat))))
