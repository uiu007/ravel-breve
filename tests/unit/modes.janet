# tests/unit/modes.janet —— D-59 处理流程（模式）层
#
# 这一层要守住的两条性质：
#   ① 模式 ⇄ 钩子 是**双向**的：`mode` 装进去的，`mode-of` 能原样取出来；
#   ② 历史标记默认全开，且可以用开关一项一项关掉。

(deftest "D-59：mode-of 导出 default 模式与预置逐项相等（往返）"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (def preset (rb/mode-get "default"))
    (def cap (val-in env rb/mode-capture))
    (is= "default" (cap :name) "名字沿用当前模式")
    (is= preset cap "整个模式表（含钩子对象、开关、工具）deep= 相等")
    (is= 8 (length (keys (cap :hooks))) "8 个事件齐全（未声明 = 空数组，形状规范）")
    (is= 1 (length (get (cap :hooks) "@RoundDone")))
    (is= 1 (length (get (cap :hooks) "@Toolcall")))
    (is= 0 (length (get (cap :hooks) "@Chunk")))))

(deftest "D-59：mode \"ptc\" 往返相等，且带 eval 工具与系统提示"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (is= 0 (run-in-exit env "mode \"ptc\"") "切换成功")
    (is= "ptc" (ws :mode))
    (is (not (nil? (ws :mode-prompt))) "ptc 有系统提示")
    (is (not (nil? (val-in env (fn [] (rb/tool-get "eval"))))) "ptc 装了 eval 工具")
    (is= (rb/mode-get "ptc") (val-in env rb/mode-capture) "往返相等")))

(deftest "D-59：PTC 的 eval 工具执行程序并返回栈顶"
  (fn []
    (def env (new-ws))
    (is= 0 (run-in-exit env "mode \"ptc\""))
    (is= 3 (val-in env (fn [] (rb/tool-run "eval" @{"src" "+ 1 2"})))
        "程序 = ravel 源，结果 = 栈顶")
    (is= "ab" (val-in env (fn [] (rb/tool-run "eval" @{"src" "take 2 \"abcde\""})))
        "词与字面量都能用")
    (is= 0 (length (env :rb-stack)) "工具执行完栈回到原深度（不留中间量）")
    (is= 0 (length ((env :rb-ws) :round)) "nested 求值不进本轮列表")
    # val-in 把子 fiber 的错误**返回**（不抛），所以直接看错误值里的码
    (def p (val-in env (fn [] (rb/tool-run "eval" @{"src" "pop pop"}))))
    (is= 60 (get p :rb-code) "程序失败 → 60（编排层），不炸掉外层")
    (is= 0 (length (env :rb-stack)) "失败程序也不留栈效果（D-55）")))

(deftest "D-59：未知模式 → 20；模式值类型错 → 31"
  (fn []
    (def env (new-ws))
    (is= 20 (run-in-exit env "mode \"nope\""))
    (is= 31 (run-in-exit env "mode 42"))))

(deftest "D-59：modes 列出预制模式（升序元组）"
  (fn []
    (def env (new-ws))
    (is= ["default" "ptc"] (tup (eval-top-in env "modes")))))

(deftest "D-59：切回 default 会撤掉 ptc 声明的工具（模式不互相污染）"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (is= 0 (run-in-exit env "mode \"ptc\""))
    (is (not (nil? (val-in env (fn [] (rb/tool-get "eval"))))))
    (is= 0 (run-in-exit env "mode \"default\""))
    (is (nil? (val-in env (fn [] (rb/tool-get "eval")))) "default 没有声明 eval → 撤掉")
    (is (nil? (ws :mode-prompt)) "default 不注入系统提示")))

(deftest "D-59：用户 @on 出来的钩子能被 mode-of 收成模式，再 mode 回去"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (is= 0 (run-in-exit env "@on @Chunk [ ]"))
    (def snapshot (val-in env rb/mode-capture))
    (is= 1 (length (get (snapshot :hooks) "@Chunk")) "捕获到用户钩子")
    (is= 0 (run-in-exit env "mode \"ptc\""))      # 换模式会整体替换钩子
    (is= 0 (length (get (ws :hooks) "@Chunk")))
    (val-in env (fn [] (rb/mode-apply! snapshot)))   # 再装回用户模式
    (is= 1 (length (get (ws :hooks) "@Chunk")) "用户的钩子回来了")
    (is= "default" (ws :mode) "模式名也回来了")))

(deftest "D-59：历史标记默认全开（turn / from / mode）"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (run-in env "agent \"c\" { }")
    (def a ((ws :agents) 0))
    (def u (val-in env (fn [] (rb/agent-append! a @{:role "user" :content "x"}) (in (a :session) 0))))
    (is= 1 (u :turn) "第 1 轮")
    (is= "c" (u :from) "来源 agent 标签")
    (is= "default" (u :mode) "产生它的模式")
    (val-in env (fn [] (rb/agent-append! a @{:role "assistant" :content "y"})))
    (is= 2 (((a :session) 1) :turn) "第 2 轮")))

(deftest "D-59：开关关掉后不再打对应标记"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (is= 0 (run-in-exit env "flag-set false \"history-turn\""))
    (is= false (eval-top-in env "flag \"history-turn\""))
    (run-in env "agent \"c\" { }")
    (def a ((ws :agents) 0))
    (def u (val-in env (fn [] (rb/agent-append! a @{:role "user" :content "x"}) (in (a :session) 0))))
    (is= nil (u :turn) "轮次标记被关掉")
    (is= "c" (u :from) "其余标记不受影响")
    (is= "default" (u :mode))))

(deftest "D-59：开关默认值可读，未知开关 → nil；非布尔值 → 31"
  (fn []
    (def env (new-ws))
    (is= true (eval-top-in env "flag \"history-origin\""))
    (is= true (eval-top-in env "flag \"history-mode\""))
    (is= nil (eval-top-in env "flag \"nope\""))
    (is= 31 (run-in-exit env "flag-set 42 \"history-mode\""))))

(deftest "D-59：模式提示只进请求（前置 system），不进会话历史"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (is= 0 (run-in-exit env "mode \"ptc\""))
    (var seen nil)
    (def orig (rb/cap-get :llm/chat))
    (rb/cap-put :llm/chat
      (fn [messages opts]
        (set seen messages)
        (var sent false)
        (fn [] (if sent nil (do (set sent true) "ok")))))
    (def r (run-in env "agent \"c\" { }\nsend say \"hi\"\ndrain"))
    (rb/cap-put :llm/chat orig)
    (is (r :ok) (string "应成功：" (if (r :ok) "" (rb/error-msg (r :error)))))
    (is= "system" ((seen 0) :role) "请求首条是 system")
    (is (string/find "PTC" ((seen 0) :content)) "内容就是模式提示")
    (def a (in (ws :agents) 0))
    (is= 2 (length (a :session)) "会话仍只有 user + assistant")
    (is= "user" (((a :session) 0) :role) "会话首条仍是用户消息")))

(deftest "D-59：模式的自省名词（mode-name / mode-prompt / mode-tools）"
  (fn []
    (def env (new-ws))
    (is= "default" (eval-top-in env "mode-of\nmode-name"))
    (is= nil (eval-top-in env "mode-of\nmode-prompt") "default 无提示")
    # D-61：缺省工作区就有能力层装好的四个工具
    (is= (tup ["edit" "glob" "grep" "shell"]) (tup (eval-top-in env "mode-of\nmode-tools")))
    (is= 0 (run-in-exit env "mode \"ptc\""))
    (is= "ptc" (eval-top-in env "mode-of\nmode-name"))
    (is (string/find "PTC" (eval-top-in env "mode-of\nmode-prompt")))
    (is= (tup ["eval"]) (tup (eval-top-in env "mode-of\nmode-tools")))))
