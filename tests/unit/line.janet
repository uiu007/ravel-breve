# tests/unit/line.janet —— REPL 行编辑器（D-57）
#
# 键位是**数据**（rb/line-emacs-keys 等），编辑循环接受注入的键源
# （`rb/line-edit` 的第三个参数），所以这里不需要终端、不需要 pty：
# 直接喂键码，检查编辑结果与模式切换。

(defn line-codes
  "字符串 → 键码数组（按码位：CJK 也是一个键）。"
  [s]
  (rb/line-cps-of s))

(defn line-run
  "喂一串键码给编辑器，返回结果行（nil = EOF / 取消）。

  末尾不是 Enter 时自动补一个（否则键源耗尽 = EOF，会得到 nil）。"
  [codes &opt hist]
  (def all (if (and (> (length codes) 0) (not= (last codes) 13))
             (array/concat @[] codes @[13])
             codes))
  (var i 0)
  (rb/line-edit "t> " (or hist @[])
                (fn []
                  (def n (length all))
                  (def k (if (< i n) (all i) -1))
                  (set i (+ i 1))
                  k)))

(defn line-ed
  "把关键字序列（:ctrl-a 等）和字符串混着喂。"
  [& parts]
  (def codes @[])
  (each p parts
    (if (string? p)
      (each c (line-codes p) (array/push codes c))
      (array/push codes
                  (case p
                    :esc -2 :up -101 :down -102 :right -103 :left -104
                    :home -105 :end -106 :delete -107
                    :word-right -108 :word-left -109
                    :ctrl-a 1 :ctrl-b 2 :ctrl-c 3 :ctrl-d 4 :ctrl-e 5 :ctrl-f 6
                    :tab 9 :enter 13 :ctrl-k 11 :ctrl-l 12
                    :ctrl-n 14 :ctrl-p 16 :ctrl-u 21 :ctrl-w 23 :backspace 127
                    (error (string "测试里没有这个键：" p))))))
  codes)

# ---- 键码表 --------------------------------------------------------------

(deftest "行编辑：键码 → 关键字"
  (fn []
    (is= :ctrl-a (rb/line-key 1))
    (is= :enter (rb/line-key 13))
    (is= :enter (rb/line-key 10))
    (is= :backspace (rb/line-key 127))
    (is= :up (rb/line-key -101))
    (is= :esc (rb/line-key -2))
    (is= :eof (rb/line-key -1))
    (is= :unknown (rb/line-key -3))
    # 可打印码位原样透出（含 CJK）
    (is= 97 (rb/line-key 97))
    (is= 0x4e2d (rb/line-key 0x4e2d))))

# ---- Emacs 键位 ----------------------------------------------------------

(deftest "行编辑：Emacs 打字 + Enter 提交"
  (fn []
    (is= "+ 1 2" (line-run (line-ed "+ 1 2" :enter)))))

(deftest "行编辑：C-a 回到行首、C-e 到行尾"
  (fn []
    (is= "Xabc" (line-run (line-ed "abc" :ctrl-a "X")))
    (is= "abcX" (line-run (line-ed "abc" :ctrl-a :ctrl-e "X")))))

(deftest "行编辑：C-b / C-f 逐字移动、方向键等价"
  (fn []
    (is= "aXbc" (line-run (line-ed "abc" :ctrl-a :ctrl-f "X")))
    (is= "aXbc" (line-run (line-ed "abc" :ctrl-a :right "X")))
    (is= "abXc" (line-run (line-ed "abc" :ctrl-a :right :right "X")))
    (is= "Xabc" (line-run (line-ed "abc" :ctrl-a :right :left "X")))))

(deftest "行编辑：C-k 删到行尾、C-u 删到行首"
  (fn []
    (is= "ab" (line-run (line-ed "abcdef" :ctrl-a :right :right :ctrl-k)))
    (is= "" (line-run (line-ed "abcdef" :ctrl-a :ctrl-k)))
    (is= "ef" (line-run (line-ed "abcdef" :ctrl-b :ctrl-b :ctrl-u)))))

(deftest "行编辑：C-w 删一个词、M-b/M-f 按词移动"
  (fn []
    (is= "+ 111 " (line-run (line-ed "+ 111 222" :ctrl-w)))
    (is= "+ 100 9200" (line-run (line-ed "+ 100 200" :word-left "9")))
    (is= "+ x100 200 " (line-run (line-ed "+ 100 200 " :ctrl-a :word-right "x")))
    # 中文也算词字符（只在空白处切）
    (is= "1 " (line-run (line-ed "1 中文" :ctrl-w)))))

(deftest "行编辑：Backspace / Delete 按码位删（CJK 只删一个字）"
  (fn []
    (is= "ab" (line-run (line-ed "abc" :backspace)))
    (is= "ac" (line-run (line-ed "abc" :ctrl-a :right :delete)))
    (is= "" (line-run (line-ed "中" :backspace)))
    (is= "中文" (line-run (line-ed "中文字" :ctrl-a :end :backspace)))))

(deftest "行编辑：Tab 插两个空格"
  (fn []
    (is= "  x" (line-run (line-ed :tab "x")))))

(deftest "行编辑：EOF 与取消"
  (fn []
    (is= nil (line-run (line-ed :ctrl-d)))          # 空行 C-d = EOF
    (is= nil (line-run (line-ed :ctrl-c)))          # C-c = 取消
    (is= "b" (line-run (line-ed "ab" :ctrl-a :ctrl-d)))   # 非空行 C-d = 删字符
    (is= "abc" (line-run (line-ed "abc" :ctrl-e :ctrl-d))) # 行尾 C-d 什么也不删
    (is= nil (line-run (line-ed "rewrite" :ctrl-c)))      # 取消不返回值
    (is= nil (line-run @[]))))                            # 键源直接 EOF

(deftest "行编辑：历史（Up/Down），回到底部恢复未提交内容"
  (fn []
    (def hist @["+ 1 2" "+ 3 4"])
    (is= "+ 3 4" (line-run (line-ed :up :enter) hist))
    (is= "+ 1 2" (line-run (line-ed :up :up) hist))
    (is= "+ 3 4" (line-run (line-ed :up :up :down) hist))
    (is= "" (line-run (line-ed :up :up :down :down) hist))
    # 打了一半再翻历史，回来还在
    (is= "half" (line-run (line-ed "half" :up :down) hist))))

# ---- Vim 模式 ------------------------------------------------------------

(deftest "行编辑：Esc 进 Vim normal 模式（Emacs → normal → Emacs）"
  (fn []
    (def st (rb/line-state))
    (is= :emacs (st :mode))
    (rb/line-apply-key! st -2)
    (is= :vim-normal (st :mode))
    (rb/line-apply-key! st -2)
    (is= :emacs (st :mode))))

(deftest "行编辑：normal 下 i/a/I/A 进插入模式"
  (fn []
    (is= "X12" (line-run (line-ed "12" :esc "0" "i" "X" :esc)))
    (is= "1X2" (line-run (line-ed "12" :esc "0" "a" "X" :esc)))
    (is= "X12" (line-run (line-ed "12" :esc "0" :end "I" "X" :esc)))
    (is= "12X" (line-run (line-ed "12" :esc "0" "A" "X" :esc)))
    # 插入模式里 Esc 退回 normal（光标左移一格，同 Vim）
    (def st (rb/line-state))
    (rb/line-apply-key! st -2)
    (rb/line-apply-key! st 105)                     # i
    (is= :vim-insert (st :mode))
    (rb/line-apply-key! st -2)
    (is= :vim-normal (st :mode))))

(deftest "行编辑：normal 下 h/l/0/$/w/b 移动、字符不键入"
  (fn []
    (is= "Xab" (line-run (line-ed "ab" :esc "0" "i" "X" :esc)))
    # normal 下按字母不会插入（这里是 z）
    (is= "ab" (line-run (line-ed "ab" :esc "z" :enter)))
    (is= "abX" (line-run (line-ed "ab" :esc "$" "i" "X" :esc)))
    (is= "aXb" (line-run (line-ed "ab" :esc "0" "l" "i" "X" :esc)))
    (is= "aXb" (line-run (line-ed "ab" :esc "$" "h" "i" "X" :esc)))))

(deftest "行编辑：normal 下 x 删字、D 删到尾、dd 清行"
  (fn []
    (is= "bc" (line-run (line-ed "abc" :esc "0" "x")))
    (is= "" (line-run (line-ed "abc" :esc "0" "D")))
    (is= "a" (line-run (line-ed "abc" :esc "0" "l" "D")))
    (is= "" (line-run (line-ed "abc" :esc "d" "d")))
    # d 后面不是 d → 前缀作废，不删
    (is= "abc" (line-run (line-ed "abc" :esc "d" "z")))
    (is= "" (line-run (line-ed "abc" :esc "0" "x" "x" "x")))))

(deftest "行编辑：normal 下 u 撤销一步"
  (fn []
    (is= "abc" (line-run (line-ed "abc" :esc "0" "x" "u")))
    (is= "bc" (line-run (line-ed "abc" :esc "0" "x" "x" "u")))))

(deftest "行编辑：Vim 模式下 Enter 提交、C-c 取消"
  (fn []
    (is= "+ 1 2" (line-run (line-ed "+ 1 2" :esc :enter)))
    (is= "+ 1 2" (line-run (line-ed "+ 1 2" :esc "0" "i" :enter)))
    (is= nil (line-run (line-ed "junk" :esc :ctrl-c)))))

# ---- 显示与扩展点 --------------------------------------------------------

(deftest "行编辑：宽度（CJK 算两列）与 UTF-8 往返"
  (fn []
    (is= 3 (rb/line-width "abc"))
    (is= 4 (rb/line-width "中文"))
    (is= 4 (rb/line-width "a中b"))
    (is= "中a文" (rb/line-text (rb/line-cps-of "中a文")))
    (is= @[0x4e2d 97] (rb/line-cps-of "中a"))))

(deftest "行编辑：Vim 模式的提示符带模式标记（看得见才不误按）"
  (fn []
    (is= "r> " (rb/line-prompt "r> " :emacs))
    (is= "r> -- NORMAL -- " (rb/line-prompt "r> " :vim-normal))
    (is= "r> -- INSERT -- " (rb/line-prompt "r> " :vim-insert))))

(deftest "行编辑：键位表可扩展（加键不必改 rb/line.janet）"
  (fn []
    (put rb/line-emacs-keys :ctrl-l (fn [st] (rb/line-set! st (rb/line-cps-of "hi") 2) nil))
    (is= "hi" (line-run (line-ed :ctrl-l :enter)))
    # 还原
    (put rb/line-emacs-keys :ctrl-l (fn [st] nil))
    (is= "x" (line-run (line-ed "x" :ctrl-l :enter)))))

(deftest "行编辑：没有终端原语时退回行模式（裸 janet 也能装载）"
  (fn []
    (is (nil? rb/line-term))
    (is (not (rb/line-tty?)))
    (is (function? rb/line-reader))))
