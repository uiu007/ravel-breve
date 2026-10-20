# cap/fs.janet —— 能力层：文件读写（**不属于核心**，REQ-37 / 附录 D）
#
# 核心里的 L7 词（`read`/`write`/`save`/`load`/`compact`）只认识能力键：
#   :fs/read    path                  → String | nil（读不到则 nil）
#   :fs/write   text path             → 写入字节数
#   :fs/append  text path             → 追加字节数
#   :fs/size    path                  → 字节数 | nil
#   :fs/exists? path                  → 布尔
# 剔除本文件（make core-only）后核心仍可装载，L7 词报 60。

(defn cap/fs-read
  [path]
  (def p (protect (slurp path)))
  (if (get p 0) (string (get p 1)) nil))

(defn cap/fs-write
  [text path]
  (def p (protect (spit path text)))
  (when (not (get p 0))
    (error (string "写入失败：" path "（" (get p 1) "）")))
  (length text))

(defn cap/fs-append
  [text path]
  (def f (file/open path :a))
  (when (nil? f) (error (string "追加失败：" path)))
  (file/write f text)
  (file/close f)
  (length text))

(defn cap/fs-size
  [path]
  (def st (os/stat path))
  (if st (st :size) nil))

(defn cap/fs-exists?
  [path]
  (not (nil? (os/stat path))))

(rb/cap-put :fs/read cap/fs-read)
(rb/cap-put :fs/write cap/fs-write)
(rb/cap-put :fs/append cap/fs-append)
(rb/cap-put :fs/size cap/fs-size)
(rb/cap-put :fs/exists? cap/fs-exists?)
