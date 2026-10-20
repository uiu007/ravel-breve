# tests/unit/stream.janet —— Stream 生命周期（REQ-08 / REQ-36 / REQ-45 / REQ-46）

(defn fake-it
  "把固定序列变成取块函数；抛出用 :throw 项。"
  [items]
  (var i 0)
  (fn []
    (when (< i (length items))
      (def x (items i))
      (++ i)
      (if (and (table? x) (get x :throw))
        (error (x :throw))
        x))))

(defn log-events
  "给五个生命周期事件挂一个记录器，返回记录数组。"
  [env]
  (def log @[])
  (each ev @["@Start" "@Chunk" "@Fail" "@Close" "@Done"]
    (hook-on-in env ev (fn [] (array/push log ev))))
  log)

(defn mk-stream
  "在工作区里建一个流，并把取块函数挂上。"
  [env items]
  (var s nil)
  (in-env env (fn [] (set s (rb/stream-new "c" nil (fake-it items)))))
  s)

(deftest "stream: 取块时序 Start → Chunk… → Done → Close"
  (fn []
    (def env (new-ws))
    (def log (log-events env))
    (def s (mk-stream env @["a" "b"]))
    (in-env env (fn []
                  (rb/push (rb/stream-next! s))
                  (rb/push (rb/stream-next! s))
                  (rb/push (rb/stream-next! s))))
    (is= (tup ["a" "b" nil]) (tup (env :rb-stack)))
    (is= (tup ["@Start" "@Chunk" "@Chunk" "@Done" "@Close"]) (tup log))
    (is= :done (s :state))
    (is (s :closed))
    (is= "ab" (string (s :text)))))

(deftest "stream: 到末尾后再取不再发事件"
  (fn []
    (def env (new-ws))
    (def log (log-events env))
    (def s (mk-stream env @["a"]))
    (in-env env (fn []
                  (rb/stream-next! s)
                  (rb/stream-next! s)
                  (rb/stream-next! s)))
    (is= (tup ["@Start" "@Chunk" "@Done" "@Close"]) (tup log))))

(deftest "stream: 取块函数抛出 → Fail + Close，utter 报 60"
  (fn []
    (def env (new-ws))
    (def log (log-events env))
    (def s (mk-stream env @["a" @{:throw "炸了"}]))
    (def d (in-env env (fn [] (rb/stream-drain! s))))
    (is= :error (fiber/status d) "drain 遇失败流应抛错（D-27）")
    (is= 60 (rb/error-code (fiber/last-value d)))
    (is= "a" (string (s :text)) "失败前已取到的一块保留")
    (is= :failed (s :state))
    (is= (tup ["@Start" "@Chunk" "@Fail" "@Close"]) (tup log))
    (def fb (in-env env (fn [] (rb/stream->utter! s))))
    (is= :error (fiber/status fb))
    (is= 60 (rb/error-code (fiber/last-value fb)))))

(deftest "stream: 取块函数返回非字符串 → 31"
  (fn []
    (def env (new-ws))
    (def s (mk-stream env @[42]))
    (def fb (in-env env (fn [] (rb/stream-next! s))))
    (is= :error (fiber/status fb))
    (is= 31 (rb/error-code (fiber/last-value fb)))))

(deftest "stream: drain 取尽并可重复调用（幂等）"
  (fn []
    (def env (new-ws))
    (def s (mk-stream env @["ab" "cd"]))
    (in-env env (fn []
                  (rb/push (rb/stream-drain! s))
                  (rb/push (rb/stream-drain! s))))
    (is= (tup ["abcd" "abcd"]) (tup (env :rb-stack)))))

(deftest "stream: stop 中止，Close 只发一次"
  (fn []
    (def env (new-ws))
    (def log (log-events env))
    (def s (mk-stream env @["a" "b"]))
    (in-env env (fn []
                  (rb/stream-next! s)
                  (rb/stream-stop! s)
                  (rb/stream-stop! s)))
    (is= :stopped (s :state))
    (is= (tup ["@Start" "@Chunk" "@Close"]) (tup log))
    (in-env env (fn [] (rb/push (rb/stream-next! s))))
    (is (nil? (last (env :rb-stack))) "中止后再取为 nil")))

(deftest "stream: new 即登记进本轮（REQ-45）"
  (fn []
    (def env (new-ws))
    (mk-stream env @["a"])
    (mk-stream env @["b"])
    (is= 2 (length ((env :rb-ws) :round)))
    (is= (tup ["c" "c"]) (tup (map (fn [s] (s :label)) ((env :rb-ws) :round))))))

(deftest "stream: 类型校验 —— 非 Stream 一律 31"
  (fn []
    (def fb (in-env (new-ws) (fn [] (rb/stream-ensure "不是流"))))
    (is= :error (fiber/status fb))
    (is= 31 (rb/error-code (fiber/last-value fb)))
    (is (rb/stream? @{:kind :stream}))
    (is (not (rb/stream? @{:kind :agent})))))

(deftest "stream: Stream → Utter 是唯一转换（REQ-46）"
  (fn []
    (def env (new-ws))
    (def s (mk-stream env @["你" "好"]))
    (in-env env (fn [] (rb/push (rb/stream->utter! s))))
    (is= (tup [@{:role "assistant" :content "你好"}])
         (tup (env :rb-stack)))))
