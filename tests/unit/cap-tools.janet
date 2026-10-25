# tests/unit/cap-tools.janet —— D-61：能力层默认工具包（P1）
#
# 四个工具都是**普通工具表项**（REQ-48 契约）：`rb/tool-run` 先把参数压栈，
# 工具自己 `rb/pop` 取，结果留在栈顶。写盘一律先过 D-60 的沙箱。

(def ct-dir
  (do (protect (os/mkdir "build/tmp")) "build/tmp"))

(defn ct-path
  [name]
  (string ct-dir "/" name))

(deftest "D-61 / D-72：ws-new 装好六个默认工具（read/write/edit/glob/grep/shell）"
  (fn []
    (def env (new-ws))
    (def names (sort (keys ((env :rb-ws) :tools))))
    (is= (tup ["edit" "glob" "grep" "read" "shell" "write"]) (tup names))
    (is= (tup ["edit" "glob" "grep" "read" "shell" "write"])
         (tup ((env :rb-ws) :mode-tools))
         "记在 :mode-tools，切模式时只撤这一批")))

(deftest "D-72：read 带行号、offset/limit 续读；write 原子替换"
  (fn []
    (def env (new-ws))
    (def p (ct-path "ct-read.txt"))
    (spit p "alpha\nbeta\ngamma\ndelta\n")
    (def head (eval-top-in env (string "invoke \"read\" H{ \"path\" \"" p "\" \"limit\" 2 }")))
    (is (string/find "1  alpha\n2  beta" head) "带行号，limit 生效")
    (is (string/find "[还有 2 行" head) "截断时尾附续读提示")
    (def rest (eval-top-in env (string "invoke \"read\" H{ \"path\" \"" p "\" \"offset\" 3 }")))
    (is (string/find "3  gamma" rest))
    (is (string/find "delta" rest))
    # write 是**替换**不是追加，且返回字节数
    (is= 1 (eval-top-in env (string "invoke \"write\" H{ \"path\" \"" p "\" \"content\" \"z\" }"))
        "返回写入字节数")
    (is= "z" (string (slurp p)) "整份替换（原子 rename）")
    (protect (os/rm p))))

(deftest "D-61：edit 改文件内容（字面量全替换），找不到 old → 60"
  (fn []
    (def env (new-ws))
    (def p (ct-path "ct-edit.txt"))
    (is= 0 (run-in-exit env (string "write \"hello old world\" \"" p "\"")))
    (def r (eval-top-in env (string "invoke \"edit\" H{ \"path\" \"" p "\""
                                    " \"old\" \"old\" \"new\" \"new\" }")))
    (is (string/find "已改 1 处" r))
    (is= "hello new world" (eval-top-in env (string "read \"" p "\"")))
    (is= 60 (run-in-exit env (string "invoke \"edit\" H{ \"path\" \"" p "\""
                                     " \"old\" \"没有这个\" \"new\" \"x\" }")))
    (protect (os/rm p))))

(deftest "D-61：glob 段内 * / ? 与任意层 **"
  (fn []
    (def env (new-ws))
    (def d (string ct-dir "/ct-glob"))
    (protect (os/mkdir d))
    (protect (os/mkdir (string d "/sub")))
    (spit (string d "/a.txt") "")
    (spit (string d "/b.md") "")
    (spit (string d "/sub/c.txt") "")
    (def top (eval-top-in env (string "invoke \"glob\" H{ \"pattern\" \"*.txt\""
                                      " \"dir\" \"" d "\" }")))
    (is= (string d "/a.txt") top "段内 * 只命中一层")
    (def deep (eval-top-in env (string "invoke \"glob\" H{ \"pattern\" \"**/*.txt\""
                                       " \"dir\" \"" d "\" }")))
    (is (string/find "sub/c.txt" deep) "** 跨层")
    (protect (os/rm (string d "/a.txt")))
    (protect (os/rm (string d "/b.md")))
    (protect (os/rm (string d "/sub/c.txt")))
    (protect (os/rm (string d "/sub")))
    (protect (os/rm d))))

(deftest "D-61：grep 字面量搜索，输出 path:行号: 文本"
  (fn []
    (def env (new-ws))
    (def p (ct-path "ct-grep.txt"))
    (is= 0 (run-in-exit env (string "write \"alpha\\nbeta\\ngamma\" \"" p "\"")))
    (def out (eval-top-in env (string "invoke \"grep\" H{ \"pattern\" \"beta\""
                                      " \"path\" \"" p "\" }")))
    (is (string/find ":2: beta" out))
    (is= "" (eval-top-in env (string "invoke \"grep\" H{ \"pattern\" \"zzz\""
                                     " \"path\" \"" p "\" }")))
    (protect (os/rm p))))

(deftest "D-61 / REQ-67：shell 的授权来自模式设定——装好就能用，一行能关掉"
  (fn []
    (def env (new-ws))
    # 缺省就是 default 模式：设定随模式来，不该让人先去设环境变量
    (is= "hi\n" (eval-top-in env "invoke \"shell\" H{ \"cmd\" \"echo hi\" }"))
    (def bad (eval-top-in env "invoke \"shell\" H{ \"cmd\" \"echo oops >&2 && exit 3\" }"))
    (is (string/find "[退出码 3]" bad))
    # 关掉：开关 → 60，且 wire 上不再公示（模型看不见，就不会在回合中途撞墙）
    (is= 0 (run-in-exit env "flag-set false \"allow-shell\""))
    (is= 60 (run-in-exit env "invoke \"shell\" H{ \"cmd\" \"echo hi\" }"))
    (is= (tup ["edit" "glob" "grep" "read" "write"])
         (tup (val-in env rb/tool-wire)) "关掉后 wire 里没有 shell")
    # 环境变量是显式覆盖，两个方向都行
    (os/setenv "RB_ALLOW_SHELL" "1")
    (is= "hi\n" (eval-top-in env "invoke \"shell\" H{ \"cmd\" \"echo hi\" }")
        "RB_ALLOW_SHELL=1 压过工作区开关")
    (is= 0 (run-in-exit env "flag-set true \"allow-shell\""))
    (os/setenv "RB_ALLOW_SHELL" "0")
    (is= 60 (run-in-exit env "invoke \"shell\" H{ \"cmd\" \"echo hi\" }")
        "RB_ALLOW_SHELL=0 压过工作区开关")
    (os/setenv "RB_ALLOW_SHELL" nil)))

(deftest "D-61：file 工具也守沙箱（越界 → 60）"
  (fn []
    (def env (new-ws))
    (is= 60 (run-in-exit env "invoke \"edit\" H{ \"path\" \"/etc/hostname\" \"old\" \"a\" \"new\" \"b\" }"))
    (is= 60 (run-in-exit env "invoke \"glob\" H{ \"pattern\" \"*\" \"dir\" \"/etc\" }"))))
