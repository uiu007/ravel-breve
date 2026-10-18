# 符合性矩阵（REQ ↔ 测试）

状态：**M0**（2026-xx）。`✅` = 已有可执行验收；`⏳` = 计划在某里程碑落地；`❓` = 需人工裁决（见 `docs/DECISIONS.md` / `docs/SPEC-FEEDBACK.md`）。

跑法：`make test`（单元 + 符合性 + 端到端 + 附录 D）。

## 测试分层

| 层 | 位置 | 说明 |
|---|---|---|
| 单元 | `tests/unit/*.janet` | 词法 / 转译等内部不变量 |
| 符合性 | `tests/conformance/req-*.janet` | 逐条 REQ 的验收（文件名即 REQ 号） |
| 端到端 | `tests/e2e/cli.sh` | 真二进制、真退出码、REPL/--serve 管道 |
| 附录 D | `make test-core-only` | 剔除 `cap/` 后核心仍可独立装载并完成主脊 |

## §4.1–4.5 记法与执行模型

| REQ | 内容 | 状态 | 测试 |
|---|---|---|---|
| REQ-01 | 一行内 RTL 求值，操作符在左 | ✅ | `conformance/req-01-notation.janet` |
| REQ-02 | 镜像原理（切词→反转→换名→宿主求值，无 VM） | ✅ | `conformance/req-01-notation.janet`、`unit/translate.janet` |
| REQ-03 | 引号块内同样 RTL，括号不参与反转 | ✅ | `conformance/req-03-quote.janet` |
| REQ-04 | 换行终结、`\` 续行、未闭合块自动续行 | ✅ | `conformance/req-04-terminator.janet`、`unit/lexer.janet` |
| REQ-05 | 定义行 `:`；`=` 专表相等 | ✅ | `conformance/req-05-definition.janet` |
| REQ-30 | 数据栈 fiber-local，不在宿主全局共享 | ✅ | `conformance/req-30-stack-isolation.janet`、`e2e/cli.sh`（--serve 逐请求隔离） |
| REQ-31 | 每词 = 一次栈操作调用，按反转序排列、可 dump | ✅ | `conformance/req-01-notation.janet`（与规格示例逐字比对） |
| REQ-32 | `[ ]` 压栈即数据，仅由组合子触发 | ✅ | `conformance/req-03-quote.janet` |
| REQ-33 | 定义行是元层，装载期注册进字典 | ✅ | `conformance/req-05-definition.janet` |
| REQ-34 | 元层不参与镜像，仅 `体` 递归反转 | ✅ | `conformance/req-05-definition.janet`、`unit/translate.janet` |
| REQ-35 | `doc`/`see` 读字典；重定义覆盖并告警 | ✅ | `conformance/req-05-definition.janet` |
| REQ-23 | 退出码分级 | ✅ | `conformance/req-23-exit-codes.janet`、`e2e/cli.sh` |
| REQ-22 | CLI 四形态 + 提示符 | ✅ | `e2e/cli.sh` |
| REQ-24 | 前后端分离，NDJSON over stdio | ⏳（骨架已通） | `e2e/cli.sh`（--serve 逐行请求/响应） |
| REQ-38 | 宿主钉 1.42.x，amalgam 静态嵌入 | ✅ | `make check-vendor`、`vendor/janet/VERSION` |
| REQ-37 | 核心不含 net/file/http/crypto，能力走能力层 | ✅ | `conformance/req-37-cap-boundary.janet`、`make test-core-only` |

## §4.6–4.8 类型 / 词表 / 会话

| REQ | 内容 | 状态 | 备注 |
|---|---|---|---|
| REQ-06 | 结构类型 String/Utter/Session/Stream/Json | ⏳ M2 | |
| REQ-07 | 包装类型 Head/Endpoint/Path/Event/Workspace | ⏳ M2 | |
| REQ-08 | Stream 独立类型，chunk 到达即 flush | ⏳ M2/M3 | |
| REQ-09 | 词表分层 L0–L9，一名一词性 | ⏳ M2 | |
| REQ-10 | Session 复用 L1 多态序列词，无会话编辑词 | ⏳ M2 | 负面测试见 `req-37` 的禁止词断言 |
| REQ-11 | `,` / `,,` 为多态 join；`take`/`drop` 四象限 | ⏳ M2 | |
| REQ-12 | 单 agent 活会话只可 append | ⏳ M3 | |
| REQ-13 | 改序/重编排 → 新 Session + 新 agent | ⏳ M3 | |
| REQ-14 | 来源树不进词表，仅保留 `origin` | ✅（负面） | `req-37`：`agents`/`focus`/`tree` 不得出现在词表 |
| REQ-15 | 广播可带域（含 `*`/`?` 通配） | ⏳ M3 | |
| REQ-16 | 钩子注册/注销 `@on`/`@off` | ⏳ M3 | |
| REQ-17 | 8 个事件名 | ⏳ M3 | |
| REQ-18 | 默认回合收尾钩子（@RoundDone）四步时序 | ⏳ M3 | |
| REQ-19 | `@off @RoundDone` 可禁用 | ⏳ M3 | |
| REQ-20 | 版本化 JSON 快照 + JSONL 增量日志 | ⏳ M4 | 格式待 CHK-4 冻结 |
| REQ-21 | compact 三条件（0.5 倍 / 1000 条 / 显式） | ⏳ M4 | |
| REQ-25 | 元命令为无前缀裸词（保留名表） | ⏳ M5 | |
| REQ-26 | 底栏 token 序列，字符串占位 `"…"` | ⏳ M7 | 前端 |
| REQ-27 | 主 buffer 为会话视图 | ⏳ M7 | 前端 |
| REQ-28 | `show` 普通打印；`watch` 语法糖 | ⏳ M5 | |
| REQ-29 | 按键 `t`/`s`/`c` | ⏳ M7 | 前端（Emacs 优先） |
| REQ-36 | Stream ≡ fiber，chunk 一次 yield | ⏳ M3 | |

## 附录 D：核心规模与禁止项

| 验收 | 手段 |
|---|---|
| 核心不含 net/file/http/crypto/JSON 解析 | `rb/init.janet` 装载期自检 + `make test-core-only`（剔除 `cap/` 仍可装载） |
| 无自研 VM / 字节码 / 求值循环 | 代码审查：只有 `rb/translate.janet`（文本转译）+ 栈原语 |
| 不含 Forth 特性与宿主语法（`immediate`/`>r`/`create`/`does>`/`!`/`@`/`<<`/`>>`/`$`/`(`） | `req-37` 负面断言 |
| 不含会话编辑词（`insert`/`remove`/`move`） | `req-37` 负面断言 |
| 不含来源树词（`agents`/`focus`/`tree`/`AgentTree`） | `req-37` 负面断言 |
