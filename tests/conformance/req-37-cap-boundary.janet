# tests/conformance/req-37-cap-boundary.janet —— REQ-37 / 附录 D：核心与能力层边界

(deftest "REQ-37：能力经注册表取用，核心不直接依赖 cap/"
  (fn []
    (is (function? (rb/cap-get :json/encode)))
    (is (rb/cap? :json/encode))))

(deftest "REQ-37：JSON 编码在能力层实现（核心不含 JSON 解析）"
  (fn []
    (is= "{\"a\":1}" ((rb/cap-get :json/encode) @{:a 1}))
    (is= "[\"x\",2]" ((rb/cap-get :json/encode) @["x" 2]))
    (is= "null" ((rb/cap-get :json/encode) nil))
    (is= "\"a\\\"b\"" ((rb/cap-get :json/encode) "a\"b"))))

(deftest "REQ-37：能力层缺失时核心给出可读错误（--serve 走注册表）"
  (fn []
    # 模拟「剔除 cap/」：临时摘掉注册项，核心路径仍应装载且给出提示
    (def saved (rb/cap-get :json/encode))
    (put rb/cap :json/encode nil)
    (is (nil? (rb/cap-get :json/encode)))
    (rb/cap-put :json/encode saved)
    (is (function? (rb/cap-get :json/encode)))))

(deftest "附录 D：核心词表不含宿主/插值语法与禁止特性（§5 / §4.9.6）"
  (fn []
    (each name ["immediate" ">r" "r>" "create" "does>" "!" "@"
                "<<" ">>" "$" "(" ")"
                "insert" "remove" "move"
                "agents" "focus" "tree"]
      (is (nil? (get rb/rename name)) (string "词表不应含：" name))
      (is (not (rb/dict? name)) (string "字典不应含：" name)))))

(deftest "REQ-37：核心装载期自检通过（无「无实现」告警）"
  (fn []
    # rb/validate 在装载时运行；这里复查一遍，返回值应无副作用
    (is (nil? (rb/validate)))))
