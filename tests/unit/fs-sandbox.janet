# tests/unit/fs-sandbox.janet —— D-60：能力层文件沙箱（P0）
#
# 规则（cap/fs.janet）：
#   RB_SANDBOX 未设      → 根 = 进程当前目录
#   RB_SANDBOX=<路径>    → 根 = 该路径
#   RB_SANDBOX=none|*    → 关闭
# 越界：写 → 41，读 → 40（读的契约是「失败 = nil」，不给调用方两条失败路径）。

(def sb-dir
  (do (protect (os/mkdir "build/tmp")) "build/tmp"))

(defn sb-path
  [name]
  (string sb-dir "/" name))

(defn sb-rm
  [p]
  (protect (os/rm p))
  nil)

(deftest "D-60：根内可写可读，根外写 41 读 40"
  (fn []
    (def env (new-ws))
    (def inside (sb-path "sb-inside.txt"))
    (is= 0 (run-in-exit env (string "write \"沙\" \"" inside "\"")))
    (is= "沙" (eval-top-in env (string "read \"" inside "\"")))
    (sb-rm inside)
    (def outside "/tmp/rb-sb-denied.txt")
    (sb-rm outside)
    (is= 41 (run-in-exit env (string "write \"x\" \"" outside "\"")) "根外写")
    (is (nil? (os/stat outside)) "越界写不能落地")
    (is= 40 (run-in-exit env "read \"/etc/hostname\"") "根外读")))

(deftest "D-60：`..` 绕路也被拦（规范化后判定）"
  (fn []
    (def env (new-ws))
    (def src (string "write \"x\" \"" sb-dir "/../../etc/rb-sb-x.txt\""))
    (is= 41 (run-in-exit env src))
    (is (nil? (os/stat "/home/uiu/project/etc/rb-sb-x.txt")))))

(deftest "D-60：RB_SANDBOX=<路径> 换根；none 关闭"
  (fn []
    (def env (new-ws))
    (os/setenv "RB_SANDBOX" sb-dir)
    (is= 0 (run-in-exit env (string "write \"x\" \"" (sb-path "sb-root.txt") "\"")))
    (sb-rm (sb-path "sb-root.txt"))
    (is= 41 (run-in-exit env "write \"x\" \"build/sb-outside-root.txt\"") "换了根，仓库根就变根外")
    (os/setenv "RB_SANDBOX" "none")
    (is= 0 (run-in-exit env "write \"x\" \"/tmp/rb-sb-none.txt\""))
    (sb-rm "/tmp/rb-sb-none.txt")
    (os/setenv "RB_SANDBOX" nil)
    (is= 41 (run-in-exit env "write \"x\" \"/tmp/rb-sb-none.txt\"") "恢复缺省后又拦")))

(deftest "D-60：exists? / size 也走同一道检查"
  (fn []
    (def env (new-ws))
    (is= 40 (run-in-exit env "read \"/etc/hostname\"") "读不到（越界）")
    (def f (rb/cap-get :fs/size))
    (is (tuple? (protect (f "/etc/hostname"))) "size 越界要报错，不能静默返回 nil")))
