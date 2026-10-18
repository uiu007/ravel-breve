# tests/conformance/req-05-definition.janet —— REQ-05 定义行 / REQ-33 装载期注册 / REQ-34 元层

(deftest "REQ-05：定义行本身无栈效果"
  (fn []
    (is= [] (eval-stack "c5a : [ * 2 ]"))))

(deftest "REQ-05：定义后可用（c5b 5 → 10）"
  (fn []
    (is= [10] (eval-stack "c5b : [ * 2 ]\nc5b 5"))))

(deftest "REQ-33：定义在装载期（转译期）即注册进字典"
  (fn []
    (rb/dict-declare "__probe_word" "(fn [] nil)")
    (is (rb/dict? "__probe_word"))))

(deftest "REQ-33：后续语句可在转译期解析到前面定义的词"
  (fn []
    (is= [4] (eval-stack "c5c : [ + 2 ]\nc5c 2"))))

(deftest "REQ-34：定义行是元层，不参与镜像（名字在前，体在块中）"
  (fn []
    (is (eval-ok? "c5d : [ * 2 ]"))
    (is= 20 (eval-exit ": [ * 2 ] c5d"))))

(deftest "REQ-35：字典可 see/doc 查询"
  (fn []
    (eval-stack "c5e : [ * 2 ]")
    (def e (get rb/dict "c5e"))
    (is (not (nil? e)))
    (is (string/find "(rb/push 2) (rb/mul)" (e :src)))
    (is (function? (e :body)))))

(deftest "REQ-35：重定义覆盖（同一名字二次定义后体为新体）"
  (fn []
    (is= [8] (eval-stack "c5f : [ * 2 ]\nc5f 4"))
    (is= [16] (eval-stack "c5f : [ * 4 ]\nc5f 4"))))

(deftest "REQ-05：定义体内的未知词在转译期报 20"
  (fn []
    (is= 20 (eval-exit "c5g : [ nope ]"))))

(deftest "REQ-05：= 专表相等，不是定义符（: 与 = 分工）"
  (fn []
    (is= [true] (eval-stack "= 3 3"))
    (is= [false] (eval-stack "= 3 4"))))
