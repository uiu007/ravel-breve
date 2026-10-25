# tests/unit/plugins.janet —— REQ-60 插件 ABI（v1.0j）
#
# 分层验收：插件只能往**用户层**加东西（词 / 钩子 / 工具），
# 核心层（词法 / 转译 / 栈 / 流 / agent / 钩子机制 / 协议）不受影响。
# 夹具：tests/fixtures/plugins/*.breve（不走 examples/，例程可以随便改）

(def pl-ok "tests/fixtures/plugins/ok.breve")
(def pl-fail "tests/fixtures/plugins/fail.breve")
(def pl-redef "tests/fixtures/plugins/redef.breve")
(def pl-nested "tests/fixtures/plugins/nested.breve")

(defn pl-in
  "在一个**新建工作区**里跑 body，并把 dyn 指向它（钩子/工具/字典都按 dyn 取），
   跑完无论成败都把 dyn 还原——否则会污染后面的用例。"
  [body]
  (def env (new-ws))
  (def prev (dyn :rb-ws))
  (setdyn :rb-ws (env :rb-ws))
  (def r (protect (body env)))
  (setdyn :rb-ws prev)
  (if (get r 0) (get r 1) (error (get r 1))))

(deftest "REQ-60：plug 装载 → 名字 / 台账 / 词 / 钩子 / 工具都到位"
  (fn []
    (pl-in (fn [env]
             (def h0 (hook-count-in env "@Chunk"))
             (is= "ok" (eval-top-in env (string "plug \"" pl-ok "\"")) "返回插件名")
             (is= (tup ["ok"]) (eval-top-in env "plugins") "台账里有它")
             # 插件词只能在**下一轮**用：同一份源在转译期就解析完了
             (is= 42 (eval-top-in env "p-ok 41") "插件词可用")
             (is= (+ h0 1) (hook-count-in env "@Chunk") "钩子挂上了")
             (is (not (nil? (get ((env :rb-ws) :tools) "p-tool"))) "工具注册了")))))

(deftest "REQ-60：装载不算一轮——不额外触发 @RoundDone，也不往本轮列表塞东西"
  (fn []
    (pl-in (fn [env]
             (def n @{:n 0})
             (hook-on-in env "@RoundDone" (fn [] (put n :n (inc (n :n)))))
             (eval-top-in env (string "plug \"" pl-ok "\""))
             (is= 0 (n :n) "plug 自身不算一轮（@RoundDone 没响）")
             (is= 0 (length ((env :rb-ws) :round)) "也没往本轮列表塞东西")
             # 造一轮**有流的**求值：收尾钩子才会响（空轮不触发，属 REQ-18 既有语义）
             (eval-top-in env (string "agent \"m\" { }\n"
                                      "dup\nsend say \"hi\"\n"
                                      "append utter"))
             (is= 1 (n :n) "普通求值仍算一轮")))))

(deftest "REQ-60：插件残留的操作数不外溢到调用者"
  (fn []
    (pl-in (fn [env]
             (eval-top-in env (string "plug \"" pl-ok "\""))
             (is= (tup ["ok"]) (eval-stack-in env "") "只留下 plug 自己的返回值")))))

(deftest "REQ-60：unplug 精确撤销（词 + 钩子 + 工具），并返回项数"
  (fn []
    (pl-in (fn [env]
             (def h0 (hook-count-in env "@Chunk"))
             (eval-top-in env (string "plug \"" pl-ok "\""))
             (is= 3 (eval-top-in env "unplug \"ok\"") "撤了三项")
             (is= (tup []) (eval-top-in env "plugins") "台账清空")
             (is= 20 (run-in-exit env "p-ok 41") "词跟着走了（未知的词）")
             (is= h0 (hook-count-in env "@Chunk") "钩子回到装载前")
             (is (nil? (get ((env :rb-ws) :tools) "p-tool")) "工具回到装载前")
             (is= 20 (run-in-exit env "unplug \"ok\"") "重复卸载 → 20")))))

(deftest "REQ-60：装载失败 → 已装的部分全部撤销（不留半装状态）"
  (fn []
    (pl-in (fn [env]
             (is= 33 (run-in-exit env (string "plug \"" pl-fail "\"")) "原错误码透出")
             (is= (tup []) (eval-top-in env "plugins") "台账里没有它")
             (is= 20 (run-in-exit env "p-half") "半装的词也撤了")))))

(deftest "REQ-60：插件重定义已有词 → 卸载后还原旧词条"
  (fn []
    (pl-in (fn [env]
             (eval-top-in env "twice : [ * 2 ]")
             (is= 6 (eval-top-in env "twice 3") "原词条")
             (eval-top-in env (string "plug \"" pl-redef "\""))
             (is= 9 (eval-top-in env "twice 3") "插件版生效")
             (eval-top-in env "unplug \"redef\"")
             (is= 6 (eval-top-in env "twice 3") "卸载后回到原词条")))))

(deftest "REQ-60：同名重装先卸旧账（不留孤儿注册）"
  (fn []
    (pl-in (fn [env]
             (eval-top-in env (string "plug \"" pl-ok "\""))
             (def h1 (hook-count-in env "@Chunk"))
             (eval-top-in env (string "plug \"" pl-ok "\""))
             (is= h1 (hook-count-in env "@Chunk") "钩子没叠成两份")
             (is= (tup ["ok"]) (eval-top-in env "plugins") "台账还是一份")
             (is= 3 (eval-top-in env "unplug \"ok\"") "仍只撤三项")))))

(deftest "REQ-60：插件里不能再 plug（不做传递依赖）"
  (fn []
    (pl-in (fn [env]
             (is= 31 (run-in-exit env (string "plug \"" pl-nested "\"")) "嵌套装载 → 31")
             (is= (tup []) (eval-top-in env "plugins") "谁也没装上")))))

(deftest "REQ-60：坏路径 / 坏参数 / 缺能力 → 40 / 31 / 60"
  (fn []
    (pl-in (fn [env]
             (is= 40 (run-in-exit env "plug \"tests/fixtures/plugins/nope.breve\"")
                  "文件不存在 → 40")
             (is= 31 (run-in-exit env "plug 42") "非字符串 → 31")
             (is= 31 (run-in-exit env "unplug 42") "非字符串 → 31")
             # 缺能力（--core-only 的边界）：摘掉 :fs/read 后 plug 给出可读错误
             (def saved (rb/cap-get :fs/read))
             (put rb/cap :fs/read nil)
             (is= 60 (run-in-exit env (string "plug \"" pl-ok "\"")) "缺能力 → 60")
             (rb/cap-put :fs/read saved)
             (is= "ok" (eval-top-in env (string "plug \"" pl-ok "\"")) "装回来就能用")))))

(deftest "REQ-60：RB_PLUGINS 启动装载（新工作区建好就装上）"
  (fn []
    (def saved (os/getenv "RB_PLUGINS"))
    (os/setenv "RB_PLUGINS" (string pl-ok ", " pl-redef))
    (def r (protect (pl-in (fn [env]
                             (is= (tup ["ok" "redef"]) (eval-top-in env "plugins")
                                  "按序装了两个")
                             (is= 42 (eval-top-in env "p-ok 41") "启动装的词可用")))))
    (os/setenv "RB_PLUGINS" saved)
    (if (get r 0) (get r 1) (error (get r 1)))))

(deftest "REQ-60：插件不改核心层——换名表（核心词表）不随插件变，字典只多插件的词"
  (fn []
    (pl-in (fn [env]
             (def r0 (length rb/rename))
             (def d0 (length (keys ((env :rb-ws) :dict))))
             (eval-top-in env (string "plug \"" pl-ok "\""))
             (is= (+ d0 1) (length (keys ((env :rb-ws) :dict))) "字典只多了插件那一个词")
             (is= r0 (length rb/rename) "换名表没变")))))

(deftest "REQ-61：技能自带样板 skills/ravel-breve-plugin/plugin.breve 能装能跑"
  (fn []
    (pl-in (fn [env]
             (is= "plugin" (eval-top-in env "plug \"skills/ravel-breve-plugin/plugin.breve\"")
                  "技能样板可装载")
             (is= 42 (eval-top-in env "sum2 40 2") "样板里的词能用")
             (is= 42 (eval-top-in env "invoke \"sum\" H{ \"a\" 40 \"b\" 2 }")
                  "样板里的工具能用")
             # 样板里的 @Close 钩子：流关闭后 flags 里有记号
             (eval-top-in env (string "agent \"a\" { }\n"
                                      "send say \"hi\"\n"
                                      "drain"))
             (is (eval-top-in env "flag \"saw-close\"") "样板里的钩子确实挂上了")
             (is= 3 (eval-top-in env "unplug \"plugin\"") "词 + 钩子 + 工具 = 3 项")))))
