# 符合性矩阵（REQ ↔ 测试）

依据规格：**`ravel-breve-spec-v1.0c.md`**（修订定稿）；`ravel-breve-spec-v1.0b.md` 为历史原文。
状态：**M2**（词表 L0–L5 已落地）。`✅` = 已有可执行验收；`⏳` = 计划在某里程碑落地；`❓` = 需人工裁决（见 `docs/DECISIONS.md` / `docs/SPEC-FEEDBACK.md`）。

> 注：REQ-01…REQ-38 的编号与 v1.0b 保持稳定；v1.0c 新增 **REQ-39…REQ-46**（见文末）。

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
| REQ-01 | 语法为波兰（前缀）表达式：`词 实参…`，词在左 | ✅ | `conformance/req-01-notation.janet` |
| REQ-02 | 类 Forth 执行 + 前缀→后置转换（镜像），无 VM | ✅ | `conformance/req-01-notation.janet`、`unit/translate.janet` |
| REQ-03 | 引号块是嵌套波兰式，延迟代码；括号不参与镜像 | ✅ | `conformance/req-03-quote.janet` |
| REQ-04 | 换行终结、`\` 续行、未闭合块自动续行 | ✅ | `conformance/req-04-terminator.janet`、`unit/lexer.janet` |
| REQ-05 | 定义行 `:`；`=` 专表相等；`= 3 3` → true，`3 3 =` → 30 | ✅ | `conformance/req-05-definition.janet`、`req-01-notation.janet` |
| REQ-30 | **工作区 = 字典（函数与常量）+ 栈（变量）**；两者都是持久状态；并发在流层 | ✅（单工作区） | `conformance/req-30-stack-isolation.janet`（复用 env = 同一工作区） |
| REQ-31 | 每词 = 一次栈操作调用，按反转序排列、可 dump | ✅ | `conformance/req-01-notation.janet`（与规格示例逐字比对） |
| REQ-32 | `[ ]` 压栈即数据，仅由组合子触发 | ✅ | `conformance/req-32-quote.janet` |
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
| REQ-06 | 结构类型 String/Utter/Session/Stream/Json | ✅（Stream 除外） | `conformance/req-06-07-types.janet` |
| REQ-07 | 包装类型 Head/Endpoint/Path/Event/Workspace | ✅（负面；Ws 待 M4） | `conformance/req-06-07-types.janet` |
| REQ-08 | Stream 独立类型，chunk 到达即 flush | ⏳ M3 | |
| REQ-09 | 词表分层 L0–L9，一名一词性 | ✅ | `conformance/req-09-word-table.janet` |
| REQ-10 | Session 复用 L1 多态序列词，无会话编辑词 | ✅ | `conformance/req-10-session-polymorphism.janet` |
| REQ-11 | `,` / `,,` 为多态 join；`take`/`drop` 四象限 | ✅ | `conformance/req-11-join.janet`、`unit/words-l1.janet` |
| REQ-12 | 单 agent 活会话只可 append | ⏳ M3 | |
| REQ-13 | 改序/重编排 → 新 Session + 新 agent | ⏳ M3 | |
| REQ-14 | 来源树不进词表，仅保留 `origin` | ✅（负面） | `req-37`：`agents`/`focus`/`tree` 不得出现在词表 |
| REQ-15 | 广播可带域（含 `*`/`?` 通配） | ⏳ M3 | |
| REQ-16 | 钩子注册/注销 `@on`/`@off` | ⏳ M3 | |
| REQ-17 | 8 个事件名 | ⏳ M3 | |
| REQ-18 | 默认回合收尾钩子（@RoundDone）逐 stream 四步：解析绑定→转 utter→append→退订/删 stream | ⏳ M3 | |
| REQ-19 | `@off @RoundDone` 可禁用 | ⏳ M3 | |
| REQ-20 | 版本化 JSON 快照 + JSONL 增量日志 | ⏳ M4 | 格式待 CHK-4 冻结 |
| REQ-21 | compact 三条件（0.5 倍 / 1000 条 / 显式） | ⏳ M4 | |
| REQ-25 | 元命令为无前缀裸词（保留名表） | ✅（保留名表；分发待 M5） | `conformance/req-25-meta-commands.janet` |
| REQ-26 | 底栏 token 序列，字符串占位 `"…"` | ⏳ M7 | 前端 |
| REQ-27 | 主 buffer 为会话视图 | ⏳ M7 | 前端 |
| REQ-28 | `show` 普通打印；`watch` 语法糖 | ⏳ M5 | |
| REQ-29 | 按键 `t`/`s`/`c` | ⏳ M7 | 前端（Emacs 优先） |
| REQ-36 | Stream ≡ fiber，chunk 一次 yield | ⏳ M3 | |

## v1.0c 新增 REQ（39–44）

| REQ | 内容 | 状态 | 测试 |
|---|---|---|---|
| REQ-39 | `#` 至行末为注释 | ✅ | `unit/lexer.janet`（注释与空行） |
| REQ-40 | 块内换行 = 语句分隔（逐语句镜像、语句间保持书写序） | ✅ | `conformance/req-03-quote.janet`、`unit/translate.janet` |
| REQ-41 | 退出码具体取值（附录 E） | ✅ | `conformance/req-23-exit-codes.janet`、`e2e/cli.sh` |
| REQ-42 | `--serve`：工作区（字典 + 栈）跨请求保留 / 失败不终止 / EOF→0 | ✅ | `e2e/cli.sh` |
| REQ-43 | NDJSON 最小 schema（附录 F） | ✅（最小集） | `e2e/cli.sh` |
| REQ-44 | 字面量是数据、引号是代码（`{ }`/`H{ }` 不参与镜像） | ✅ | `conformance/req-44-literal.janet`、`unit/literals.janet` |
| REQ-45 | 一轮 = `list Stream`；stream 携带标签绑定 | ⏳ M3 | 待 M3 实现后补 `conformance/req-45-round-streams.janet` |
| REQ-46 | `Stream → Utter` 显式转换；自动/手动路径共用 | ⏳ M3 | 待 M3 实现后补 `conformance/req-46-utter.janet` |

## 附录 D：核心规模与禁止项

| 验收 | 手段 |
|---|---|
| 核心不含 net/file/http/crypto/JSON 解析 | `rb/init.janet` 装载期自检 + `make test-core-only`（剔除 `cap/` 仍可装载） |
| 无自研 VM / 字节码 / 求值循环 | 代码审查：只有 `rb/translate.janet`（文本转译）+ 栈原语 |
| 不含 Forth 特性与宿主语法（`immediate`/`>r`/`create`/`does>`/`!`/`@`/`<<`/`>>`/`$`/`(`） | `req-37` 负面断言 |
| 不含会话编辑词（`insert`/`remove`/`move`） | `req-37` 负面断言、`req-10` 负面断言 |
| 不含来源树词（`agents`/`focus`/`tree`/`AgentTree`） | `req-37` 负面断言 |

## M2 词表覆盖（逐词 → 用例）

`✅` = 有直接断言。用例位置：`U:` = `tests/unit/*`，`C:` = `tests/conformance/*`。

| 层 | 词 | 状态 | 用例 |
|---|---|---|---|
| L0 | `dup` `pop` `swap` `rot` `-rot` `keep` `dip` `apply` `depth` `dump` | ✅ | U:words-l1（间接）、C:req-09 |
| L1 | `len` `take` `drop` `first` `last` `reverse` `sort` `at` `nth` `map` `filter` `fold` `zip` `show` `print` | ✅ | U:words-l1 |
| L1 | `,` `,,` `split` | ✅ | C:req-11、U:words-l1 |
| L1b | `=` `!=` `<` `>` `<=` `>=` `not` `and` `or` `+` `-` `*` `/` `mod` `abs` `min` `max` `sum` | ✅ | C:req-09、U:words-l5 |
| L1c | `trim` `replace` `contains` `starts-with` `ends-with` `lines` `words` | ✅ | U:words-l1c-l1d |
| L1d | `to-string` `to-int` | ✅ | U:words-l1c-l1d |
| L2 | `Utter` `say` `Role` `Content` `to-json` `from-json` | ✅ | U:words-l2、C:req-06-07-types |
| L5 | `if` `when` `unless` `loop` `while` `try` `recover` `retry` | ✅ | U:words-l5 |
| L5b | `fail` `assert` `now` `env` `log` `wait` | ✅（`log`/`wait` 间接） | U:words-l5、C:req-23 |
| L6 | `see` `doc` | ✅ | C:req-05-definition |
| — | 元命令保留名表 | ✅ | C:req-25 |

**组合子引号内的实参次序**（M2 实测结论，见 `docs/DECISIONS.md` D-18 / SF-12）：
引号是**未写满的波兰表达式**，组合子把隐藏实参补在**最右**（书写序最后）。
故 `filter [ < 2 ] seq` 即 `< 2 元素`（第一个操作数 2）；`map [ - 10 ] { 1 2 3 }` → `(9 8 7)`；
`fold [ - ] 0 { 1 2 3 4 }` 即 `- 累加值 元素` → `-10`。
直接推论：**栈上已有的值只能落在最右操作数位置**。
计数循环也只写波兰式：`1 2 3` → `while [ < 1 depth ] [ + ]`（`< 1 depth`，即 1 小于 depth 时继续）。
