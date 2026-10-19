# tests/conformance/req-06-07-types.janet —— REQ-06 / REQ-07 类型
#
# REQ-06 结构类型：String / Utter / Session = list Utter / Stream / Json。
# REQ-07 包装类型：Head / Endpoint / Path / Event / Workspace（Ws 为语法糖）。
#
# 本测试只覆盖 M2 已落地的部分（String / Utter / Session / Json）；
# Stream 在 M3、Workspace 在 M4，届时本文件扩充。

(deftest "REQ-06：String 是宿主 string"
  (fn []
    (is (string? (eval-top "\"abc\"")))
    (is (string? (eval-top "to-string 42")))))

(deftest "REQ-06：Utter = @{:role :content}"
  (fn []
    (def u (eval-top "say \"hi\""))
    (is (table? u))
    (is= "user" (get u :role))
    (is= "hi" (get u :content))
    (is= 2 (length u))))

(deftest "REQ-06：Session = list Utter（array）"
  (fn []
    (def s (eval-top ", say \"a\" say \"b\""))
    (is (array? s))
    (each u s
      (is (table? u))
      (is (string? (get u :role)))
      (is (string? (get u :content))))))

(deftest "REQ-06：Json = 宿主 table / array / 标量"
  (fn []
    (is (table? (eval-top `from-json "{\"a\":1}"`)))
    (is (array? (eval-top `from-json "[1]"`)))
    (is (string? (eval-top `from-json "\"s\""`)))
    (is (number? (eval-top `from-json "1"`)))
    (is (boolean? (eval-top `from-json "true"`)))
    (is (nil? (eval-top `from-json "null"`)))))

(deftest "REQ-06：核心不静态依赖 cap/（REQ-37 交叉）"
  (fn []
    # 能力层注册表是取用 JSON 的唯一通道
    (is (function? (rb/cap-get :json/encode)))
    (is (function? (rb/cap-get :json/decode)))
    (is (nil? (rb/cap-get :no/such-cap)))))

(deftest "REQ-07：包装类型名（Head/Endpoint/Path/Event/Workspace）不得是方言词"
  (fn []
    (each w ["Head" "Endpoint" "Path" "Event" "Workspace" "Ws"]
      (is= 20 (eval-exit (string w " 1"))))))
