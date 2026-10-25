# cap/fs.janet —— 能力层：文件读写（**不属于核心**，REQ-37 / 附录 D）
#
# 核心里的 L7 词（`read`/`write`/`save`/`load`/`compact`）只认识能力键：
#   :fs/read    path                  → String | nil（读不到则 nil）
#   :fs/write   text path             → 写入字节数
#   :fs/append  text path             → 追加字节数
#   :fs/size    path                  → 字节数 | nil
#   :fs/exists? path                  → 布尔
# 剔除本文件（make core-only）后核心仍可装载，L7 词报 60。

# ---- 沙箱（P0，D-60）-----------------------------------------------------
#
# 目的：模型（或一段 PTC 程序）不该能读写工作目录之外的东西。
#   RB_SANDBOX 未设   → 根 = 进程当前目录
#   RB_SANDBOX=<路径>  → 根 = 该路径
#   RB_SANDBOX=none|*  → 关闭（脚本里要跨目录时显式关掉）
# 判定在**规范化之后**做：存在的东西走 realpath（顺带解掉符号链接），
# 不存在的走「父目录 realpath + 基名」，所以 `sub/../../etc/passwd` 这类也会被拦。

(defn cap/fs-root
  []
  (def v (os/getenv "RB_SANDBOX"))
  (cond
    (nil? v) (os/cwd)
    (empty? v) (os/cwd)
    (or (= v "none") (= v "*")) nil
    true v))

(defn cap/fs-last-slash
  "最后一个 `/` 的下标（没有则 nil）。janet 1.42 没有 string/rfind，
  也没有 string/codepoint；按字节扫（`/` 是单字节 47，UTF-8 安全）。"
  [p]
  (var idx nil)
  (def b (string/bytes p))
  (loop [i :range [0 (length b)]]
    (when (= 47 (b i)) (set idx i)))
  idx)

(defn cap/fs-dirname
  [p]
  (def i (cap/fs-last-slash p))
  (cond
    (nil? i) "."
    (= i 0) "/"
    true (string/slice p 0 i)))

(defn cap/fs-basename
  [p]
  (def i (cap/fs-last-slash p))
  (if (nil? i) p (string/slice p (inc i))))

(defn cap/fs-abs
  [p]
  (if (string/has-prefix? "/" p) p (string (os/cwd) "/" p)))

(defn cap/fs-canon
  "尽量把路径规范化：存在的走 realpath；不存在的规范化父目录后拼基名。"
  [p]
  (def abs (cap/fs-abs p))
  (def r (protect (os/realpath abs)))
  (if (get r 0)
    (string (get r 1))
    (let [rp (protect (os/realpath (cap/fs-dirname abs)))]
      (if (get rp 0)
        (string (get rp 1) "/" (cap/fs-basename abs))
        abs))))

(defn cap/fs-check
  "沙箱检查：根外的路径直接报错（L7 的写词会把它归到 41）。"
  [path]
  (def root (cap/fs-root))
  (when root
    (def r (cap/fs-canon root))
    (def p (cap/fs-canon path))
    (def inside? (or (= p r)
                     (string/has-prefix? (string r "/") p)))
    (when (not inside?)
      (error (string "沙箱拒绝（根 = " r "）：" path
                     "；确需越界请设 RB_SANDBOX=none（D-60）"))))
  path)

(defn cap/fs-read
  [path]
  # 沙箱拒绝也归 40（读不到）：read 的契约是「失败 = nil」，不给调用方留两条失败路径
  (def p (protect (do (cap/fs-check path) (slurp path))))
  (if (get p 0) (string (get p 1)) nil))

(defn cap/fs-write
  [text path]
  (cap/fs-check path)
  (def p (protect (spit path text)))
  (when (not (get p 0))
    (error (string "写入失败：" path "（" (get p 1) "）")))
  (length text))

(defn cap/fs-append
  [text path]
  (cap/fs-check path)
  (def f (file/open path :a))
  (when (nil? f) (error (string "追加失败：" path)))
  (file/write f text)
  (file/close f)
  (length text))

(defn cap/fs-size
  [path]
  (cap/fs-check path)
  (def st (os/stat path))
  (if st (st :size) nil))

(defn cap/fs-exists?
  [path]
  (cap/fs-check path)
  (not (nil? (os/stat path))))

(rb/cap-put :fs/read cap/fs-read)
(rb/cap-put :fs/write cap/fs-write)
(rb/cap-put :fs/append cap/fs-append)
(rb/cap-put :fs/size cap/fs-size)
(rb/cap-put :fs/exists? cap/fs-exists?)
