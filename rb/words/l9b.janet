# rb/words/l9b.janet —— L9b 插件（REQ-60，v1.0j）
#
# 三个词，词性互不重叠（REQ-09）：`plug` / `unplug` 是动词，`plugins` 是名词。
#
#   plug        Path -- String   装载，返回插件名；坏路径 40，非字符串 31
#   unplug      Name -- Int      卸载，返回撤销项数；没装过 20
#   plugins     -- Seq           已装插件名（升序）
#
# 「插件能装什么」由 rb/plugins.janet 记账：词（定义行）、钩子（`@on`）、
# 工具（`deftool`）。核心层（词法 / 转译 / 栈 / 流 / agent / 钩子机制 / 协议）
# 插件碰不到——这条分离是 ABI 的一部分，不是风格建议。

(defn rb/plug
  "Path -- String ；装载一个插件文件（`.breve`），返回插件名。
   装载不算一轮（不触发 `@RoundDone`、不写日志）；失败则整趟撤销后抛原错误。"
  []
  (def path (rb/pop))
  (rb/push (rb/plugin-load path)))

(defn rb/unplug
  "Name -- Int ；卸载插件，返回撤销的项数（词 + 钩子 + 工具）。"
  []
  (def name (rb/pop))
  (when (not (string? name))
    (rb/raise (rb/exit-table :runtime-type)
              (string "unplug 需要一个插件名字符串，得到 " (type name))))
  (rb/push (rb/plugin-unload name)))

(defn rb/plugins
  "-- Seq ；已装插件名（升序）。"
  []
  (rb/push (rb/plugin-list)))
