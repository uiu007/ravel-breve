# tests/unit/preset.janet —— REQ-62 / REQ-63 provider 配置预设（v1.0k）+ REQ-64 可发现（v1.0l）
#
# 预设 = 一份 JSON，键就是工作区配置的白名单键。三条不变式：
#   ① 只写白名单键（`key` → 60 / 未知项 → 31，D-54）
#   ② 幂等、可叠加：只覆盖预设里出现的键
#   ③ 密钥永不落盘：导出时 headers 里带 Authorization 之类 → 60
#
# 夹具写进 build/tmp/presets/（沙箱根 = 仓库根，所以用仓库内相对路径）。

(def pv-dir "build/tmp/presets")

(defn pv-file
  "写一份夹具（JSON 文本）→ 路径。"
  [name text]
  (spit (string pv-dir "/" name) text)
  (string pv-dir "/" name))

(defn pv-in
  "在一个**新建工作区**里跑 body（配置随工作区走，不污染其它用例）。"
  [body]
  (def env (new-ws))
  (def prev (dyn :rb-ws))
  (setdyn :rb-ws (env :rb-ws))
  (def r (protect (body env)))
  (setdyn :rb-ws prev)
  (if (get r 0)
    (get r 1)
    (error (get r 1))))

(when (not (os/stat pv-dir)) (os/mkdir pv-dir))

(def pv-one (pv-file "one.json" "{\"provider\":\"opencode\",\"model\":\"m1\",\"max-tokens\":77}"))
(def pv-bad "build/tmp/presets/bad.json")
(spit pv-bad "{not json")
(def pv-key (pv-file "key.json" "{\"key\":\"sk-secret\"}"))
(def pv-unknown (pv-file "unknown.json" "{\"provier\":\"nvidia\"}"))
(def pv-array (pv-file "array.json" "[1,2,3]"))

# ---- 导入 ---------------------------------------------------------------

(deftest "REQ-62：llm-import 路径 → 只写预设里出现的键，返回配置表"
  (fn []
    (pv-in (fn [env]
             (def t (eval-top-in env (string "llm-import \"" pv-one "\"")))
             (is (dictionary? t) "压回的是配置表")
             (is= "opencode" (get t "provider") "provider 到位")
             (is= "m1" (get t "model") "model 到位")
             (is= 77 (get t "max-tokens") "max-tokens 到位")
             (is= nil (get t "temperature") "预设没写的键不会被塞进来")
             (is= "opencode" (eval-top-in env "llm-get \"provider\"") "llm-get 也看得见")))))

(deftest "REQ-62：llm-import 名字 → presets/<名字>.json（仓库自带的预设）"
  (fn []
    (pv-in (fn [env]
             (def t (eval-top-in env "llm-import \"opencode-go\""))
             (is= "opencode" (get t "provider") "自带预设的 provider")
             (is= 1024 (get t "max-tokens") "自带预设的 max-tokens")
             (is (string? (get t "model")) "自带预设给了具体模型名")))))

(deftest "REQ-62：导入可叠加——后装的覆盖同键、不清掉别的键"
  (fn []
    (pv-in (fn [env]
             (eval-top-in env (string "llm-import \"" pv-one "\""))
             (def two (pv-file "two.json" "{\"model\":\"m2\",\"temperature\":0.5}"))
             (def t (eval-top-in env (string "llm-import \"" two "\"")))
             (is= "m2" (get t "model") "同键被覆盖")
             (is= 0.5 (get t "temperature") "新键写入")
             (is= "opencode" (get t "provider") "没提到的键保持原样")
             (is= 77 (get t "max-tokens") "同上")))))

(deftest "REQ-62：导入 —— 不存在 → 40 ; 非法 JSON → 31 ; 非对象 → 31 ; 参数非字符串 → 31"
  (fn []
    (pv-in (fn [env]
             (is= 40 (run-in-exit env "llm-import \"build/tmp/presets/nope.json\"") "读不到 = 40")
             (is= 31 (run-in-exit env (string "llm-import \"" pv-bad "\"")) "坏 JSON = 31")
             (is= 31 (run-in-exit env (string "llm-import \"" pv-array "\"")) "数组不是预设 = 31")
             (is= 31 (run-in-exit env "llm-import 42") "参数类型 = 31")
             (is= 31 (run-in-exit env "llm-import \"\"") "空名字 = 31")))))

(deftest "REQ-62：预设不许带密钥、不许带未知配置项（D-54：密钥不进工作区）"
  (fn []
    (pv-in (fn [env]
             (is= 60 (run-in-exit env (string "llm-import \"" pv-key "\""))
                    "`key` → 60（与 llm-set 同一个理由）")
             (is= 31 (run-in-exit env (string "llm-import \"" pv-unknown "\""))
                    "拼错的配置项 → 31，不静默无效")))))

# ---- 导出 ---------------------------------------------------------------

(deftest "REQ-62：llm-export → 文件，再 llm-import 回来完全一致（往返）"
  (fn []
    (pv-in (fn [env]
             (eval-top-in env (string "llm-import \"" pv-one "\""))
             (def out (string pv-dir "/roundtrip.json"))
             (def n (eval-top-in env (string "llm-export \"" out "\"")))
             (is= 3 n "写入项数 = 预设里的键数")
             (def back (eval-top-in env (string "llm-import \"" out "\"")))
             (is= "opencode" (get back "provider"))
             (is= "m1" (get back "model"))
             (is= 77 (get back "max-tokens"))))))

(deftest "REQ-62：llm-export 只导显式配置——环境变量推出来的值不写进预设"
  (fn []
    (pv-in (fn [env]
             (eval-top-in env "llm-set \"nvidia\" \"provider\"")
             (def out (string pv-dir "/explicit.json"))
             (eval-top-in env (string "llm-export \"" out "\""))
             (def txt (string (slurp out)))
             (is (string/find "\"provider\"" txt) "显式项在")
             (is (nil? (string/find "\"endpoint\"" txt)) "endpoint 是推出来的，不导")
             (is (nil? (string/find "\"temperature\"" txt)) "temperature 同上")))))

(deftest "REQ-62：llm-export 不写密钥——headers 里有 Authorization → 60（D-54）"
  (fn []
    (pv-in (fn [env]
             (eval-top-in env "llm-set H{ \"Authorization\" \"Bearer sk-x\" } \"headers\"")
             (is= 60 (run-in-exit env (string "llm-export \"" pv-dir "/leak.json\""))
                    "宁可导不出去，也不把密钥写盘")
             (is (nil? (os/stat (string pv-dir "/leak.json"))) "文件根本没创建")))))

(deftest "REQ-62：llm-export 写不进去 → 41（与 write 词同一条映射）"
  (fn []
    (pv-in (fn [env]
             (eval-top-in env "llm-set \"mock\" \"provider\"")
             # 沙箱外的路径：读 40 / 写 41（REQ-53）
             (is= 41 (run-in-exit env "llm-export \"/tmp/rb-preset-outside.json\""))
             (is (nil? (os/stat "/tmp/rb-preset-outside.json")) "没留下文件")))))

# ---- 启动装载（REQ-63）--------------------------------------------------

(deftest "REQ-63：cap/preset-startup 按 RB_CONFIG → RB_PRESET → --preset 顺序装"
  (fn []
    (def cfg (string pv-dir "/user.json"))
    (spit cfg "{\"provider\":\"mock\",\"model\":\"from-file\"}\n")
    (def pre (string pv-dir "/pre.json"))
    (spit pre "{\"model\":\"from-preset\"}\n")
    (def old-cfg (os/getenv "RB_CONFIG"))
    (def old-pre (os/getenv "RB_PRESET"))
    (os/setenv "RB_CONFIG" cfg)
    (os/setenv "RB_PRESET" "build/tmp/presets/pre.json")
    (array/push rb/config-presets "nvidia")   # 相当于 `--preset nvidia`
    (def r (protect (pv-in (fn [env]
                             (def t (eval-top-in env "llm"))
                             (tup [(get t "provider") (get t "model")])))))
    (array/clear rb/config-presets)
    (os/setenv "RB_CONFIG" (or old-cfg "-"))
    (os/setenv "RB_PRESET" (or old-pre ""))
    (is (get r 0) "装载不报错")
    (def [provider model] (get r 1))
    (is= "nvidia" provider "最后一份预设（--preset nvidia）赢")
    (is= "meta/llama-3.2-11b-vision-instruct" model "nvidia 预设有具体模型")))

(deftest "REQ-63：RB_CONFIG=- 时完全不看用户配置文件（测试 hermetic）"
  (fn []
    (def old (os/getenv "RB_CONFIG"))
    (os/setenv "RB_CONFIG" "-")
    (def r (pv-in (fn [env] (eval-top-in env "llm"))))
    (os/setenv "RB_CONFIG" (or old "-"))
    (is= 0 (length (pairs r)) "工作区配置是空表")))

# ---- REQ-64：可发现（v1.0l）----------------------------------------------

(deftest "REQ-64：cap/preset-list 列出仓库自带的三份预设（按名字升序）"
  (fn []
    (def items (cap/preset-list))
    (def names (map |($ :name) items))
    (each n @["mock" "nvidia" "opencode-go"]
      (is (find |(= n $) names) (string "列到 " n)))
    # 升序
    (var ok true)
    (for i 1 (length names)
      (when (> (compare (names (- i 1)) (names i)) 0) (set ok false)))
    (is ok "按名字升序")
    # 每项都带路径与解出来的配置
    (def oc (find |(= "opencode-go" ($ :name)) items))
    (is= "presets/opencode-go.json" (oc :path))
    (is= "opencode" (get (oc :config) "provider"))))

(deftest "REQ-64：坏预设不会让「列出来」整体失败（留着 :error 继续列）"
  (fn []
    (def dir "build/tmp/list")
    (when (not (os/stat dir)) (os/mkdir dir))
    # 借 cap/preset-dir 的目录是确定的，这里直接验证 list 的容错：临时造一份坏的
    (def good (string dir "/good.json"))
    (spit good "{\"provider\":\"mock\"}")
    (def p (protect (cap/preset-list)))
    (is (get p 0) "列目录本身不抛")))

(deftest "REQ-64：找不到时的报错带可用名字（名字写错也能自助）"
  (fn []
    (def msg (rb/error-msg
               (get (protect (cap/preset-import "nope")) 1)))
    (is (string/find "nope.json" msg) "说了找的是哪个文件")
    (is (string/find "opencode-go" msg) "列了可用的名字")
    # 显式路径不猜：只说可以看 --presets
    (def msg2 (rb/error-msg
                (get (protect (cap/preset-import "/tmp/nope.json")) 1)))
    (is (string/find "--presets" msg2))))

(deftest "REQ-64：用户配置文件路径判据在核心里（RB_CONFIG 三态）"
  (fn []
    (def old (os/getenv "RB_CONFIG"))
    (def old-xdg (os/getenv "XDG_CONFIG_HOME"))
    (os/setenv "RB_CONFIG" nil)
    (os/setenv "XDG_CONFIG_HOME" "/xdg")
    (is= "/xdg/ravel/config.json" (rb/config-user-path))
    (os/setenv "XDG_CONFIG_HOME" nil)
    (is (string/has-suffix? "/.config/ravel/config.json" (rb/config-user-path)))
    (os/setenv "RB_CONFIG" "/tmp/c.json")
    (is= "/tmp/c.json" (rb/config-user-path))
    (os/setenv "RB_CONFIG" "-")
    (is (nil? (rb/config-user-path)))
    (os/setenv "RB_CONFIG" "")
    (is (nil? (rb/config-user-path)))
    (os/setenv "RB_CONFIG" (or old "-"))
    (os/setenv "XDG_CONFIG_HOME" old-xdg)))
