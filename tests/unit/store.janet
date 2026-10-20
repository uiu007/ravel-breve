# tests/unit/store.janet —— 持久化底层：值编码（D-36）/ 判据（REQ-21）/ 半行容忍

(def store-tmp
  (do (protect (os/mkdir "build/tmp")) "build/tmp"))

(defn sp
  "测试用的临时路径（每个用例自带前缀，避免互相踩）。"
  [name]
  (string store-tmp "/" name))

(deftest "D-36：标量原样往返（字符串 / 数字 / 布尔 / nil）"
  (fn []
    (each v @["abc" "" 1 -2 3.5 true false nil]
      (is= v (rb/store-dec (rb/store-enc v) (rb/ws))))))

(deftest "D-36：tuple 与 array 往返且形态不混"
  (fn []
    (def t (rb/store-dec (rb/store-enc (tuple 1 2 3)) (rb/ws)))
    (is (tuple? t))
    (is= (tuple 1 2 3) t)
    (def a (rb/store-dec (rb/store-enc @[1 2 3]) (rb/ws)))
    (is (array? a) "array 不能变成 tuple")
    (is= @[1 2 3] a)))

(deftest "D-36：Utter 与嵌套会话往返"
  (fn []
    (def sess @[@{:role "user" :content "问"}
                 @{:role "assistant" :content "答"}])
    (def back (rb/store-dec (rb/store-enc sess) (rb/ws)))
    (is (array? back))
    (is= 2 (length back))
    (is= "user" ((back 0) :role))
    (is= "答" ((back 1) :content))))

(deftest "D-36：普通表 / 关键字往返"
  (fn []
    (def back (rb/store-dec (rb/store-enc @{:a 1 :b @{:c "x"}}) (rb/ws)))
    (is= 1 (back "a"))
    (is= "x" ((back "b") "c"))
    (is= :kw (rb/store-dec (rb/store-enc :kw) (rb/ws)))
    (is= 'sym (rb/store-dec (rb/store-enc 'sym) (rb/ws)))))

(deftest "D-36：Stream 不可持久化 → 载入为「缺席」（保存时也不进快照）"
  (fn []
    (def s (rb/stream-new "l" nil (fn [] nil) @{}))
    (def enc (rb/store-enc s))
    (is= "stream" (enc "$"))
    (is= rb/store-absent (rb/store-dec enc (rb/ws)))
    # 栈编码丢弃 stream，其余保留
    (def enc-stack (rb/store-enc-stack @["a" s]))
    (is= 1 (length enc-stack) "stream 不进栈编码")
    (is= "a" (enc-stack 0))))

(deftest "D-36：Agent → agent-ref，按 label 解析回同一个 agent"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (run-in env "agent \"c\" { }")
    (def a (last (env :rb-stack)))
    (def enc (rb/store-enc a))
    (is= "agent-ref" (enc "$"))
    (is= "c" (enc "label"))
    (is (= a (rb/store-dec enc ws)) "同一工作区内应解析回原 agent")))

(deftest "D-36：工作区本身编码为 workspace 引用（避免走 :env 的环）"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (is= "workspace" ((rb/store-enc ws) "$"))
    (is (= ws (rb/store-dec @{"$" "workspace"} ws)))))

(deftest "D-36：过深的表退化为 opaque（防环 / 防爆炸）"
  (fn []
    (var v @{:x 1})
    (for i 0 20 (set v @{:x v}))
    # 逐层下钻，最里面那层应退化为 opaque
    (var e (rb/store-enc v))
    (var n 0)
    (while (and (= "table" (e "$")) (< n 40))
      (set e ((e "v") "x"))
      (set n (+ n 1)))
    (is= "opaque" (e "$"))
    (is (< n 20) "确实在某个深度截断了")))

(deftest "REQ-20：快照含 kind / version / dict / stack / agents 五段"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (run-in env "dbl : [ * 2 ]")
    (def snap (rb/store-decode (rb/store-snapshot ws @[1 "a"])))
    (is= rb/store-kind (snap "kind"))
    (is= rb/store-version (snap "version"))
    (is= "* 2" (get ((snap "dict") "dbl") "src") "字典只存 ravel 源")
    (is (not (string/find "rb/push" (rb/store-encode (snap "dict"))))
        "快照里不该出现宿主序")
    (is= 2 (length (snap "stack")))
    (is (array? (snap "agents")))))

(deftest "REQ-21：比例判据在 0.5 倍边界（> 0.5 才触发）"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (put ws :path (sp "ratio.json"))
    (put ws :seq 1)
    (rb/store-file-write "0123456789" (sp "ratio.json"))         # 快照 10 字节
    (put ws :snap-size 10)
    (rb/store-file-write "01234" (string (sp "ratio.json") ".log"))   # 日志 5 = 0.5
    (is= 0.5 ((rb/store-log-ratio ws) :ratio))
    (is (not (rb/store-compact-needed? ws)) "恰好 0.5 不触发")
    (rb/store-file-write "012345" (string (sp "ratio.json") ".log"))  # 6 = 0.6
    (is (rb/store-compact-needed? ws) "超过 0.5 触发")))

(deftest "REQ-21：条数判据在 1000 条边界（> 1000 才触发）"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (put ws :path (sp "count.json"))
    (rb/store-file-write "0123456789" (sp "count.json"))
    (put ws :snap-size 10)
    (rb/store-file-write "" (string (sp "count.json") ".log"))
    (put ws :seq 1000)
    (is (not (rb/store-compact-needed? ws)) "1000 条不触发")
    (put ws :seq 1001)
    (is (rb/store-compact-needed? ws) "1001 条触发")))

(deftest "REQ-20：日志末行半截 → 载入忽略该行（崩溃恢复）"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (def path (sp "half.json"))
    (run-in env "dbl : [ * 2 ]")
    (rb/store-save! ws (env :rb-stack) path)
    # 追加一行好行 + 一行被截断的坏行
    (def good (string (rb/store-log-line ws 1 @[] @[7]) "\n"))
    (rb/store-file-append (string good "{\"v\":1,\"n\":2,\"def") (string path ".log"))
    (def env2 (new-ws))
    (def r (rb/store-load! (env2 :rb-ws) path))
    (is (not (nil? r)))
    (is= 1 ((env2 :rb-ws) :seq) "只重放了完整的一行")
    (is= (tuple 7) (tup (env2 :rb-stack)) "好行生效")))
