# tools/core-only-check.janet —— 附录 D 验收：剔除 cap/ 后核心仍可独立工作
#
# 用法：janet tools/core-only-check.janet build/core-only/rb-bundle.janet

(def path (last (dyn :args)))
(when (nil? path)
  (eprintf "用法：janet tools/core-only-check.janet <bundle.janet>\n")
  (os/exit 2))

(def env (curenv))
(each form (parse-all (slurp path))
  (eval form env))

(defn fail [msg]
  (eprintf "core-only: 失败：%s\n" msg)
  (os/exit 1))

(defn stack-of [src]
  (def r (rb/run-source src "core-only"))
  (if (r :ok)
    (tuple ;(r :stack))
    [:__error__ (rb/error-msg (r :error))]))

(when (rb/cap? :json/encode)
  (fail "cap/json 未被剔除"))

# 主脊：切词 → 递归反转 → 换名 → 栈原语
(when (not (deep= ["ab"] (stack-of "take 2 \"abcde\"")))
  (fail (string "主脊不可用：" (string/format "%q" (stack-of "take 2 \"abcde\"")))))

# 定义行（元层，不参与镜像）
(when (not (deep= [10] (stack-of "dbl : [ * 2 ]\ndbl 5")))
  (fail "定义行不可用"))

# 引号 + 组合子
(when (not (deep= [42] (stack-of "apply [ * 2 ] 21")))
  (fail "引号/apply 不可用"))

# 转译产物仍可 dump
(when (not= "(do (rb/push \"abcde\") (rb/push 2) (rb/take))"
           ((rb/compile-source "take 2 \"abcde\"") :code))
  (fail "转译产物与 REQ-31 不符"))

(print "core-only: 通过（核心可独立装载并完成主脊）")
