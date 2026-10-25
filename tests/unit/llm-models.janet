# tests/unit/llm-models.janet —— D-65（自定义请求头）与 D-66（模型列表 / 自动配置）
#
# 全部离线：把 `:http/get-body` 换成假的，检查 URL / 头 / 解析与选择规则。

(def lm-fake-body
  "{\"object\":\"list\",\"data\":[{\"id\":\"a-flash\"},{\"id\":\"b-max\"},{\"id\":\"mockish\"}]}")

(defn lm-with-env
  "临时设一批环境变量，跑 body，最后还原（nil = 删除）。"
  [pairs body]
  (def saved @{})
  (each [k v] pairs
    (put saved k (os/getenv k))
    (os/setenv k v))
  (def r (protect (body)))
  (each [k v] pairs
    (os/setenv k (get saved k)))
  (if (get r 0) (get r 1) (error (get r 1))))

(defn lm-with-get
  "临时替换 `:http/get-body`；`fake` 收到 (url headers)，返回响应体字符串。"
  [fake body]
  (def old (rb/cap-get :http/get-body))
  (rb/cap-put :http/get-body fake)
  (def r (protect (body)))
  (rb/cap-put :http/get-body old)
  (if (get r 0) (get r 1) (error (get r 1))))

(deftest "D-65：自定义请求头：环境变量（K:v,K:v 与 JSON）与工作区表"
  (fn []
    (lm-with-env [["RB_HEADERS" nil]]
      (fn []
        (is= @{} (cap/headers) "没设就是空表")))
    (lm-with-env [["RB_HEADERS" "X-A:1, X-B: two"]]
      (fn []
        (is= @{"X-A" "1" "X-B" "two"} (cap/headers))
        (is= "two" (get (cap/headers) "X-B") "冒号后的空白被剪掉")))
    (lm-with-env [["RB_HEADERS" "{\"X-J\":\"1\"}"]]
      (fn []
        (is= @{"X-J" "1"} (cap/headers) "JSON 对象也认")))
    # 工作区配置优先于环境变量（D-54 的同一套优先级）
    (lm-with-env [["RB_HEADERS" "X-Env:1"]]
      (fn []
        (def env (new-ws))
        (val-in env
          (fn []
            (setdyn :rb-ws (env :rb-ws))
            (rb/config-set "headers" @{"X-Ws" "2"})
            (is= @{"X-Ws" "2"} (cap/headers))))))))

(deftest "D-65：headers 进白名单，llm-get/llm-set 走得通"
  (fn []
    (def env (new-ws))
    (is= 0 (run-in-exit env "llm-set H{ \"X-T\" \"9\" } \"headers\""))
    (is= @{"X-T" "9"} (eval-top-in env "llm-get \"headers\""))
    (is= @{"X-T" "9"} (eval-top-in env "at \"headers\" llm"))
    # 删掉就回落到环境变量/空
    (is= 0 (run-in-exit env "llm-set nil \"headers\""))
    (is= (tup []) (tup (keys (eval-top-in env "llm-get \"headers\""))))))

(deftest "D-65：自定义头覆盖内置同名项（Authorization / User-Agent 也能换）"
  (fn []
    (def base @{"Authorization" "Bearer k" "User-Agent" "ravel-breve/1.0j"})
    (lm-with-env [["RB_HEADERS" "User-Agent:mine/2"]]
      (fn []
        (def h (cap/merge-headers base))
        (is= "Bearer k" (get h "Authorization") "没覆盖的项保留")
        (is= "mine/2" (get h "User-Agent") "同名的被覆盖")))))

(deftest "D-66：基址 = 端点去掉 /chat/completions"
  (fn []
    (def env (new-ws))
    (is= 0 (run-in-exit env "llm-set \"https://x.test/v1/chat/completions\" \"endpoint\""))
    (val-in env
      (fn []
        (setdyn :rb-ws (env :rb-ws))
        (is= "https://x.test/v1" (cap/llm-base-url))))
    (is= 0 (run-in-exit env "llm-set \"https://x.test/v1\" \"endpoint\""))
    (val-in env
      (fn []
        (setdyn :rb-ws (env :rb-ws))
        (is= "https://x.test/v1" (cap/llm-base-url) "没有该后缀就原样")))))

(deftest "D-66：偏好顺序来自 RB_MODEL_PREFER，否则用 provider 内置"
  (fn []
    (def env (new-ws))
    (is= 0 (run-in-exit env "llm-set \"opencode\" \"provider\""))
    (val-in env
      (fn []
        (setdyn :rb-ws (env :rb-ws))
        # 没设 RB_MODEL_PREFER → provider 内置偏好
        (lm-with-env [["RB_MODEL_PREFER" nil]]
          (fn []
            (is= "deepseek-v4.1-flash" ((cap/model-prefer) 0))))
        # 设了 → 逗号分隔，按序
        (lm-with-env [["RB_MODEL_PREFER" "z, y"]]
          (fn []
            (is= (tup ["z" "y"]) (tup (cap/model-prefer)))))))))

(deftest "D-66：拉模型列表：URL、头、data[].id"
  (fn []
    (def seen @[])
    (def fake (fn [url headers]
                (array/push seen @[url headers])
                lm-fake-body))
    (def env (new-ws))
    (is= 0 (run-in-exit env "llm-set \"opencode\" \"provider\""))
    (is= 0 (run-in-exit env "llm-set H{ \"X-T\" \"9\" } \"headers\""))
    (def got (lm-with-env [["OPENCODE_API_KEY" "oc_sk_test"] ["RB_OC_BASE" nil]]
                (fn []
                  (lm-with-get fake
                    (fn [] (eval-top-in env "llm-models"))))))
    (is= 3 (length got))
    (is= (tup ["a-flash" "b-max" "mockish"]) (tup got))
    (is (string/find "/models" (get (seen 0) 0)))
    (def h (get (seen 0) 1))
    (is= "Bearer oc_sk_test" (get h "Authorization"))
    (is= "9" (get h "X-T") "自定义头也带上（拉列表同样需要鉴权/网关头）")
    (is (not (nil? (get h "x-opencode-session"))))))

(deftest "D-66：自动选模型：偏好命中 / 保留已在列表里的 / 写回工作区"
  (fn []
    (def fake (fn [url headers] lm-fake-body))
    (def env (new-ws))
    (is= 0 (run-in-exit env "llm-set \"opencode\" \"provider\""))
    (def r (lm-with-env [["OPENCODE_API_KEY" "oc_sk_test"] ["RB_MODEL_PREFER" "b-max,a-flash"]]
             (fn []
               (lm-with-get fake
                 (fn []
                   # 当前 model 是缺省（deepseek-v4.1-flash，不在列表里）→ 按偏好选 b-max
                   @[(eval-top-in env "llm-auto")
                     (eval-top-in env "at \"model\" llm")])))))
    (is= "b-max" (r 0))
    (is= "b-max" (r 1) "自动配置 = 真的写进工作区")
    # 已经指向列表里的模型：保留，不做惊喜变更
    (is= 0 (run-in-exit env "llm-set \"a-flash\" \"model\""))
    (def r2 (lm-with-env [["OPENCODE_API_KEY" "oc_sk_test"] ["RB_MODEL_PREFER" "b-max"]]
               (fn []
                 (lm-with-get fake
                   (fn [] (eval-top-in env "llm-auto"))))))
    (is= "a-flash" r2 "显式设过的模型还在列表里就保留")
    # 但**内置缺省**不算显式：偏好表照样生效（否则 RB_MODEL_PREFER 永远没机会）
    (is= 0 (run-in-exit env "llm-set nil \"model\""))
    (def r3 (lm-with-env [["OPENCODE_API_KEY" "oc_sk_test"] ["RB_MODEL_PREFER" "b-max"]]
               (fn []
                 (lm-with-get fake
                   (fn [] (eval-top-in env "llm-auto"))))))
    (is= "b-max" r3 "删除显式配置后按偏好走")))

(deftest "D-66：mock provider 不需要网络，列表就是 @[\"mock\"]"
  (fn []
    (def env (new-ws))
    (is= 0 (run-in-exit env "llm-set \"mock\" \"provider\""))
    (is= (tup ["mock"]) (tup (eval-top-in env "llm-models")))
    (is= "mock" (eval-top-in env "llm-auto") "mock 的自动配置就是它自己")
    (is= "mock" (eval-top-in env "at \"model\" llm"))))

(deftest "REQ-37：能力缺失时 llm-models / llm-auto 报 60（--core-only 边界不变）"
  (fn []
    (def env (new-ws))
    (is= 0 (run-in-exit env "llm-set \"mock\" \"provider\""))
    (def oldm (rb/cap-get :llm/models))
    (def olda (rb/cap-get :llm/auto))
    (put rb/cap :llm/models nil)
    (put rb/cap :llm/auto nil)
    (is= 60 (run-in-exit env "llm-models") "未装 :llm/models → 60")
    (is= 60 (run-in-exit env "llm-auto") "未装 :llm/auto → 60")
    (rb/cap-put :llm/models oldm)
    (rb/cap-put :llm/auto olda)
    (is= 0 (run-in-exit env "llm-models") "装回来就能用")))
