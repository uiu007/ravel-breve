# tests/run.janet —— 测试引导（make test-unit）
#
# 注意编译期语义：janet 在**编译期**解析符号，所以本文件在装载内核 bundle
# 之前不能引用任何 rb/* 。因此这里只做引导：
#   逐 form 装载 build/rb-bundle.janet → 再逐 form 装载 tests/runner.janet。
# 逐 form 装载与宿主 janet_dobytes 语义一致（宿主也是逐 form 编译执行的）。

(defn rb-load-forms
  [path]
  (def env (curenv))
  (each form (parse-all (slurp path))
    (eval form env))
  nil)

(rb-load-forms "build/rb-bundle.janet")
(rb-load-forms "tests/runner.janet")
