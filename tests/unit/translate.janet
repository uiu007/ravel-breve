# tests/unit/translate.janet —— 转译单元测试（REQ-01 / REQ-02 / REQ-31）

(deftest "转译：镜像产物与规格 REQ-31 例一致"
  (fn []
    (is= "(do (rb/push \"abcde\") (rb/push 2) (rb/take))"
         (translated "take 2 \"abcde\""))))

(deftest "转译：算术按「左 = 栈顶 = 先消费」重排"
  (fn []
    (is= "(do (rb/push 3) (rb/push 5) (rb/sub))"
         (translated "- 5 3"))))

(deftest "转译：字面量 true/false/nil"
  (fn []
    (is= "(do (rb/push true))" (translated "true"))
    (is= "(do (rb/push nil))" (translated "nil"))))

(deftest "转译：引号块压栈即数据，内容递归反转（REQ-03/REQ-32）"
  (fn []
    (is= "(do (rb/quot (fn [] (do (rb/push 2) (rb/mul)))))"
         (translated "[ * 2 ]"))
    # 块内多语句：语句之间保持书写序，语句内部各自反转
    (is= "(do (rb/quot (fn [] (do (rb/pop) (rb/push 1) (rb/push 2) (rb/mul)))))"
         (translated "[ 1 pop\n* 2 ]"))))

(deftest "转译：定义行是元层，不参与镜像（REQ-33/REQ-34）"
  (fn []
    (def code (translated "dbl : [ * 2 ]"))
    (is (string/has-prefix? "(do (rb/define-word \"dbl\"" code))
    (is (string/find "(rb/push 2) (rb/mul)" code))))

(deftest "转译：未知词在转译期即报错（退出码 20）"
  (fn []
    (is= 20 (eval-exit "nope 1"))))

(deftest "转译：产物是可解析的宿主序（REQ-31 可 dump）"
  (fn []
    (each src ["take 2 \"abcde\""
               "- 5 3"
               "double : [ * 2 ]"
               "apply [ * 2 ] 21"
               "1 2\n+ 3"]
      (is (not (nil? (parse (translated src))))
          (string "无法解析：" src)))))
