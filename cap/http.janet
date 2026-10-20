# cap/http.janet —— 能力层：HTTP POST 的**行流**（§4.11 / REQ-37）
#
# 核心不认识网络。这里把「一次 POST、按行读回」包成一个能力：
#   键 :http/post-lines
#   入参 url headers body
#   出参 0 元取行函数（String 一行，nil = 结束）
#
# 实现选型：curl 子进程 + **命名管道（FIFO）**。
#   * 管道是**阻塞**的普通文件句柄 → `file/read :line` 真阻塞，天然流式，
#     不占用事件循环，也不需要把方言求值改成异步（REQ-36 的时序由拉取保证）。
#   * 错误走临时文件（stdout 是 FIFO，不能混）。

(var cap/http-seq 0)

(defn cap/http-tmp
  "生成一个本进程内唯一的临时路径。"
  [suffix]
  (++ cap/http-seq)
  (string "/tmp/ravel-" (os/getpid) "-" cap/http-seq suffix))

(defn cap/shell-quote
  "把单个参数安全地嵌进 sh 命令行（单引号包裹）。"
  [s]
  (string "'" (string/replace-all "'" "'\\''" s) "'"))

(defn cap/http-post-lines
  "url headers body → 取行函数。headers = @{\"Name\" \"value\" …}，body = String。"
  [url headers body]
  (def fifo (cap/http-tmp ".fifo"))
  (def errfile (cap/http-tmp ".err"))
  (def bodyfile (cap/http-tmp ".body"))
  (spit bodyfile body)
  (def mk (os/execute ["mkfifo" fifo] :p))
  (when (not= mk 0)
    (os/execute ["rm" "-f" bodyfile] :p)
    (rb/raise (rb/exit-table :io-write)
              (string "无法创建命名管道 " fifo "（mkfifo 退出码 " mk "）")))
  (def argv @["curl" "-sS" "-N" "--max-time" (or (os/getenv "RB_HTTP_TIMEOUT") "180")
              "--connect-timeout" "20"
              "-X" "POST" url "--data-binary" (string "@" bodyfile)])
  (each [k v] (pairs headers)
    (array/push argv "-H")
    (array/push argv (string k ": " v)))
  (def script
    (string "exec > " (cap/shell-quote fifo) " 2> " (cap/shell-quote errfile) "; "
            (string/join (map cap/shell-quote argv) " ")))
  (var proc nil)
  (var fh nil)
  (var exit-code nil)
  (defn cleanup []
    (when fh (protect (file/close fh)) (set fh nil))
    (os/execute ["rm" "-f" fifo bodyfile] :p))
  (defn finish []
    (when (nil? exit-code)
      (set exit-code (or (os/proc-close proc) 0))
      (def err (or (get (protect (slurp errfile)) 1) ""))
      (cleanup)
      (os/execute ["rm" "-f" errfile] :p)
      (when (and (not= exit-code 0) (string? err))
        (when (not (empty? (string/trimr err)))
          (rb/raise (rb/exit-table :orchestration-base)
                    (string "HTTP 请求失败（curl " exit-code "）：" (string/trimr err))))))
    nil)
  (set proc (os/spawn ["bash" "-c" script] :p))
  (fn []
    (if (nil? fh)
      (set fh (file/open fifo :r)))  # 阻塞到子进程打开写端
    (def line (file/read fh :line))
    (if (nil? line)
      (do (finish) nil)
      (string/trimr line))))

(rb/cap-put :http/post-lines cap/http-post-lines)
