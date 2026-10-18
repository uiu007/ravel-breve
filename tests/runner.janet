# tests/runner.janet —— 测试装配与运行（编译于内核装载之后）
#
# 测试文件是**普通 form 文件**（不是模块）：直接使用 deftest / is= /
# eval-stack 等 harness 名字，不需要 import。

(rb-load-forms "tests/harness.janet")

(each dir ["tests/unit" "tests/conformance"]
  (each f (sort (os/dir dir))
    (when (string/has-suffix? ".janet" f)
      (rb-load-forms (string dir "/" f)))))

(var passed 0)
(each [name body] harness-tests
  (put harness-current :name name)
  (def before (length harness-fails))
  (def [ok err] (protect (body)))
  (if (not ok)
    (array/push harness-fails [name :exception (rb/error-msg err)])
    (when (= before (length harness-fails))
      (++ passed))))

(print (string "测试：" (length harness-tests)
               "  通过：" passed
               "  失败：" (length harness-fails)))
(each [name kind msg] harness-fails
  (printf "  ✗ %s [%s] %s\n" name kind msg))

(os/exit (if (empty? harness-fails) 0 1))
