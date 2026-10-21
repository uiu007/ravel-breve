# 符合性矩阵（REQ ↔ 测试）

依据规格：**`ravel-breve-spec-v1.0d.md`**（agent 基本能力定稿，待 CHK-6 追认）；
`ravel-breve-spec-v1.0c.md` / `ravel-breve-spec-v1.0b.md` 为历史原文。
状态：**M6**（词表 L0–L9 + 持久化 L7 + agent / 流 / 钩子 / 收尾 + 工具调用 / 重试 / 压缩 / 编排边 + CLI / NDJSON 协议 v1 已落地；真 NVIDIA provider 已打通）。`✅` = 已有可执行验收；`⏳` = 计划在某里程碑落地；`❓` = 需人工裁决（见 `docs/DECISIONS.md` / `docs/SPEC-FEEDBACK.md`）。

> 注：REQ-01…REQ-38 的编号与 v1.0b 保持稳定；v1.0c 新增 **REQ-39…REQ-46**，
> v1.0d 新增 **REQ-47…REQ-51**（见文末）。

跑法：`make test`（单元 + 符合性 + 端到端 + 附录 D）。

## 测试分层

| 层 | 位置 | 说明 |
|---|---|---|
| 附录 A 覆盖 | `tests/conformance/req-09-appendix-a.janet` | 规格列出的词逐个「认得」；未冻结的（`seq`/`par`/`Json`）显式断言仍报 20 |
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
| REQ-22 | CLI 四形态 + 提示符 + `--json` | ✅ | `e2e/cli.sh`、`conformance/req-22-cli.janet` |
| REQ-24 | 前后端分离，NDJSON over stdio（双向不阻塞） | ✅ 协议 v1 冻结（D-39） | `conformance/req-24-duplex.janet`、`e2e/cli.sh`（chunk 与 eval 同进程交织） |
| REQ-38 | 宿主钉 1.42.x，amalgam 静态嵌入 | ✅ | `make check-vendor`、`vendor/janet/VERSION` |
| REQ-37 | 核心不含 net/file/http/crypto，能力走能力层 | ✅ | `conformance/req-37-cap-boundary.janet`、`make test-core-only` |

## §4.6–4.8 类型 / 词表 / 会话

| REQ | 内容 | 状态 | 备注 |
|---|---|---|---|
| REQ-06 | 结构类型 String/Utter/Session/Stream/Json | ✅ | `conformance/req-06-07-types.janet`、`unit/stream.janet` |
| REQ-07 | 包装类型 Head/Endpoint/Path/Event/Workspace | ✅ | `conformance/req-06-07-types.janet`、`req-20-workspace.janet`（Workspace 句柄） |
| REQ-08 | Stream 独立类型，chunk 到达即 flush | ✅ | `conformance/req-08-stream.janet`、`unit/stream.janet` |
| REQ-09 | 词表分层 L0–L9，一名一词性 | ✅ | `conformance/req-09-word-table.janet` |
| REQ-10 | Session 复用 L1 多态序列词，无会话编辑词 | ✅ | `conformance/req-10-session-polymorphism.janet` |
| REQ-11 | `,` / `,,` 为多态 join；`take`/`drop` 四象限 | ✅ | `conformance/req-11-join.janet`、`unit/words-l1.janet` |
| REQ-12 | 单 agent 活会话只可 append | ✅ | `conformance/req-12-13-agent.janet` |
| REQ-13 | 改序/重编排 → 新 Session + 新 agent | ✅ | `conformance/req-12-13-agent.janet` |
| REQ-14 | 来源树不进词表，仅保留 `origin` | ✅（负面） | `req-37`：`agents`/`focus`/`tree` 不得出现在词表 |
| REQ-15 | 广播可带域（含 `*`/`?` 通配） | ✅ | `conformance/req-15-bcast.janet` |
| REQ-16 | 钩子注册/注销 `@on`/`@off` | ✅ | `conformance/req-16-19-hooks.janet`、`unit/events.janet` |
| REQ-17 | 8 个事件名 | ✅ | `conformance/req-16-19-hooks.janet`、`unit/events.janet` |
| REQ-18 | 默认回合收尾钩子（@RoundDone）逐 stream 四步：解析绑定→转 utter→append→退订/删 stream | ✅ | `conformance/req-45-46-round.janet`（D-30：中断则本轮作废） |
| REQ-19 | `@off @RoundDone` 可禁用 | ✅ | `conformance/req-16-19-hooks.janet` |
| REQ-20 | 版本化 JSON 快照 + JSONL 增量日志 | ✅ | `conformance/req-20-workspace.janet`、`unit/store.janet`（格式冻结见 D-33） |
| REQ-21 | compact 三条件（0.5 倍 / 1000 条 / 显式） | ✅ | `conformance/req-21-compact.janet`（小工作区频繁 compact 见 D-37） |
| REQ-25 | 元命令为无前缀裸词（保留名表 + REPL 分发） | ✅ | `conformance/req-25-meta-commands.janet`、`e2e/cli.sh` |
| REQ-26 | 底栏 token 序列，字符串占位 `"…"` | ⏳ M7 | 前端 |
| REQ-27 | 主 buffer 为会话视图 | ⏳ M7 | 前端 |
| REQ-28 | `show` 普通打印；`watch` 语法糖（视图流） | ✅ | `conformance/req-28-show-watch.janet` |
| REQ-29 | 按键 `t`/`s`/`c` | ⏳ M7 | 前端（Emacs 优先） |
| REQ-36 | Stream ≡ fiber，chunk 一次 yield | ✅ | `conformance/req-45-46-round.janet`（两流交错推进）、`unit/stream.janet` |

## v1.0c 新增 REQ（39–46）

| REQ | 内容 | 状态 | 测试 |
|---|---|---|---|
| REQ-39 | `#` 至行末为注释 | ✅ | `unit/lexer.janet`（注释与空行） |
| REQ-40 | 块内换行 = 语句分隔（逐语句镜像、语句间保持书写序） | ✅ | `conformance/req-03-quote.janet`、`unit/translate.janet` |
| REQ-41 | 退出码具体取值（附录 E） | ✅ | `conformance/req-23-exit-codes.janet`、`e2e/cli.sh` |
| REQ-42 | `--serve`：工作区（字典 + 栈）跨请求保留 / 失败不终止 / EOF→0 | ✅ | `e2e/cli.sh` |
| REQ-43 | NDJSON 最小 schema（附录 F） | ✅（最小集） | `e2e/cli.sh` |
| REQ-44 | 字面量是数据、引号是代码（`{ }`/`H{ }` 不参与镜像） | ✅ | `conformance/req-44-literal.janet`、`unit/literals.janet` |
| REQ-45 | 一轮 = `list Stream`；stream 携带标签绑定 | ✅ | `conformance/req-45-46-round.janet`、`unit/stream.janet`（建流即登记） |
| REQ-46 | `Stream → Utter` 显式转换；自动/手动路径共用 | ✅ | `conformance/req-45-46-round.janet`、`conformance/req-16-19-hooks.janet`、`unit/stream.janet` |

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

## M3 词表覆盖（agent / 流 / 钩子 / 收尾）

| 层 | 词 | 栈效应 | 用例 |
|---|---|---|---|
| L3 | `append` | `Utter Agent -- Agent` | C:req-12-13-agent |
| L3 | `session` | `Agent -- Session` | C:req-12-13-agent |
| L3 | `send` | `Utter Agent -- Stream` | C:req-45-46-round、C:req-08-stream |
| L3 | `resend` | `Utter Agent -- Stream` | C:req-12-13-agent（注销后报 31） |
| L3 | `bcast` | `Utter Domain -- list Stream` | C:req-15-bcast |
| L4 | `agent` | `Lab Session -- Agent`（`Lab` 可省） | C:req-12-13-agent |
| L4 | `origin` | `Agent -- origin` | U:agent |
| L4 | `unsubscribe` | `Agent -- Agent`（标记注销） | C:req-15-bcast |
| L8 | `@on` | `Event Quote -- ` | C:req-16-19-hooks |
| L8 | `@off` | `Event [Quote] -- ` | C:req-16-19-hooks |
| L8 | `next` | `Stream -- Chunk\|nil`（消耗） | C:req-45-46-round |
| L8 | `drain` | `Stream -- String` | C:req-08-stream |
| L8 | `utter` | `Stream -- Utter` | C:req-45-46-round |
| L8 | `stop` | `Stream -- Stream` | C:req-45-46-round |
| — | 事件名 `@Start` `@Chunk` `@Fail` `@Error` `@Close` `@Toolcall` `@Done` `@RoundDone` | 字面量 | C:req-16-19-hooks |

**词形次序**（D-26）：消息在前、目标在后（`Utter` 是最左实参 = 栈顶）。
理由见 D-18 推论：栈上已有的值只能落在最右操作数位置，而 agent 是栈上的变量（REQ-30）。

**自动路径 vs 手动路径**（REQ-18 / REQ-19 / REQ-46）：

```breve
# 自动：一轮结束时默认 @RoundDone 做 ①..④
agent "c" { }
dup
send say "你好"
pop
session
```

```breve
# 手动：关掉默认钩子，自己 utter + append
agent "c" { }
@off @RoundDone
dup
send say "你好"
utter
append
```

两条路径的会话**逐条相同**（`C:req-16-19-hooks` 断言）。

## M4 词表覆盖（持久化 / 工作区，L7）

| 层 | 词 | 栈效应 | 用例 |
|---|---|---|---|
| L7 | `read` | `Path -- String`（读不到 40；缺能力 60） | C:req-20-workspace |
| L7 | `write` | `String Path --`（写失败 41；缺能力 60） | C:req-20-workspace、e2e |
| L7 | `current` | `-- Workspace` | C:req-20-workspace |
| L7 | `save` | `Workspace Path --`（非当前工作区 31） | C:req-20-workspace |
| L7 | `load` | `Path -- Workspace`（不存在 40） | C:req-20-workspace、e2e |
| L7 | `compact` | `Workspace --`（未绑路径 60） | C:req-21-compact |

**写读次序**（D-18 推论）：最左实参先被消费，故 `write "内容" "路径"`、`read "路径"`。

**跨进程往返**：

```breve
x : [ * 2 ]
save current "ws.json"
```

```breve
# 另一个进程
load "ws.json"
pop          # 丢掉工作区句柄（load 的结果）
x 21         # → 42（注意：载入进来的词要下一轮才解析得到，见 D-38）
```

**持久化格式（D-33 冻结）**：`<path>` = 单文件 JSON 快照（`kind` / `version` / `dict` / `stack` / `agents`）；
`<path>.log` = JSONL，每轮一行 `{"v","n","defs","stack"}`；末行为半截时**容忍并告警**（崩溃恢复）。
字典只存 **ravel 源**（D-34），宿主序仅用于 `--dump` 对照。

**compact**：① 日志 > 快照 0.5 倍；② 日志 > 1000 条；③ 显式 `compact`。
触发后写新快照、清空日志、计数归零。

## M5 词表覆盖（前端订阅，L9）与 CLI

| 层 | 词 | 栈效应 | 用例 |
|---|---|---|---|
| L9 | `watch` | `Agent -- Stream` | C:req-28-show-watch、C:req-24-duplex |
| L1 | `show` / `print` | `X --`（序列逐元素一行） | C:req-28-show-watch |

**视图流语义（D-42）**：先补历史条目，再随 `append` 吐新增；**不进本轮列表**
（`:agent nil` + `:watch true`），因此默认收尾钩子不会把它并回会话；取尽不 `close`
（它是常驻观察者）。`--serve` 下每次请求处理完 `rb/watch-tick!` 推进各视图流
（每次至多 64 块），块走协议 `chunk` 消息。

**CLI 四形态 + 一个开关**

| 形态 | 命令 | 说明 |
|---|---|---|
| REPL | `ravel` | 提示符 `ravel> `；栈与字典跨行保留；未闭合块自动续行 |
| 一行 | `ravel -e '<源码>'` | 打印剩余栈 |
| 脚本 | `ravel script.breve` | 同上 |
| 服务 | `ravel --serve` | NDJSON over stdio（协议 v1，`docs/PROTOCOL.md`） |
| JSON 输出 | `ravel --json …` | 结果按协议消息形状打到 stdout（REQ-22，D-43） |

**元命令（REQ-25 / D-41）**：保留名表 `quit` / `exit` / `help` / `clear`；都是**裸词**且
**都不是方言词**；`watch` / `save` / `load` 是方言词，因此不在表里（REQ-09）。
协议侧的裸行一律当源码——元命令属于**前端**的命令表（`clear` → `{"type":"reset"}`）。

**输出分流（D-40 / REQ-43）**：`--serve` 与 `--json` 时，方言的 `print`/`show`
改走 stderr，stdout 只承载协议消息。

## 能力层（M3 / M4）

| 能力 | 文件 | 说明 |
|---|---|---|
| `:llm/chat` | `cap/llm.janet` | 按 `RB_LLM`（`mock`/`nvidia`/`auto`）派发 |
| `:json/encode` `:json/decode` | `cap/json.janet` | 唯一 JSON 实现（D-08） |
| `:http/post-lines` | `cap/http.janet` | FIFO + `curl -N`（D-28，核心不含） |
| `:fs/read` `:fs/write` `:fs/append` `:fs/size` `:fs/exists?` | `cap/fs.janet` | L7 词与快照的唯一落盘通道（`--core-only` 时 L7 词报 60） |
| mock provider | `cap/mock.janet` | 离线、确定；`RB_MOCK_REPLY`，按 UTF-8 字符切块（D-31） |
| NVIDIA provider | `cap/nvidia.janet` | OpenAI 兼容 SSE；`RB_MODEL` / `RB_ENDPOINT` / `RB_HTTP_TIMEOUT` |

真机验收：`bash tests/e2e/agent.sh`（无密钥则自动跳过；坏密钥 → 退出码 60，D-27）。

## v1.0d 新增 REQ（47–51）：agent 的基本能力

主题边界：**只补能力，不改语法/执行模型/状态模型/协议骨架**。
验收标准：每项能力都必须由「词 + 钩子 + 流 + 工作区的表」组合出来（§0）。

| REQ | 内容 | 状态 | 测试 |
|---|---|---|---|
| REQ-47 | 角色只是 `Utter` 的字段；`saysys` 糖；`Utter "tool" "x"` 可造任意角色；不新增类型 | ✅ | `conformance/req-47-51-capabilities.janet` |
| REQ-48 | 工具调用：`deftool` / `invoke` / `@Toolcall` / 同一条流继续 / `@off` 后冻结为 `:tool` | ✅ | `conformance/req-47-51-capabilities.janet`、`e2e/cli.sh`（协议 `event`） |
| REQ-49 | 重试在钩子层；`@Fail` 载荷 `Fail Stream`；`resend` 接受 Agent 或 Stream；不装钩子不重试 | ✅ | `conformance/req-47-51-capabilities.janet` |
| REQ-50 | 上下文压缩在钩子层；标准写法 = `take` + `saysys` + 新 `agent`；核心不内置算法 | ✅ | `conformance/req-47-51-capabilities.janet` |
| REQ-51 | 编排边：`->` 血缘、`onfail` 失败回退、`subscribe` 恢复缺省广播域 | ✅ | `conformance/req-47-51-capabilities.janet` |
| — | `seq` / `par` | ❓ 未冻结 | SF-25（不实现：无栈效应/无结果定义） |

决策记录：D-45（工具循环）· D-46（`:tool` 冻结）· D-47（`onfail` / `->` / `subscribe`）·
D-48（重试只靠钩子）· D-49（压缩策略在用户侧）。
