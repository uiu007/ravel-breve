# tests/unit/words-l5.janet —— L5 控制（附录 A / REQ-32）
#
# 全部是组合子；书写序即自然阅读序：
#   if cond [ 体 ] [ 体 ]   when cond [ 体 ]   loop n [ 体 ]
#   while [ 条件 ] [ 体 ]   try [ 体 ] [ 处理 ]   recover [ 体 ] [ 处理 ]

(deftest "L5：if"
  (fn []
    (is= [1] (eval-stack "if true [ 1 ] [ 2 ]"))
    (is= [2] (eval-stack "if false [ 1 ] [ 2 ]"))
    # 条件在左、分支在右，读作 if 条件 [ 真 ] [ 假 ]
    (is= ["big"] (eval-stack "if > 5 3 [ \"big\" ] [ \"small\" ]"))
    (is= ["small"] (eval-stack "if > 3 5 [ \"big\" ] [ \"small\" ]"))))

(deftest "L5：when / unless"
  (fn []
    (is= [7] (eval-stack "when true [ 7 ]"))
    (is= [] (eval-stack "when false [ 7 ]"))
    (is= [7] (eval-stack "unless false [ 7 ]"))
    (is= [] (eval-stack "unless true [ 7 ]"))))

(deftest "L5：loop"
  (fn []
    (is= [1 1 1] (eval-stack "loop 3 [ 1 ]"))
    (is= [] (eval-stack "loop 0 [ 1 ]"))
    (is= [3] (eval-stack "sum { 1 1 1 }"))))

(deftest "L5：while（条件引号须自己保留计数）"
  (fn []
    # 栈上**已有**的值总是靠后的操作数（附录 A 推论），且比较是二元的，
    # 所以计数式循环要 `dup` 保留计数、`swap` 把它提到栈顶。
    # 读法：`[ < swap 3 dup ]` 执行序为 dup → 3 → swap → < ，即「保留 c，c < 3」。
    (def cond-q "[ < swap 3 dup ]")
    (def body-q "[ + 1 ]")
    (is (eval-ok? (string "0\nwhile " cond-q " " body-q)))
    (is= [3] (eval-stack (string "0\nwhile " cond-q " " body-q)))
    # 条件一开始就不成立时不执行体
    (is= [5] (eval-stack (string "5\nwhile " cond-q " " body-q)))
    # 条件引号不留真值 → 栈下溢（30）
    (is= 30 (eval-exit "1\nwhile [ ] [ pop ]"))))

(deftest "L5：try 捕获错误，错误值入栈交给处理引号"
  (fn []
    (is= ["boom"] (eval-stack "try [ fail \"boom\" ] [ to-string ]"))
    (is= [42] (eval-stack "try [ 42 ] [ to-string ]"))
    # try 保留体引号的栈效果
    (is= [7 "boom"] (eval-stack "try [ 7\nfail \"boom\" ] [ to-string ]"))))

(deftest "L5：recover 失败时回滚栈深度"
  (fn []
    # 体引号先压 7 再失败；recover 回滚，栈上只剩错误消息
    (is= ["boom"] (eval-stack "recover [ 7\nfail \"boom\" ] [ to-string ]"))))

(deftest "L5：retry"
  (fn []
    (is= [1] (eval-stack "retry [ 1 ] 2"))
    (is (not (eval-ok? "retry [ fail \"x\" ] 2")))
    (is= 31 (eval-exit "retry 5 2"))))
