# rb/words/l1.janet —— L1 序列 / 文本与连接（多态）
#
# REQ-10：Session 复用 L1 多态序列词，不另设会话编辑词；一律纯函数，返回新值。
# 附录 A 记法：左 = 栈顶 = 先被消费。

(defn rb/-slice
  "对 String / 序列 的统一切片（负索引由调用方归一）。"
  [s start end]
  (if (string? s) (string/slice s start end) (slice s start end)))

(defn rb/len
  "seq -- n"
  []
  (rb/push (length (rb/pop))))

(defn rb/take
  "N seq -- seq；N ∈ Z 四象限（正=前 N，负=后 |N|）。"
  []
  (def n (rb/pop))
  (def s (rb/pop))
  (def l (length s))
  (def r (if (>= n 0)
           (rb/-slice s 0 (min n l))
           (rb/-slice s (max 0 (+ l n)) l)))
  (rb/push r))

(defn rb/drop
  "N seq -- seq；N ∈ Z 四象限（正=去前 N，负=去后 |N|）。"
  []
  (def n (rb/pop))
  (def s (rb/pop))
  (def l (length s))
  (def r (if (>= n 0)
           (rb/-slice s (min n l) l)
           (rb/-slice s 0 (max 0 (+ l n)))))
  (rb/push r))

(defn rb/first
  "seq -- seq；= take 1 糖"
  []
  (rb/push 1)
  (rb/take))

(defn rb/last
  "seq -- seq；= take -1 糖"
  []
  (rb/push -1)
  (rb/take))

(defn rb/reverse
  "seq -- seq"
  []
  (def s (rb/pop))
  (rb/push (if (string? s)
             (string/reverse s)
             (reverse (if (tuple? s) (array ;s) s)))))

(defn rb/at
  "n seq -- x；n 可为负（自尾部计）"
  []
  (def n (rb/pop))
  (def s (rb/pop))
  (def i (if (< n 0) (+ (length s) n) n))
  (rb/push (get s i)))

(defn rb/show
  "x -- ；list 逐元素打印（REQ-28），其余整体打印。"
  []
  (def x (rb/pop))
  (if (or (array? x) (tuple? x))
    (each e x (print (rb/render e)))
    (print (rb/render x))))
