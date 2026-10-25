# tests/unit/opencode.janet —— D-64：OpenCode Zen / Go provider（OpenAI 兼容）
#
# 不联网：把 `:http/post-lines` 换成一个**假的**行源，检查我们发出去的
# 请求头/请求体，以及 SSE 的解析规则（reasoning 不算正文、用量照记）。

(def oc-dir
  (do (protect (os/mkdir "build/tmp")) "build/tmp"))

(defn oc-with-post
  "临时替换 `:http/post-lines`，跑 body，最后还原。`fake` 收到 (url headers body)。"
  [fake body]
  (def old (rb/cap-get :http/post-lines))
  (rb/cap-put :http/post-lines fake)
  (def r (protect (body)))
  (rb/cap-put :http/post-lines old)
  # protect → [true 值] / [false 错误]
  (if (get r 0)
    (get r 1)
    (error (get r 1))))

(defn oc-env
  [k dflt]
  (def v (os/getenv k))
  (if (nil? v) dflt v))

(deftest "D-64：端点缺省与 RB_OC_BASE 覆盖"
  (fn []
    (def old (os/getenv "RB_OC_BASE"))
    (os/setenv "RB_OC_BASE")
    (is= "https://opencode.ai/zen/go/v1/chat/completions" (cap/oc-url))
    (os/setenv "RB_OC_BASE" "https://example.test/v1/")
    (is= "https://example.test/v1/chat/completions" (cap/oc-url))
    (os/setenv "RB_OC_BASE" "https://example.test/v1/chat/completions")
    (is= "https://example.test/v1/chat/completions" (cap/oc-url)
         "已是完整端点就不再拼")
    (os/setenv "RB_OC_BASE" old)))

(deftest "D-64：provider=opencode 时的模型缺省与端点缺省"
  (fn []
    (def env (new-ws))
    (is= 0 (run-in-exit env "llm-set \"opencode\" \"provider\""))
    (is= "opencode" (eval-top-in env "llm-get \"provider\""))
    (is= cap/oc-model-default (eval-top-in env "llm-get \"model\"")
         "没设 model 就按 provider 给缺省")
    (is= "glm-5.3-flash" cap/oc-model-default)
    (is (string/find "opencode.ai" (eval-top-in env "llm-get \"endpoint\"")))
    (is= 0 (run-in-exit env "llm-set \"glm-5.3\" \"model\""))
    (is= "glm-5.3" (eval-top-in env "llm-get \"model\""))))

(deftest "D-64：请求头自称客户端、带稳定 session、Bearer 密钥"
  (fn []
    (def seen @[])
    (def fake (fn [url headers body]
                (array/push seen [url headers body])
                (fn [] nil)))
    (def oldkey (os/getenv "OPENCODE_API_KEY"))
    (os/setenv "OPENCODE_API_KEY" "oc_sk_test")
    (oc-with-post fake
      (fn []
        (def f (rb/cap-get :llm/opencode))
        (f @[@{:role "user" :content "hi"}] @{:model "glm-5.3-flash" :session "c"})
        (f @[@{:role "user" :content "hi"}] @{:model "glm-5.3-flash" :session "c"})))
    (os/setenv "OPENCODE_API_KEY" oldkey)
    (is= 2 (length seen))
    (def h (seen 0))
    (def [url headers body] h)
    (is (string/find "opencode.ai/zen/go/v1/chat/completions" url))
    (is= "Bearer oc_sk_test" (get headers "Authorization"))
    (is (string/has-prefix? "ravel-breve/" (get headers "User-Agent"))
        "必须自称客户端（OpenCode 拒绝通用 SDK 名）")
    (is (not (nil? (get headers "x-opencode-session")))
        "缺这个头会被 MissingSessionID 拒掉")
    (is= (get headers "x-opencode-session")
         (get (get (seen 1) 1) "x-opencode-session")
         "同一会话两次请求用同一个 session")
    (is= "rb-c" (get headers "x-opencode-session"))
    (is (string/find "\"stream\":true" body))
    (is (string/find "include_usage" body))))

(deftest "D-64：SSE 里 reasoning_content 不进正文，usage 照记（REQ-55）"
  (fn []
    (def lines @[
      "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"\"}}]}"
      "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"想一下\"}}]}"
      "data: {\"choices\":[{\"delta\":{\"content\":\"收到\"}}]}"
      "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":7,\"completion_tokens\":2,\"total_tokens\":9}}"
      "data: [DONE]"])
    (var i 0)
    (def fake (fn [url headers body]
                (fn [] (def v (get lines i)) (set i (inc i)) v)))
    (def oldkey (os/getenv "OPENCODE_API_KEY"))
    (os/setenv "OPENCODE_API_KEY" "oc_sk_test")
    (def out (oc-with-post fake
               (fn []
                 (def f (rb/cap-get :llm/opencode))
                 (def it (f @[@{:role "user" :content "hi"}]
                            @{:model "glm-5.3-flash" :session "c"}))
                 (var text "")
                 (var u nil)
                 (var go true)
                 (while go
                   (def b (it))
                   (cond
                     (nil? b) (set go false)
                     (string? b) (set text (string text b))
                     (dictionary? b) (set u (get b :usage))))
                 @[text u])))
    (os/setenv "OPENCODE_API_KEY" oldkey)
    (is= "收到" (out 0) "reasoning 不算正文")
    (is= 7 (get (out 1) "prompt_tokens"))
    (is= 9 (get (out 1) "total_tokens"))))
