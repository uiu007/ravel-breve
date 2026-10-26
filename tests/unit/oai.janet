# tests/unit/oai.janet —— REQ-70：SSE 取块循环的 EOF 幂等性
#
# 现象（v1.0q 实测，OpenCode / deepseek-v4.1-flash）：收尾块可能在**行源到 EOF 那次**
# 才被补交（没有 `finish_reason` 帧的 provider 就是这样），于是上层会再取一次；
# 第二次进 `cap/oai-pull` 时若仍去问行源，HTTP 行流的 FIFO 已经删掉 → `file/read nil`
# →「bad slot #0, expected core/file, got nil」→ 整轮 60。
#
# 所以：**行源 EOF 之后一行都不许再问**，取块函数必须是幂等的。

(defn oai-counted-lines
  "行源：先给 payload，再给 nil（EOF），**之后每问一次就记一笔违规**。"
  [payload]
  (def st @{:n 0 :after-eof 0})
  [st (fn []
        (++ (st :n))
        (cond
          (= (st :n) 1) (string "data: " payload)
          (= (st :n) 2) nil
          (do (++ (st :after-eof)) nil)))])

(deftest "REQ-70：行源 EOF 之后不再被调用（取块函数幂等）"
  (fn []
    (def [st lines] (oai-counted-lines
                      "{\"choices\":[{\"delta\":{\"content\":\"hi\"},\"finish_reason\":\"length\"}]}"))
    (def pull (cap/oai-pull lines (fn [s] (cap/json/decode s)) "mock"))
    (is= "hi" (pull) "文本块")
    (def f (pull))
    (is= "length" (f :finish) "收尾块带 finish_reason")
    (is= 2 (f :chars) "正文长度")
    (is= 0 (f :calls) "没有工具调用")
    (is (nil? (pull)) "收尾块之后是 nil")
    (is (nil? (pull)) "再取还是 nil")
    (is= 2 (st :n) "行源只在 EOF 之前被调用")
    (is= 0 (st :after-eof) "EOF 之后一次都没问")))

(deftest "REQ-70：没有 finish_reason 帧时，EOF 那次补交收尾块（reason = stop）"
  (fn []
    (def [st lines] (oai-counted-lines "{\"choices\":[{\"delta\":{\"content\":\"\"}}]}"))
    (def pull (cap/oai-pull lines (fn [s] (cap/json/decode s)) "mock"))
    (def f (pull))
    (is= "stop" (f :finish) "缺省 stop")
    (is= 0 (f :chars) "零正文（推理型模型的病理）")
    (is (nil? (pull)) "继续取 = nil")
    (is= 0 (st :after-eof) "EOF 之后一次都没问")))
