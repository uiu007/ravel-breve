# tests/conformance/req-10-session-polymorphism.janet —— REQ-10 会话复用 L1 词
#
# REQ-10：`Session` 不另设编辑词表；`take` / `drop` / `at` / `reverse` / `sort` /
#         `map` … 直接作用于 `Session`，一律纯函数、返回**新** Session。
# REQ-06：`Session` = list Utter；`Utter` = @{:role :content}。
#
# 本测试在 M2 用「Utter 的 array」构造 Session（M3 的 `append` 落地后同构）。

(defn session-of
  "用 L1 的 `,` 拼出一个两元素 Session。"
  []
  (eval-top ", say \"hi\" say \"there\""))

(deftest "REQ-06：Utter 的 array 即 Session"
  (fn []
    (def s (session-of))
    (is (array? s))
    (is= 2 (length s))
    (is= "hi" (get (s 0) :content))
    (is= "there" (get (s 1) :content))))

(deftest "REQ-10：at / len"
  (fn []
    (is= "hi" (get (eval-top "at 0 , say \"hi\" say \"there\"") :content))
    (is= 2 (eval-top "len , say \"hi\" say \"there\""))))

(deftest "REQ-10：take / drop 返回新 Session"
  (fn []
    (def one (eval-top "take 1 , say \"hi\" say \"there\""))
    (is (array? one))
    (is= 1 (length one))
    (is= "hi" (get (one 0) :content))
    (def rest (eval-top "drop 1 , say \"hi\" say \"there\""))
    (is (array? rest))
    (is= 1 (length rest))
    (is= "there" (get (rest 0) :content))))

(deftest "REQ-10：reverse 返回新 Session"
  (fn []
    (def s (eval-top "reverse , say \"hi\" say \"there\""))
    (is (array? s))
    (is= "there" (get (s 0) :content))
    (is= "hi" (get (s 1) :content))))

(deftest "REQ-10：map 作用于每个 Utter"
  (fn []
    (is= (tuple (array "hi" "there"))
         (eval-stack "map [ Content ] , say \"hi\" say \"there\""))))

(deftest "REQ-10：纯函数 —— 原 Session 不被改动"
  (fn []
    (def s (session-of))
    (def before (length s))
    (eval-top "take 1 , say \"hi\" say \"there\"")
    (is= before (length s))))

(deftest "REQ-10：Session 上不得出现会话编辑词（负面）"
  (fn []
    (each w ["insert" "remove" "move"]
      (is= 20 (eval-exit (string w " 1"))))))
