# rb/words/l7.janet —— L7 持久化词（REQ-20 / REQ-21）
#
# 书写序（最左 = 栈顶 = 先被消费，D-04）：
#   read    Path              -- String          读文件
#   write   String Path       --                 写文件
#   save    Workspace Path    --                 写快照并把工作区绑定到该路径
#   load    Path              -- Workspace       载入快照 + 重放日志
#   current                   -- Workspace       当前工作区
#   compact Workspace         --                 写新快照、清空日志
#
# 例子（一行一操作，书写序 = 执行序）：
#   save current "w.json"      # 存
#   load "w.json"              # 取（载入到当前工作区）
#
# 文件 IO / JSON 都在能力层（REQ-37）：剔除 cap/ 后这些词报 60，别的照旧。

(defn rb/read
  "Path -- String；读不到 → 40。"
  []
  (def path (rb/pop))
  (when (not (string? path))
    (rb/raise (rb/exit-table :runtime-type)
              (string "read 需要一个路径字符串，得到 " (type path))))
  (def f (rb/cap-get :fs/read))
  (when (nil? f)
    (rb/raise (rb/exit-table :orchestration-base) "read 需要能力 :fs/read（cap/fs）"))
  (def text (f path))
  (when (nil? text)
    (rb/raise (rb/exit-table :io-read) (string "文件不存在或无权限：" path)))
  (rb/push text))

(defn rb/write
  "String Path -- ；写文件（失败 41）。"
  []
  (def text (rb/pop))
  (def path (rb/pop))
  (when (not (string? path))
    (rb/raise (rb/exit-table :runtime-type)
              (string "write 需要一个路径字符串，得到 " (type path))))
  (rb/store-file-write (string text) path)
  nil)

(defn rb/current-ws
  "current -- Workspace；取当前工作区（REQ-30）。"
  []
  (rb/push (rb/ws)))

(defn rb/save
  "Workspace Path -- ；写快照 + 截断日志，并把工作区绑定到该路径（REQ-20）。"
  []
  (def ws (rb/pop))
  (def path (rb/pop))
  (when (not (table? ws))
    (rb/raise (rb/exit-table :runtime-type)
              (string "save 需要一个 Workspace，得到 " (type ws))))
  (when (not= ws (rb/ws))
    (rb/raise (rb/exit-table :runtime-type)
              "save 只支持当前工作区（先用 current 取，D-35）"))
  (rb/store-save! ws (rb/stack) path)
  nil)

(defn rb/load
  "Path -- Workspace；载入快照 + 重放日志，装入当前工作区（REQ-20）。"
  []
  (def path (rb/pop))
  (def ws (rb/ws))
  (def ok (rb/store-load! ws path))
  # 新的栈来自文件；把结果留在栈上（`load` 的返回值 = 工作区句柄）
  (rb/push ok)
  nil)

(defn rb/compact
  "Workspace -- ；写新快照并清空日志（REQ-21）。"
  []
  (def ws (rb/pop))
  (when (not (table? ws))
    (rb/raise (rb/exit-table :runtime-type)
              (string "compact 需要一个 Workspace，得到 " (type ws))))
  (when (not= ws (rb/ws))
    (rb/raise (rb/exit-table :runtime-type)
              "compact 只支持当前工作区（先用 current 取，D-35）"))
  (rb/store-compact! ws (rb/stack))
  nil)
