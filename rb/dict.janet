# rb/dict.janet —— 字典（REQ-33 / REQ-35）
#
# 字典：词名 → @{:body thunk :doc string :src string :declared bool}
# 定义行在**装载期**（= 转译期）先 rb/dict-declare 占位，运行期再由
# rb/define-word 装入 thunk；重定义**覆盖并告警**（REQ-35）。

(def rb/dict @{})

(defn rb/dict?
  [name]
  (not (nil? (get rb/dict name))))

(defn rb/dict-declare
  "装载期占位：让后续语句能在转译时解析到该名字（REQ-33）。"
  [name &opt src]
  (when (not (rb/dict? name))
    (put rb/dict name @{:body nil :doc "" :src (or src "") :declared true})))

(defn rb/define-word
  "运行期装入词体；重定义覆盖并告警（REQ-35）。"
  [name thunk &opt docstr src]
  (def old (get rb/dict name))
  (when (and old (not (nil? (old :body))))
    (eprintf "ravel: 警告：重定义 %s\n" name))
  (put rb/dict name @{:body thunk :doc (or docstr "") :src (or src "") :declared false})
  nil)

(defn rb/call-word
  "调用一个用户定义的词。"
  [name]
  (def e (get rb/dict name))
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
  (def e (get rb/dict name))
  (if (nil? e)
    (print (string "无此词：" name))
    (print (string name " : [ " (e :src) " ]"))))

(defn rb/doc
  "L6：打印文档串（REQ-35）。"
  []
  (def name (rb/pop))
  (def e (get rb/dict name))
  (print (if (nil? e) (string "无此词：" name) (string name " —— " (e :doc)))))
