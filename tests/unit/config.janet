# tests/unit/config.janet —— 工作区级 provider 配置（D-54：llm / llm-get / llm-set）
#
# 优先级：工作区配置 > 环境变量 > 内置缺省（解析在 cap/config.janet）。
# 测试引导已设 RB_LLM=mock，所以「环境变量这一层」也有确定值。

(deftest "D-54：llm 给出活表，llm-set 写、at 读"
  (fn []
    (def env (new-ws))
    (def cfg ((env :rb-ws) :config))
    (is= 0 (length cfg) "新工作区没有显式配置")
    (run-in env "llm-set \"mock\" \"provider\"")
    (run-in env "llm-set \"tiny\" \"model\"")
    (is= "mock" (get cfg "provider"))
    (is= "tiny" (get cfg "model"))
    # 活表：方言里 at 读到刚写的值（写的是同一张表，不是副本）
    (is= "tiny" (eval-top-in env "at \"model\" llm"))))

(deftest "D-54：配置项名归一化（方言里没有关键字字面量，关键字只从宿主侧来）"
  (fn []
    (is= "model" (rb/config-normalize "model"))
    (is= "model" (rb/config-normalize :model))
    (is= 31 (try (rb/config-normalize 5) ([e] (rb/error-code e))))))

(deftest "D-54：llm-get 给生效值（工作区配置 > 环境变量 > 缺省）"
  (fn []
    (def env (new-ws))
    # 环境变量层：RB_LLM=mock（测试引导设的）
    (is= "mock" (eval-top-in env "llm-get \"provider\""))
    # 缺省层：模型名与上限有内置缺省
    (is (string? (eval-top-in env "llm-get \"model\"")))
    (is= 512 (eval-top-in env "llm-get \"max-tokens\""))
    # 工作区配置层覆盖环境变量
    (run-in env "llm-set \"nvidia\" \"provider\"")
    (is= "nvidia" (eval-top-in env "llm-get \"provider\""))
    # 写 nil = 删除该项 → 回落环境变量
    (run-in env "llm-set nil \"provider\"")
    (is= "mock" (eval-top-in env "llm-get \"provider\""))
    (is= 0 (length ((env :rb-ws) :config)) "删除后不留空键")))

(deftest "D-54：配置项白名单与密钥禁令"
  (fn []
    (def env (new-ws))
    # 拼错 → 31（静默无效比报错更糟）
    (is= 31 (run-in-exit env "llm-set \"x\" \"provier\""))
    # 密钥不是工作区配置项 → 60（不许写进快照/日志）
    (is= 60 (run-in-exit env "llm-set \"sk-xxx\" \"key\""))
    # 类型错：配置项名不是字符串
    (is= 31 (run-in-exit env "llm-set \"x\" 5"))))

(deftest "D-54：provider 名字受校验"
  (fn []
    (def env (new-ws))
    (run-in env "llm-set \"nvidia\" \"provider\"")
    (is= "nvidia" (eval-top-in env "llm-get \"provider\""))
    (run-in env "llm-set \"别的\" \"provider\"")
    (is= 31 (run-in-exit env "llm-get \"provider\""))))

(deftest "D-54：配置随快照保存与载入"
  (fn []
    (def env (new-ws))
    (def ws (env :rb-ws))
    (run-in env "llm-set \"nvidia\" \"provider\"")
    (run-in env "llm-set \"tiny\" \"model\"")
    (def snap (rb/store-decode (rb/store-snapshot ws @[])))
    (is= @{"provider" "nvidia" "model" "tiny"} (snap "llm"))
    # 载入端：写回工作区配置
    (def env2 (new-ws))
    (rb/store-config-apply! (env2 :rb-ws) (snap "llm"))
    (def cfg2 ((env2 :rb-ws) :config))
    (is= "nvidia" (get cfg2 "provider"))
    (is= "tiny" (get cfg2 "model"))
    (is= "tiny" (eval-top-in env2 "llm-get \"model\""))))

(deftest "D-55：一次求值失败 → 没有栈效果（回滚到求值前）"
  (fn []
    (def env (new-ws))
    # 空栈上执行 `+ 1`：先压 1，再 `+` 下溢——不许把半截操作数留在栈上
    (is= 30 (run-in-exit env "+ 1"))
    (is= () (tup (env :rb-stack)) "失败的一轮没有栈效果")
    # 有多步时同样整体回滚（前两步的 pop 也退回）
    (is= 0 (run-in-exit env "1\n2\n3"))
    (is= 30 (run-in-exit env "pop\npop\npop\npop"))
    (is= '(1 2 3) (tup (env :rb-stack)))
    # 报错之后照常工作（REPL / --serve 不必重启）
    (is= 0 (run-in-exit env "+ 3 4"))
    (is= '(1 2 3 7) (tup (env :rb-stack)))))
