# tests/conformance/req-20-workspace.janet —— REQ-20 工作区持久化（快照 + JSONL 增量日志）
#
# 覆盖：字典 / 栈 / agent 血缘 随快照往返；日志增量与重放；崩溃半行容忍；
# L7 词 read/write/save/load/current 的栈效应与错误码。

(do (protect (os/mkdir "build/tmp")) "build/tmp")

(defn p20
  [name]
  (string "build/tmp/req20-" name))

# 0.5 倍判据（REQ-21 主判据）会让小工作区每轮都 compact，
# 于是「增量日志」在小工作区里看不见。测日志时先把快照撑大。
(defn pad-src
  []
  (def b @"")
  (for i 0 40 (buffer/push-string b "abcdefghij"))
  (string b))

(defn pad!
  [env]
  (run-in env (string "pad : [ drop \"" (pad-src) "\" ]")))

(defn log-lines
  [path]
  (filter (fn [l] (not= l "")) (string/split "\n" (slurp (string path ".log")))))

(deftest "REQ-20：字典跨进程往返（源随快照存，载入后重新可调用）"
  (fn []
    (def e1 (new-ws))
    (run-in e1 (string "dbl : [ * 2 ]\nsave current \"" (p20 "dict.json") "\""))
    (def e2 (new-ws))
    (is= [] (eval-stack-in e2 (string "load \"" (p20 "dict.json") "\"\npop"))
         "载入本身正常")
    # 注意：转译在**载入之前**完成，所以载入进来的词要下一轮才解析得到（REQ-33）
    (is= [42] (eval-stack-in e2 "dbl 21") "新工作区载入后字典可用")))

(deftest "REQ-20：栈跨进程往返（栈 = 工作区的变量那半）"
  (fn []
    (def e1 (new-ws))
    (run-in e1 (string "1 \"two\"\nsave current \"" (p20 "stack.json") "\""))
    (def e2 (new-ws))
    # 书写 `1 "two"` → 镜像后先压 "two" 再压 1，故保存的栈是 ("two" 1)
    (is= ["two" 1] (eval-stack-in e2 (string "load \"" (p20 "stack.json") "\"\npop"))
         "载入后栈恢复为保存时的样子")))

(deftest "REQ-20：agent 会话与血缘随快照往返"
  (fn []
    (def e1 (new-ws))
    (def r1 (run-in e1 (string "agent \"c\" { }\nappend say \"一\"\n"
                               "save current \"" (p20 "agent.json") "\"")))
    (is (r1 :ok) "保存应成功")
    (def e2 (new-ws))
    (def r2 (run-in e2 (string "load \"" (p20 "agent.json") "\"\npop\nsession")))
    (is (r2 :ok) (string "载入应成功：" (if (r2 :ok) "" (rb/error-msg (r2 :error)))))
    (def sess (last (r2 :stack)))
    (is= 1 (length sess))
    (is= "一" ((sess 0) :content))
    (is= 1 (length ((e2 :rb-ws) :agents)) "活 agent 注册表也重建")
    (is= "c" ((((e2 :rb-ws) :agents) 0) :label))))

(deftest "REQ-20：绑定路径后每一轮追加一行日志（增量，不是整份重写）"
  (fn []
    (def env (new-ws))
    (def path (p20 "log.json"))
    (run-in env (string "a : [ + 1 ]"))
    (pad! env)
    (run-in env (string "save current \"" path "\""))
    (is= 0 ((env :rb-ws) :seq) "save 之后日志计数归零")
    (run-in env "a 1")
    (is= 1 ((env :rb-ws) :seq) "一轮一行")
    (run-in env "a 2")
    (run-in env "a 3")
    (def lines (log-lines path))
    (is= 3 (length lines) "三行日志")
    (is (string/find "\"n\":1" (slurp (string path ".log"))) "带序号")))

(deftest "REQ-20：日志重放——只存日志里的定义，新工作区载入后仍在"
  (fn []
    (def env (new-ws))
    (def path (p20 "replay.json"))
    (pad! env)
    (run-in env (string "save current \"" path "\""))
    (run-in env "sq : [ * 4 ]")
    (is= 1 ((env :rb-ws) :seq))
    (def e2 (new-ws))
    (eval-stack-in e2 (string "load \"" path "\"\npop"))
    (is= [16] (eval-stack-in e2 "sq 4")
         "定义只在日志里，也要能重放出来")))

(deftest "REQ-20：compact 之后日志清空，但状态不丢（快照接管）"
  (fn []
    (def env (new-ws))
    (def path (p20 "compact.json"))
    (pad! env)
    (run-in env (string "save current \"" path "\""))
    (run-in env "k : [ * 5 ]")
    (is= 1 ((env :rb-ws) :seq) "先有一行日志")
    (run-in env (string "compact current"))
    (is= 0 ((env :rb-ws) :seq) "compact 后计数归零")
    (is= 0 (length (slurp (string path ".log"))) "日志被清空")
    (def e2 (new-ws))
    (eval-stack-in e2 (string "load \"" path "\"\npop"))
    (is= [25] (eval-stack-in e2 "k 5") "快照接管了日志里的定义")))

(deftest "REQ-20：日志末行半截（崩溃残留）→ 载入不失败，好行照常生效"
  (fn []
    (def env (new-ws))
    (def path (p20 "crash.json"))
    (pad! env)
    (run-in env (string "save current \"" path "\""))
    (run-in env "half : [ + 2 ]")
    (def logp (string path ".log"))
    # 模拟写到一半被杀：拼上一段不完整的 JSON
    (def f (file/open logp :a))
    (file/write f "{\"v\":1,\"n\":99,\"defs\":[{\"na")
    (file/close f)
    (def e2 (new-ws))
    (def r (run-in e2 (string "load \"" path "\"\npop")))
    (is (r :ok) "半行不该让载入失败")
    (is= [3] (eval-stack-in e2 "half 1") "完整的那行仍然生效")))

(deftest "REQ-20：read / write 是 L7 词（经能力层）"
  (fn []
    (def path (p20 "rw.txt"))
    (is= [] (eval-stack (string "write \"你好\" \"" path "\"")))
    (is= ["你好"] (eval-stack (string "read \"" path "\"")))
    (is= 40 (eval-exit (string "read \"" (p20 "nope.txt") "\"")) "读不到 → 40")))

(deftest "REQ-20：load 不存在的文件 → 40；save 非当前工作区 → 31"
  (fn []
    (is= 40 (eval-exit (string "load \"" (p20 "nope.json") "\"")))
    (is= 31 (eval-exit "save H{ } \"/tmp/x.json\""))))

(deftest "REQ-20：current 压入的是当前工作区句柄"
  (fn []
    (def env (new-ws))
    (def r (run-in env "current"))
    (is (= (env :rb-ws) (last (r :stack))) "current 给出的就是 (env :rb-ws)")))

(deftest "REQ-20：快照是单文件 JSON，且不含宿主序"
  (fn []
    (def env (new-ws))
    (def path (p20 "single.json"))
    (run-in env (string "f : [ + 1 ]\nsave current \"" path "\""))
    (def text (slurp path))
    (is (string/find "ravel-workspace" text))
    (is (not (string/find "rb/push" text)) "存源不存宿主码（D-34）")
    (is (not (string/find "\n" text)) "单文件 JSON 允许换行，但这里应是一行")))

(deftest "REQ-20：日志按条数增长，而不是每次全量重写"
  (fn []
    (def env (new-ws))
    (def path (p20 "grow.json"))
    (pad! env)
    (run-in env (string "save current \"" path "\""))
    (def s0 (os/stat (string path ".log")))
    (run-in env "g : [ + 9 ]")
    (def s1 (os/stat (string path ".log")))
    (is (> (s1 :size) (if s0 (s0 :size) 0)) "日志只增不减")))
