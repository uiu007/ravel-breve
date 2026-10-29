# 符合性矩阵（REQ ↔ 测试）

依据规格：**`ravel-breve-spec-v1.0t.md`**（卡住的后端：工具层超时、提示里的样例必须能跑）；
`ravel-breve-spec-v1.0b.md` … `ravel-breve-spec-v1.0s.md` 为历史原文。
状态：**M20**（词表 L0–L9 + 持久化 L7 + agent / 流 / 钩子 / 收尾 + 工具调用 / 重试 / 压缩 / 编排边 + CLI / NDJSON 协议 v1 已落地；真 NVIDIA provider 已打通）。`✅` = 已有可执行验收；`⏳` = 计划在某里程碑落地；`❓` = 需人工裁决（见 `docs/DECISIONS.md` / `docs/SPEC-FEEDBACK.md`）。

> 注：REQ-01…REQ-38 的编号与 v1.0b 保持稳定；v1.0c 新增 **REQ-39…REQ-46**，
> v1.0d 新增 **REQ-47…REQ-51**（见文末）；**v1.0e 不新增 REQ**（只把 SF-14…SF-35 冻结，见其附录 I）；
> **v1.0f 新增 REQ-52**（处理流程 / 模式，见其 §4.13 与附录 J）；
> **v1.0g 新增 REQ-53 / REQ-54**（文件沙箱、默认工具包，见其 §4.14 与附录 L）；
> **v1.0h 新增 REQ-55 / REQ-56 / REQ-57**（用量记账、取消与传播、流截止时间，见其 §4.15 与附录 M）；
> **v1.0i 新增 REQ-58 / REQ-59**（自定义请求头、模型列表与自动配置，见其 §4.16 与附录 N）；
> **v1.0j 新增 REQ-60 / REQ-61**（插件装载卸载、插件编写 skills 的分层，见其 §4.17 与附录 O）；
> **v1.0k 新增 REQ-62 / REQ-63**（配置预设的导入导出、启动装载，见其 §4.18 与附录 P）；
> **v1.0l 新增 REQ-64**（预制的可发现性，见其 §4.19 与附录 Q）；
> **v1.0t 新增 REQ-73 / REQ-74**（工具的墙钟闸是必需项、超时**当结果**还给模型
> （`RB_SHELL_TIMEOUT`，缺省 60，`<=0` 不限）；写给模型看的调用样例必须能在 REPL 里
> 原样跑通——`ptc` 提示里的 `invoke { … }` 改回 `invoke H{ … }`。见其 §4.13 / §4.15 与附录 Z），
> 依据规格 `ravel-breve-spec-v1.0t.md`，状态 **M21d**。
> **v1.0s 新增 REQ-72**（目录外照抄 pi 的 `contextWindow ?? 128000` / `maxTokens ?? 16384`；
> `est` 两种算法取大者（字节法 vs 字符法）；新词 `catalog` / `catalog-refresh`，
> 「自动更新」是一条可启停的钩子：缺省不装，`@on @Start [ catalog-refresh ]` 才有，`@off @Start` 即关。
> 见其 §4.14 与附录 Y），并随之修订 REQ-71（兜底 32768 → 16384、窗口 0 → 128000、`est` 口径），
> 依据规格 `ravel-breve-spec-v1.0s.md`，状态 **M20**。
> **v1.0r 新增 REQ-71**（模型目录 + `cap/llm-budget`：`min(想要的额度, max(1, 上下文窗口 - 估算输入 - 4096))`，
> 额度来源「显式 > 模型上限 > 兜底 32768」；收尾块补 `:out` / `:max`，`length` 且 `out >= max` = 额度真的用完
> → 立刻 `60`，`out < max` 才算可恢复的截断；预设不再钉 `max-tokens`。见其 §4.14 与附录 X），
> 并随之修订 REQ-70（额度缺省改由模型目录决定、截断判定换 pi 口径）；
> 依据规格 `ravel-breve-spec-v1.0r.md`，状态 **M19**。
> **v1.0q 新增 REQ-70**（能力层交「收尾块」`@{:finish reason :chars n :calls n}`；
> 编排层对 `finish = length` 或「无正文无调用」在**同一轮内续写**，`RB_CONTINUE_MAX` 封顶；
> `max-tokens` 缺省 512 → 8192；`default` 模式补最小系统提示，见其 §4.14 与附录 W），
> **v1.0p 新增 REQ-69**（策略拒绝的请求表、`@Approve` 事件、临时授权 `grant`/`grants`/`ungrant`，
> 见其 §4.14 与附录 V），并随之修订 REQ-17（事件集 8 → 9）与 REQ-53（先查授权）；
> 依据规格 `ravel-breve-spec-v1.0q.md`，状态 **M18**。
> **v1.0o 新增 REQ-68**（工具的参数形状、别名、模型手误回给模型，见其 §4.14 与附录 U），
> 并随之修订 REQ-48 / REQ-54；依据规格 `ravel-breve-spec-v1.0o.md`，状态 **M16**。
> **v1.0n 新增 REQ-67**（工具的前置设定随模式来、设定不满足的工具不上 wire，见其 §4.14 与附录 T），
> 并随之修订 REQ-54 的 `shell` 条款；依据规格 `ravel-breve-spec-v1.0n.md`，状态 **M15**。
> **v1.0m 新增 REQ-65 / REQ-66**（注册与公示分离、正交 plan，见其 §4.13 与附录 S），
> 并按 D-72 **修订 REQ-52**（`ptc` 由「只留一个工具」改为「全都注册、只公示 `eval`」）。

跑法：`make test`（单元 + 符合性 + 端到端 + 附录 D）。

## 测试分层

| 层 | 位置 | 说明 |
|---|---|---|
| 附录 A 覆盖 | `tests/conformance/req-09-appendix-a.janet` | 规格列出的词逐个「认得」；未冻结的（`seq`/`par`/`Json`）显式断言仍报 20 |
| 单元 | `tests/unit/*.janet` | 词法 / 转译等内部不变量 |
| 符合性 | `tests/conformance/req-*.janet` | 逐条 REQ 的验收（文件名即 REQ 号） |
| 端到端 | `tests/e2e/cli.sh` | 真二进制、真退出码、REPL/--serve 管道 |
| 附录 D | `make test-core-only` | 剔除 `cap/` 后核心仍可独立装载并完成主脊 |
| 前端层（**规格外**） | `tests/unit/line.janet` | REPL 行编辑器：Emacs / Vim 键位、模式切换、历史、CJK 退格、扩展点（D-57 / SF-35） |

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
| REQ-37 | 核心不含 net/file/http/crypto，能力走能力层 | ✅ | `conformance/req-37-cap-boundary.janet`、`make test-core-only`、`make test-agent` / `make test-oc`（换 provider 不改方言代码，D-54/D-64）|

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

**持久化格式（D-33 冻结；`llm` 段见 D-54）**：`<path>` = 单文件 JSON 快照
（`kind` / `version` / `dict` / `stack` / `agents` / `llm`）；
`<path>.log` = JSONL，每轮一行 `{"v","n","defs","stack"}`，仅当 provider 配置变化时多带 `"llm"`；
末行为半截时**容忍并告警**（崩溃恢复）。
字典只存 **ravel 源**（D-34），宿主序仅用于 `--dump` 对照。

**compact**：① 日志 > 快照 0.5 倍；② 日志 > 1000 条；③ 显式 `compact`。
触发后写新快照、清空日志、计数归零。

### 规格之外新增的词（D-54 / D-55）

| 词 | 栈效应 | 用例 |
|---|---|---|
| `llm` | `-- Table`（当前工作区的 provider 配置，活表） | U:config、e2e |
| `llm-get` | `Key -- Value`（**生效值**：配置 > 环境变量 > 缺省） | U:config、e2e |
| `llm-set` | `Value Key --`（`nil` = 删除；白名单外 31，`key` 60） | U:config、e2e |

这三个词在 v1.0e 已进附录 A · L2（SF-32 的处置）。

**失败求值的栈语义（D-55）**：一次求值 = 一个事务；出错则栈回到求值前
（副作用不回滚）。故 `+ 1` 在空栈上只报 30，不留半截操作数；
REPL 与 `--serve` 报错后可继续（U:config、e2e:cli）。

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

## v1.0f / v1.0g 新增 REQ（52–54）

| REQ | 内容 | 状态 | 测试 |
|---|---|---|---|
| REQ-52 | 处理流程（模式）：`mode` / `mode-of` 互逆；开关默认全开且不进请求；预制 `ptc`（只有 `eval`） | ✅ | `unit/modes.janet`、`conformance/req-52-modes.janet`、`e2e/cli.sh`（标记）、`examples/12-ptc.breve` |
| REQ-53 | 文件沙箱：根 = 当前目录（`RB_SANDBOX` 换/关），规范化后判定；越界写 41、读 40 | ✅ | `unit/fs-sandbox.janet`、`e2e/cli.sh`（沙箱三条） |
| REQ-54 | 默认工具包：`edit` / `grep` / `glob` / `shell`（能力层 `:tools/install`；`shell` 需 `RB_ALLOW_SHELL=1`）| ✅ | `unit/cap-tools.janet`、`conformance/req-47-51-capabilities.janet`（模型发起 edit）、`e2e/cli.sh` |

决策记录：D-59（模式 ⇄ 钩子）· D-60（文件沙箱）· D-61（默认工具包与 `:mode-tools`）。

## v1.0h 新增 REQ（55–57）

| REQ | 内容 | 状态 | 测试 |
|---|---|---|---|
| REQ-55 | 用量记账：元信息块（不是文本）→ 工作区 `:usage` 累计；`usage` 词读拷贝 | ✅ | `unit/usage.janet` |
| REQ-56 | 取消：`stop` 沿 `->` 血缘传播；`cancel` 词 + 协议 `cancel`（`stopped`，不结束会话）| ✅ | `unit/cancel.janet`、`e2e/cli.sh`（四条）|
| REQ-57 | 流截止时间：`RB_STREAM_DEADLINE_MS`，超时 → 流失败 + 60 | ✅ | `unit/cancel.janet` |

决策记录：D-62（用量记账）· D-63（取消与截止时间）。

## v1.0i 新增 REQ（58–59）

| REQ | 内容 | 状态 | 测试 |
|---|---|---|---|
| REQ-58 | 自定义请求头：配置项 `headers` + `RB_HEADERS`（JSON 对象或 `K:v,…`），归一后**覆盖同名内置头**，对拉模型列表同样生效；坏输入 31 | ✅ | `unit/llm-models.janet`（三条）、`e2e/opencode.sh`（自定义头进真请求）|
| REQ-59 | 模型列表与自动配置：`llm-models` 真请求 `<基址>/models`；`llm-auto` 按 `RB_MODEL_PREFER` > provider 偏好 > 首个选并**写回** `model`；`model = "auto"` 每次解析；mock 不联网 | ✅ | `unit/llm-models.janet`（四条）|

决策记录：D-65（自定义请求头）· D-66（模型列表与自动配置）。

## v1.0j 新增 REQ（60–61）

| REQ | 内容 | 状态 | 测试 |
|---|---|---|---|
| REQ-60 | 插件装载与卸载：插件 = 一个 `.breve` 文件；`plug` / `plugins` / `unplug` 三词全 0 元；装载**不算一轮**、脏栈不外溢、失败**原子回滚**、卸载**精确撤销并还原**被重定义的旧词条、同名重装先卸旧账、插件内再 `plug` → 31、`RB_PLUGINS` 启动按序装载；坏路径 40 / 坏参数 31 / 未装过 20 / 缺能力 60 | ✅ | `unit/plugins.janet`（13 条）、`examples/16-plugins.sh` |
| REQ-61 | 插件编写 skills：`skills/<name>/SKILL.md` + 可选可跑 `plugin.breve`；文档**必须分节**写清**核心层**（不可碰：词法/转译/栈/流/agent/钩子机制/持久化/协议/退出码/核心词表）与**用户层**（可碰：词/钩子/工具/模式），并给出「用户手打」与「打包插件」两条等价路径；`skills/` 不进 bundle | ✅ | `unit/plugins.janet`（技能样板可装可跑）、`examples/16-plugins.sh`、`tools/core-only-check.janet` |

决策记录：D-67（插件 ABI 与 skills）。

## v1.0k 新增 REQ（62–63）

| REQ | 内容 | 状态 | 测试 |
|---|---|---|---|
| REQ-62 | 配置预设：`llm-import NameOrPath -- Table` / `llm-export Path -- Int`（均 0 元）；预设 = JSON 对象，键走 `rb/config-keys` 白名单；名字查 `presets/<名字>.json`；**只覆盖预设里出现的键**；导入经 `:fs/read`（沙箱内）；导出**只导显式配置**；`key` / 未知项 31、密钥型 header 60 且不建文件、读不到 40 | ✅ | `unit/preset.janet`（6 条）、`e2e/cli.sh`（导入/往返/拒绝导出）、`examples/17-presets.sh` |
| REQ-63 | 启动装载：用户配置文件（`RB_CONFIG` 或 `~/.config/ravel/config.json`，存在才装、`-` 关闭）→ `RB_PRESET` → `--preset`（按序覆盖）；在 `rb/new-env` 里先于插件装载；stderr 通报一行；失败即终止启动；测试一律 `RB_CONFIG=-` | ✅ | `unit/preset.janet`（2 条）、`e2e/cli.sh`（`--preset` / `RB_PRESET` / 通报 / `--no-config`）、`examples/17-presets.sh` |

决策记录：D-69（配置预设）。

## v1.0l 新增 REQ（64）

| REQ | 内容 | 状态 | 测试 |
|---|---|---|---|
| REQ-64 | 预制的可发现性：`ravel --presets`（名字 / provider / model / **绝对目录** / 用户配置文件状态）与 `ravel --modes`（名字 / 工具 / 一句说明）；均**只读**（不建工作区、不求值、不装载）、退出码 `0`；空目录仍 `0`；坏预设只影响它那一行；`--core-only` 下 `--presets` → 60、`--modes` 照常；找不到预设时**报错附可用名字**（显式路径只提 `--presets`）；**搜索路径不变**（不做多路径搜索） | ✅ | `unit/preset.janet`（4 条：列表/排序、容错、报错带名字、用户配置路径判据）、`e2e/cli.sh`（13 条：两个开关的 rc 与输出、空目录与坏文件、报错文案、`--core-only` 60）、`examples/17-presets.sh`（⑨⑩⑪） |

决策记录：D-71（可发现性与搜索路径）。

## v1.0m 新增 REQ（65–66）+ REQ-52 修订

| REQ | 内容 | 状态 | 测试 |
|---|---|---|---|
| REQ-65 | **注册 ≠ 公示**：模式表新增 `:wire`（`nil` = 公示全部）；`send` 的 `tools` 只含公示的名字（升序）；不在 `:wire` 里的工具**仍注册着**（`invoke` 与 PTC 程序里可调），并写进提示的「隐藏工具清单」；`ptc` 的 `:tools` = 六默认 + `eval`、`:wire` = `("eval")`；五个预制模式 `default` / `standard` / `ptc` / `minimal` / `cordis`（人格 + 工具集 + `:wire`）；提示模板 `{{model}}` / `{{cwd}}` 每轮现拼 | ✅ | `unit/modes.janet`（REQ-65 四条：wire 呈现层、standard/minimal/cordis、plan 正交、五模式往返）、`unit/cap-tools.janet`（`read` / `write`）、`conformance/req-52-modes.janet`（wire 上只有 `eval`、其余工具仍注册着）、`e2e/cli.sh`（`--modes` 五名字、ptc 程序里 `invoke glob` 回真实结果、minimal 调 `write` → 60） |
| REQ-66 | **plan 正交于预置**：`enter-plan` 打 `plan` 开关 + 登记 `exit_plan_mode`（渐进披露）；`exit-plan` 手动退出；plan 打开时 system 提示 = 模式提示 + plan 段落，**不换模式 / 工具集 / 钩子**；`exit_plan_mode { plan }` 交计划并关开关，不在 plan 时 → 60 | ✅ | `unit/modes.janet`（plan 正交一条：模式名与工具不变、wire 多出 `exit_plan_mode`、提示含 plan 段、退出后复原）、`e2e/cli.sh`（`enter-plan` → `flag "plan"` 为 `true`、`exit_plan_mode` 后为 `false`、`exit-plan` 手动出口） |
| REQ-52（修订）| `ptc` 的表述由「只保留一个工具 `eval`」改为「**wire 上只有一个** `eval`，工具全都注册着」；模式表加 `:wire` | ✅ | `conformance/req-52-modes.janet`、`unit/modes.janet` |

决策记录：D-72（复刻 dsh 四预设 + 呈现层与注册分离 + plan 正交）。

## v1.0n 新增 REQ（67）+ REQ-54 修订

| REQ | 内容 | 测试 |
|---|---|---|
| REQ-67 | 工具的前置设定（`:tools/gates`）随模式声明，缺省配好；设定不满足不上 wire；`--modes` 印设定；装载期告警 | `unit/modes.janet`（「模式的工具与设定自洽」「前置设定不满足的工具不上 wire」）、`unit/cap-tools.janet`（开关两向 + 环境变量覆写）、`e2e/cli.sh`（default 的 shell 开箱即用 / 关掉 → 60 / `RB_ALLOW_SHELL=0` → 60 / `--modes` 印设定）|
| REQ-54（修订）| `shell` 的前置设定是 `allow-shell`（缺省 `true`，随模式来）；关掉后 `invoke` → 60 且不上 wire | 同上 |

## v1.0o 新增 REQ（68）+ REQ-48 / REQ-54 修订

| REQ | 内容 | 测试 |
|---|---|---|
| REQ-68 | 公示的工具必须带具体 `parameters`；参数别名（`command` = `cmd` …）；模型发起的调用里**参数错误**作为 `role=tool` 的结果回给模型、本轮继续；环境侧失败与 `invoke` 仍 `60` | `conformance/req-68-tool-args.janet`（8 条）、`e2e/cli.sh`（7 条：别名成功、错参数名仍 0、会话里有「接受：」、`invoke` → 60、越界 → 60）|
| REQ-48（修订）| 「工具失败 → 60」只适用于环境侧失败与脚本路径；模型发起的参数错误走回话通道 | 同上 |
| REQ-54（修订）| 六个工具参数名附别名表；`parameters` 的形状要求归 REQ-68 | 同上 |

## v1.0p 新增 REQ（69）+ REQ-17 / REQ-53 修订

| REQ | 内容 | 测试 |
|---|---|---|
| REQ-70 | 每次 provider 响应先交收尾块 `@{:finish reason :chars n :calls n}`（`length` = 被输出上限截断）；`calls = 0` 且（`length` 或 `chars = 0`）→ **同一轮内**追加 `:continue true` 的 user 提示并重发，流接着吐；上限 `RB_CONTINUE_MAX`（缺省 3，`0` = 关），用尽 → `60` 且点名 `RB_MAX_TOKENS` 与「推理与正文共用预算」；工具批（`calls > 0`）不续写；`max-tokens` 缺省 8192；`default` 带最小系统提示 | `conformance/req-70-continue.janet`（9 条）、`unit/config.janet`、`unit/modes.janet` |
| REQ-69 | 策略拒绝带请求表（`:rb-denied` + `:rb-request`：`kind`/`path`/`dir`/`root`/`op`）；模型发起的调用先发 `@Approve`（载荷 `Request Stream`），钩子写 `:decision` + `:grant`；允许 → 登记临时授权并**重试一次**，拒绝 → `60` 且消息点名退路；授权带 `uses`（`nil` = 到工作区结束）、按目录段对齐、`reset` 清空；`grant`/`grants`/`ungrant` 与裁决词 `accept`/`accept-dir`/`reject`；`invoke` 不走审批；非交互默认拒绝；`@off @Approve` 回到旧行为 | `conformance/req-69-approve.janet`（10 条）、`e2e/cli.sh`（6 条：`grant` 后越界读 → 0、非交互 → 60、消息含 `grant`、自动批准 → 0、`invoke` → 60、`RB_SANDBOX=none` → 0）、`examples/19-approve.breve` |
| REQ-17（修订）| 事件集 8 → **9**：新增 `@Approve`（第 9 个），缺省工作区就有默认审批钩子 | `unit/events.janet`、`unit/modes.janet`、`conformance/req-52-modes.janet`（事件数 9）；`conformance/req-69-approve.janet`（缺省钩子在位）|
| REQ-53（修订）| 沙箱判定先查临时授权（`@Approve` / `grant`），命中即放行并消耗一次 `uses`；未命中才抛带标记的拒绝 | `conformance/req-69-approve.janet`（请求表字段、授权放行、`uses` 用完即销）|

## v1.0r 新增 REQ（71）+ REQ-70 修订

| REQ | 内容 | 测试 |
|---|---|---|
| REQ-71 | 输出额度按模型与上下文算：`cap/model-catalog`（`deepseek-v4.1-flash` = 1e6 上下文 / 384000 输出）+ `cap/llm-budget`（`want` = 显式 > 目录 > 兜底 32768，再 `min(want, max(1, window - est - 4096))`）；请求体的 `max_tokens` 取自它；收尾块补 `:out`（`usage.completion_tokens`）与 `:max`；`length` 且 `out >= max` → 立刻 `60` 并点名 `out/max`；目录外模型兜底 32768；`RB_DEBUG_BUDGET` 可观测 | `conformance/req-71-budget.janet`（8 条）、`unit/config.janet`（兜底 32768）、`unit/preset.janet`（自带预设不写 `max-tokens`）、`examples/21-budget.sh`（5 步）|
| REQ-70（修订）| 续写判定换成 pi 的 `isRecoverableLength`：`length` 且 `out < max`（或 `out` 缺）才算可恢复；`out >= max` 不再空转三次，直接 `60`；`max-tokens` 8192 的缺省由 REQ-71 的模型目录接管（8192 只留在 REQ-70 的历史描述里）| 同上 + `conformance/req-70-continue.janet`（8 条，删掉「缺省 8192」那条）|
| REQ-62 / REQ-63（修订）| 仓库自带预设只写 provider / model / temperature，不再钉 `max-tokens`（导入语义不变）| `unit/preset.janet`、`e2e/cli.sh`（预设验模型名）|

## v1.0s 新增 REQ（72）+ REQ-71 修订

| REQ | 内容 | 测试 |
|---|---|---|
| REQ-72 | ① 目录外/没核过的模型：`:max-tokens 0`（不知道）+ 窗口 `128000`（pi 的 `contextWindow ?? 128000`），额度落兜底 `16384`（pi 的 `maxTokens ?? 16384`），`source` 记 `:fallback`；② `cap/est-text-tokens`（由 `cap/est-tokens` 调用）**两种算法取大者**：字节法 `ceil(字节÷4)` vs 字符法 `ceil(ASCII÷4) + ceil(非ASCII字节÷3)`；③ 新词 `catalog`（`-- Table`，目录副本）与 `catalog-refresh`（`-- Int`，拉 `/models` 只登记没见过的名字，`:max-tokens 0` + 窗口 128000，不改已核过的数，幂等）；④ **自动更新 = 一条可启停的钩子**：缺省不装在任何事件上，`@on @Start [ catalog-refresh ]` 才有，`@off @Start` 即关；⑤ mock provider 也打 `BUDGET|` 行（`RB_DEBUG_BUDGET=1`）| `conformance/req-72-catalog.janet`（6 条）、`conformance/req-71-budget.janet`（改断言 16384/128000）、`unit/config.janet`（兜底 16384）、`examples/22-catalog.sh`（5 步）、`examples/21-budget.sh`（数字）|
| REQ-71（修订）| 兜底 `32768` → `16384`；目录外窗口 `0` → `128000`（夹紧对所有模型生效）；`est` 由「JSON 字节 ÷ 4」改为两种算法取大者；验收标准指向 `req-72-catalog.janet` | 同上 |

## v1.0t 新增 REQ（73 / 74）

| REQ | 内容 | 测试 |
|---|---|---|
| REQ-73 | **工具的墙钟闸是必需项，超时是结果不是消失**：方言单线程，`shell` 干等子进程会把进程（连同桥）钉死，`cancel` 也排在同一线程后面；因此在**工具层**设闸——`RB_SHELL_TIMEOUT`（秒，缺省 60，`<= 0` = 不限，回归旧行为），用 `timeout -k 5 -s TERM` 包住 `sh -c`，退出码 `124/137` 时把 `[超时 Ns，已杀掉；要更久就设 RB_SHELL_TIMEOUT=<秒>（<=0 不限）]` **当工具结果压回栈**（不是抛错、不是消失）；系统没有 `timeout` 命令时退回旧行为；正常失败仍是 `[退出码 N]`，两种文本可分 | `unit/cap-tools.janet`（`RB_SHELL_TIMEOUT=1` + `sleep 30` → 8 秒内返回且结果点名超时、正常命令照旧、`=0` 拿掉闸）|
| REQ-74 | **写给模型看的样例必须能在 REPL 里原样跑通**：`ptc` 的系统提示、隐藏工具清单的「调用形式」、`eval` 工具描述三处都曾写 `invoke "名字" { … }`，但本方言 `{ … }` 是序列/广播域，表是 `H{ … }`（照提示写 → 栈下溢 → 整轮白跑，人却看到「没输出」）；三处统一改 `H{ … }` 并注明区别，且**必须有测试把样例原样送进求值器** | `conformance/req-52-modes.janet`（提示里是 `H{`、不是 `{`；`invoke "shell" H{ "cmd" "echo hi" }` 真的返回 `hi`）|
