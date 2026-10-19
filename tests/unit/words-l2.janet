# tests/unit/words-l2.janet —— L2 消息与 JSON（REQ-06 / 附录 A / 附录 D）

(deftest "L2：say 造出 Utter（缺省 Role = user）"
  (fn []
    (def u (eval-top "say \"hi\""))
    (is (table? u))
    (is= "user" (get u :role))
    (is= "hi" (get u :content))))

(deftest "L2：Utter / Role / Content"
  (fn []
    (is= ["assistant"] (eval-stack "Role Utter \"assistant\" \"yo\""))
    (is= ["yo"] (eval-stack "Content Utter \"assistant\" \"yo\""))
    (is= ["user"] (eval-stack "Role say \"hi\""))))

(deftest "L2：to-json 经能力层（核心不含 JSON 实现）"
  (fn []
    (is= ["{\"a\":1}"] (eval-stack "to-json H{ \"a\" 1 }"))
    (is= ["[1,2]"] (eval-stack "to-json { 1 2 }"))
    (is= ["null"] (eval-stack "to-json nil"))
    (is= ["true"] (eval-stack "to-json true"))))

(deftest "L2：from-json"
  (fn []
    (is= (tuple @{"a" 1}) (eval-stack `from-json "{\"a\":1}"`))
    (is= (tuple (array 1 2)) (eval-stack `from-json "[1,2]"`))
    (is= (tuple @{"a" (array 1)})
         (eval-stack `from-json "{\"a\":[1]}"`))
    (is= [true] (eval-stack `from-json "true"`))
    (is= [nil] (eval-stack `from-json "null"`))))

(deftest "L2：JSON 往返"
  (fn []
    (is= (tuple (array 1 2)) (eval-stack "from-json to-json { 1 2 }"))
    (is= (tuple @{"a" "b"}) (eval-stack "from-json to-json H{ \"a\" \"b\" }"))))

(deftest "L2：非法 JSON → 运行时报错"
  (fn []
    (is (not (eval-ok? `from-json "{oops}"`)))
    (is (not (eval-ok? `from-json "[1,2"`)))))
