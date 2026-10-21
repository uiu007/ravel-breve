# rb/words/l1.janet —— L1 序列 / 文本与连接（多态）
#
# REQ-10：Session 复用 L1 多态序列词，不另设会话编辑词；一律纯函数，返回新值。
# REQ-11：`,` / `,,` = 多态 join；`take`/`drop` 支持 N ∈ Z 四象限。
# 附录 A 记法：左 = 栈顶 = 先被消费。
#
# 多态规则（一张表，见 docs/DECISIONS.md D-17）：
#   String  → 元素是单字符字符串，结果仍是 String
#   tuple   → 结果仍是 tuple
#   array   → 结果仍是 array（Session 就是 Utter 的 array，REQ-06）
#   其他    → 类型错误（31）

(defn rb/seq-kind
  "序列形态：:string / :tuple / :array；非序列返回 nil。"
  [s]
  (cond
    (string? s) :string
    (tuple? s) :tuple
    (array? s) :array
    nil))

(defn rb/seq-elems
  "把序列规范化为元素数组（String → 单字符字符串）。"
  [s]
  (if (string? s)
    (map (fn [b] (string/from-bytes b)) s)
    (array ;s)))

(defn rb/seq-build
  "按形态重建序列。"
  [kind xs]
  (case kind
    :string (string/join (map string xs) "")
    :tuple (tuple ;xs)
    :array (array ;xs)
    (array ;xs)))

(defn rb/seq-ensure
  "断言是序列，返回形态。"
  [word s]
  (def k (rb/seq-kind s))
  (when (nil? k)
    (rb/raise (rb/exit-table :runtime-type)
              (string word " 需要序列，得到 " (type s))))
  k)

(defn rb/-slice
  "对 String / 序列 的统一切片（保留形态：janet 的 slice 总返回 tuple）。"
  [s start end]
  (if (string? s)
    (string/slice s start end)
    (rb/seq-build (rb/seq-kind s) (slice (rb/seq-elems s) start end))))

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
  (rb/push (if (>= n 0)
             (rb/-slice s 0 (min n l))
             (rb/-slice s (max 0 (+ l n)) l))))

(defn rb/drop
  "N seq -- seq；N ∈ Z 四象限（正=去前 N，负=去后 |N|）。"
  []
  (def n (rb/pop))
  (def s (rb/pop))
  (def l (length s))
  (rb/push (if (>= n 0)
             (rb/-slice s (min n l) l)
             (rb/-slice s 0 (max 0 (+ l n))))))

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
  (def k (rb/seq-ensure "reverse" s))
  (if (string? s)
    (rb/push (string/reverse s))
    (rb/push (rb/seq-build k (reverse (rb/seq-elems s))))))

(defn rb/sort
  "seq -- seq"
  []
  (def s (rb/pop))
  (def k (rb/seq-ensure "sort" s))
  (rb/push (rb/seq-build k (sort (rb/seq-elems s)))))

(defn rb/at
  "n seq -- x；n 可为负（自尾部计）"
  []
  (def n (rb/pop))
  (def s (rb/pop))
  # 序列（string/tuple/array）要整数下标；表（table/struct）任意键，缺键 = nil（D-50）
  (def seq? (or (string? s) (array? s) (tuple? s) (buffer? s)))
  (when (and seq? (not (number? n)))
    (rb/raise (rb/exit-table :runtime-type)
              (string "at 需要整数下标，得到 " (type n) "（表才用键）")))
  (def i (if (< n 0) (+ (length s) n) n))
  (rb/push (if (string? s)
             (string/slice s i (inc i))
             (get s i))))

(defn rb/map
  "[q] seq -- seq；引号必须消费 1 个、产出 1 个（REQ-32）"
  []
  (def q (rb/pop))
  (def s (rb/pop))
  (def k (rb/seq-ensure "map" s))
  (rb/push (rb/seq-build k (map (fn [x] (rb/call1 q x)) (rb/seq-elems s)))))

(defn rb/filter
  "[q] seq -- seq；引号产出真值时保留元素"
  []
  (def q (rb/pop))
  (def s (rb/pop))
  (def k (rb/seq-ensure "filter" s))
  (rb/push (rb/seq-build k
                         (filter (fn [x] (truthy? (rb/call1 q x)))
                                 (rb/seq-elems s)))))

(defn rb/fold
  "[q] init seq -- x；引号形如 `q acc x`（acc 在栈顶）"
  []
  (def q (rb/pop))
  (def init (rb/pop))
  (def s (rb/pop))
  (rb/seq-ensure "fold" s)
  (var acc init)
  (each x (rb/seq-elems s)
    (set acc (rb/call2 q acc x)))
  (rb/push acc))

(defn rb/join-any
  "多态连接（REQ-11）：String+String → String；序列+序列 → 左侧形态；其余 → array。"
  [x y]
  (def kx (rb/seq-kind x))
  (def ky (rb/seq-kind y))
  (cond
    (and (= kx :string) (= ky :string)) (string x y)
    (and kx ky) (rb/seq-build kx (array/concat @[] (rb/seq-elems x) (rb/seq-elems y)))
    (array x y)))

(defn rb/join2
  "X Y -- XY"
  []
  (def x (rb/pop))
  (def y (rb/pop))
  (rb/push (rb/join-any x y)))

(defn rb/join3
  "X Y Z -- XYZ"
  []
  (def x (rb/pop))
  (def y (rb/pop))
  (def z (rb/pop))
  (rb/push (rb/join-any (rb/join-any x y) z)))

(defn rb/split
  "sep String -- seq；按显式分隔符拆分（空段保留）"
  []
  (def sep (rb/pop))
  (def s (rb/pop))
  (rb/push (string/split sep s)))

(defn rb/zip
  "a b -- pairs；长度取短，元素为二元 tuple"
  []
  (def a (rb/pop))
  (def b (rb/pop))
  (def ea (rb/seq-elems a))
  (def eb (rb/seq-elems b))
  (def n (min (length ea) (length eb)))
  (def out @[])
  (for i 0 n (array/push out (tuple (ea i) (eb i))))
  (rb/push out))

(defn rb/show
  "x -- ；list 逐元素打印（REQ-28），其余整体打印。"
  []
  (def x (rb/pop))
  (if (or (array? x) (tuple? x))
    (each e x (print (rb/render e)))
    (print (rb/render x))))

(defn rb/wait
  "n -- ；等待 n 秒（可为小数）"
  []
  (ev/sleep (rb/pop)))

(defn rb/log
  "x -- ；写 stderr（stdout 只承载协议，REQ-43）"
  []
  (eprint (rb/render (rb/pop)))
  (eprint "\n"))

(defn rb/retry
  "[q] n -- ...；书写序 `retry [ 体 ] n`，镜像后**引号在栈顶**。
  执行 q，失败则回滚栈并重试，至多 n 次。"
  []
  (def q (rb/pop))
  (def n (rb/pop))
  (when (not (function? q))
    (rb/raise (rb/exit-table :runtime-type)
              (string "retry 的第一个实参应是引号，得到 " (type q))))
  (when (not (number? n))
    (rb/raise (rb/exit-table :runtime-type)
              (string "retry 的第二个实参应是次数，得到 " (type n))))
  (def d0 (length (rb/stack)))
  (var i 0)
  (var ok false)
  (var err nil)
  (while (and (not ok) (<= i n))
    (def r (protect (q)))
    (if (get r 0)
      (set ok true)
      (do
        (set err (get r 1))
        (rb/stack-truncate d0)
        (++ i))))
  (when (not ok) (error err))
  nil)
