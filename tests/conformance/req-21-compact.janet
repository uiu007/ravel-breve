# tests/conformance/req-21-compact.janet —— REQ-21 compact 三条件
#   ① 日志 > 快照的 0.5 倍（主判据）② 日志 > 1000 条 ③ 显式调用

(do (protect (os/mkdir "build/tmp")) "build/tmp")

(defn p21
  [name]
  (string "build/tmp/req21-" name))

(defn big-str
  [n]
  (def b @"")
  (for i 0 n (buffer/push-string b "0123456789"))
  (string b))

(deftest "REQ-21：显式 compact —— 新快照接管，日志清空"
  (fn []
    (def env (new-ws))
    (def path (p21 "explicit.json"))
    (run-in env (string "junk : [ drop \"" (big-str 200) "\" ]"))
    (run-in env (string "save current \"" path "\""))
    (run-in env "z : [ + 7 ]")
    (is= 1 ((env :rb-ws) :seq) "compact 之前有一行日志")
    (run-in env "compact current")
    (is= 0 ((env :rb-ws) :seq) "compact 之后计数归零")
    (is= 0 (length (string/trim (slurp (string path ".log")))) "日志文件被清空")
    # 快照里现在有 z（下一轮才解析得到，REQ-33）
    (def e2 (new-ws))
    (eval-stack-in e2 (string "load \"" path "\"\npop"))
    (is= [12] (eval-stack-in e2 "z 5"))))

(deftest "REQ-21：① 日志超过 max(0.5 × 快照, 512 字节) → 自动 compact（主判据）"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (def path (p21 "ratio.json"))
    (run-in env (string "save current \"" path "\""))
    # 白盒：快照 2500 字节、日志 1260 字节（> 0.5 × 2500，也越过 512 字节下限）
    (rb/store-file-write (big-str 250) path)
    (put ws :snap-size 2500)
    (rb/store-file-write (big-str 126) (string path ".log"))
    (put ws :seq 1)
    (is (rb/store-compact-needed? ws) "判据成立")
    (run-in env "\"x\"")
    (is= 0 (ws :seq) "自动 compact 后计数归零")
    (is (< ((rb/store-log-ratio ws) :log) 512) "日志被截断")))

(deftest "REQ-21：小工作区不因比例判据每轮 compact（512 字节下限）"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (def path (p21 "floor.json"))
    (run-in env (string "pad : [ drop \"" (big-str 20) "\" ]"))
    (run-in env (string "save current \"" path "\""))
    (def snap-size (ws :snap-size))
    (is (> snap-size 0))
    (var n 0)
    (while (< n 3)
      (run-in env (string "\"" (big-str 5) "\""))
      (set n (+ n 1)))
    (def r (rb/store-log-ratio ws))
    (is (> ((rb/store-log-ratio ws) :log) 0) "日志在长")
    (is (< ((rb/store-log-ratio ws) :log) 512) "三轮之后日志仍小于下限")
    (is= 3 (ws :seq) "因此没有触发 compact（增量日志没有被退化成全量重写）")))

(deftest "REQ-21：② 日志超过 1000 条 → 自动 compact"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (def path (p21 "count.json"))
    (run-in env (string "pad : [ drop \"" (big-str 40) "\" ]"))
    (run-in env (string "save current \"" path "\""))
    # 白盒：把条数直接推过 1000（跑 1000 轮太慢），再跑一轮验证判据接线
    (put ws :seq 1000)
    (is (not (nil? (ws :logged-stack))) "save 之后有基线")
    (run-in env "\"x\"")
    (is= 0 (ws :seq) "超过 1000 条后自动 compact，计数归零")
    (is (< ((rb/store-log-ratio ws) :ratio) 0.5) "日志被截断")))

(deftest "REQ-21：compact 的栈效应是 Workspace --"
  (fn []
    (def env (new-ws))
    (def path (p21 "arity.json"))
    (run-in env (string "save current \"" path "\""))
    (is= [] (eval-stack-in env "compact current") "不留结果值")
    (is= 31 (eval-exit "compact 42") "非工作区 → 31")))

(deftest "REQ-21：未绑定路径的工作区 compact → 60（编排层）"
  (fn []
    (is= 60 (eval-exit "compact current"))))

(deftest "REQ-21：判据三选一各有一条可复现用例（汇总）"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (def path (p21 "summary.json"))
    (run-in env (string "save current \"" path "\""))
    (put ws :seq 1)
    (rb/store-file-write (big-str 250) path)                 # 2500 字节
    (put ws :snap-size 2500)
    (rb/store-file-write "" (string path ".log"))
    (is (not (rb/store-compact-needed? ws)) "空日志 + 少条数 → 不触发")
    (rb/store-file-write (big-str 126) (string path ".log"))  # 1260 > 0.5 * 2500
    (is (rb/store-compact-needed? ws) "① 倍率触发")
    (rb/store-file-write "" (string path ".log"))
    (put ws :seq 1001)
    (is (rb/store-compact-needed? ws) "② 条数触发")))
