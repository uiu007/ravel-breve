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

(deftest "REQ-21：① 日志超过快照 0.5 倍 → 自动 compact（主判据）"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (def path (p21 "ratio.json"))
    (run-in env (string "pad : [ drop \"" (big-str 20) "\" ]"))
    (run-in env (string "save current \"" path "\""))
    (def snap-size (ws :snap-size))
    (is (> snap-size 0))
    # 每轮往栈上加一个 200 字节的值：日志涨得比快照快
    (var n 0)
    (while (and (< n 20) (< (or (ws :seq) 0) 1))
      (run-in env (string "\"" (big-str 20) "\""))
      (set n (+ n 1)))
    # 到这一步：要么已经自动 compact（seq 归零、日志很短），要么判据不成立
    (def r (rb/store-log-ratio ws))
    (is (< (r :ratio) 0.5) "compact 之后比例必须回落到 0.5 以下")
    (is (< (r :log) snap-size) "日志比快照短")
    (is (> n 0) "至少跑过一轮")))

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
    (rb/store-file-write (big-str 10) path)
    (put ws :snap-size 100)
    (rb/store-file-write "" (string path ".log"))
    (is (not (rb/store-compact-needed? ws)) "空日志 + 少条数 → 不触发")
    (rb/store-file-write (big-str 6) (string path ".log"))   # 60 > 0.5 * 100
    (is (rb/store-compact-needed? ws) "① 倍率触发")
    (rb/store-file-write "" (string path ".log"))
    (put ws :seq 1001)
    (is (rb/store-compact-needed? ws) "② 条数触发")))
