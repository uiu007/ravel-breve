# rb/dict.janet —— 字典（REQ-33 / REQ-35，M4 起属于工作区）
#
# 字典 = 工作区的「函数与常量」那半（REQ-30）：`名字 → 词条`。
# 词条：@{:body thunk :doc string :src ravel源 :code 宿主序 :declared bool}
#   - `:src`  = 体的 **ravel 源文本**（`see` 显示它；REQ-20 的快照也存它）
#   - `:code` = 体的宿主序文本（调试 / --dump 对照）
# 定义行在**转译期**先 rb/dict-declare 占位（REQ-33：后续语句能解析到），
# 运行期再由 rb/define-word 装入 thunk；重定义**覆盖并告警**（REQ-35）。
#
# 转译期用的 dict 由调用方**显式传入**（rb/compile-source），
# 运行期用的 dict 取当前工作区（`(rb/ws)` → `:dict`）。

(defn rb/dict-of
  "取某个工作区的字典；不给工作区就取当前的（REQ-30）。"
  [&opt ws]
  ((or ws (rb/ws)) :dict))

(defn rb/dict?
  "该名字是否已在字典里（转译期传入目标工作区）。"
  [name &opt dict]
  (not (nil? (get (or dict (rb/dict-of)) name))))

(defn rb/dict-entry
  [name &opt dict]
  (get (or dict (rb/dict-of)) name))

(defn rb/dict-declare
  "装载期占位：让后续语句能在转译时解析到该名字（REQ-33）。"
  [name &opt src dict]
  (def d (or dict (rb/dict-of)))
  (when (nil? (get d name))
    (put d name @{:body nil :doc "" :src (or src "") :code "" :declared true})))

(defn rb/define-word
  "运行期装入词体；重定义覆盖并告警（REQ-35）。"
  [name thunk &opt docstr src code]
  (def d (rb/dict-of))
  (def old (get d name))
  (when (and old (not (nil? (old :body))))
    (eprintf "ravel: 警告：重定义 %s\n" name))
  (put d name @{:body thunk
                :doc (or docstr "")
                :src (or src "")
                :code (or code "")
                :declared false})
  nil)

(defn rb/call-word
  "调用一个用户定义的词。"
  [name]
  (def e (rb/dict-entry name))
  (if (nil? e)
    (rb/raise (rb/exit-table :syntax-unknown-word) (string "未定义的词：" name))
    (do
      (when (nil? (e :body))
        (rb/raise (rb/exit-table :syntax-unknown-word) (string "词体尚未装入：" name)))
      ((e :body)))))

(defn rb/see
  "L6：打印词条（REQ-35：doc/see 从字典读取）。"
  []
  (def name (rb/pop))
  (def e (rb/dict-entry name))
  (if (nil? e)
    (print (string "无此词：" name))
    (print (string name " : [ " (e :src) " ]"))))

(defn rb/doc
  "L6：打印文档串（REQ-35）。"
  []
  (def name (rb/pop))
  (def e (rb/dict-entry name))
  (print (if (nil? e) (string "无此词：" name) (string name " —— " (e :doc)))))

(defn rb/dict-words
  "字典里的全部名字（快照 / 调试用）。"
  [&opt dict]
  (sort (keys (or dict (rb/dict-of)))))
