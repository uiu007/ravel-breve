# ravel breve 开发计划（v1.0b 规格 → 可运行实现）

> 依据：`ravel-breve-spec-v1.0b.md`（定稿）
> 目标：把 Spec 的 REQ-01…REQ-38 逐条落成**可验收**的实现，全程保持「复杂度可见、可裁决」。
> 本文件是开发契约：阶段划分、交付物、验收命令、**人工检查点（CHK）**、待裁决问题。

---

## 0. 总原则

1. **规格即验收**：每条 REQ 必须有一个可执行测试（`tests/conformance/`），映射表写入 `docs/CONFORMANCE.md`。
   无法写成测试的 REQ，说明规格仍有歧义 → 记入 `docs/DECISIONS.md`，在最近的人工检查点裁决。
2. **镜像优先**：先打通「切词 → 递归反转 → 换名 → 栈原语」这条主脊，其余全部挂在它上面。
3. **核心极小**：核心词表（方言层）不出现 net / file / http / crypto / JSON 解析实现（附录 D 验收）。
4. **复杂度可见**：转译产物可 `dump`、自动行为可 `@off`、隐含规则（续行/回合收尾）有明文与关闭手段。
5. **不猜**：Spec 标注 ❓ 或未冻结者（provider 选择、Janet 补丁版本、`H{}` 细节、前端按键）一律在检查点请用户裁决，不自行冻结。

---

## 1. 目录结构（提案）

```
RavelBreve/
├── ravel-breve-spec-v1.0b.md      # 规格（只读；修订提案写 docs/SPEC-FEEDBACK.md）
├── PLAN.md                        # 本文件
├── Makefile                       # make / make test / make dist / make clean
├── vendor/janet/                  # janet 1.42.x amalgam（janet.c, janet.h, VERSION 钉死）
├── src/main.c                     # 宿主入口：嵌入 bundle、启动 CLI、退出码
├── rb/                            # 方言层（Janet 源码，随宿主静态嵌入）
│   ├── lexer.janet                # 切词 / 括号 / 长字符串 / 续行
│   ├── translate.janet            # 递归反转 + 换名表 + 定义行识别 → dump 产物
│   ├── runtime.janet              # fiber-local 数据栈 + ~10 栈原语
│   ├── dict.janet                 # 字典（词名 → 定义 + 文档串），doc/see，重定义告警
│   ├── words/l0…l9.janet          # 词表实现（按层分文件）
│   ├── stream.janet               # Stream ≡ fiber：next/drain/stop + 事件
│   ├── hooks.janet                # @on/@off + 8 事件 + 默认 @RoundDone 收尾
│   ├── agent.janet                # agent/send/bcast/resend/origin/watch + 广播域通配符
│   ├── workspace.janet            # 快照 + JSONL 增量日志 + compact 三条件
│   └── cli.janet                  # REPL / -e / script / --serve(NDJSON) / 元命令 / 退出码
├── cap/                           # 能力层（provider 可换；核心不依赖具体 provider）
│   ├── provider.janet             # Endpoint/Head + NDJSON 边界契约
│   ├── native.janet               # 首发：同进程 Janet（net/file/ev）
│   └── lua/                       # 可选：外部进程 provider（协议不变）
├── bin/ravel                      # 启动器
├── tests/
│   ├── conformance/req-XX-*.janet # 每条 REQ 的验收测试
│   ├── unit/                      # 词法/转译/栈 单元测试
│   ├── e2e/                       # 编排端到端（mock provider）
│   └── run.janet                  # 测试运行器（输出 TAP 风格）
├── tools/embed.janet              # 生成 build/rb_bundle.c（amalgamated 静态嵌入）
└── docs/
    ├── CONFORMANCE.md             # REQ → 测试 映射矩阵（活文档）
    ├── PROTOCOL.md                # NDJSON over stdio 协议（REQ-24/25）
    ├── DECISIONS.md               # 待议项与裁决记录（含 ❓ 项）
    └── SPEC-FEEDBACK.md           # 实现中发现的规格问题 → 供附录 B 下一版
```

---

## 2. 阶段、交付物与人工检查点

> 每个检查点都是**硬闸门**：未通过不进入下一阶段。检查点给出「评审材料 + 一键验收命令 + 需裁决问题」。

### M0 · 环境与构建骨架
**覆盖**：REQ-38（Janet 1.42.x / amalgamated 静态嵌入）、REQ-23（退出码骨架）。
**交付**
- `vendor/janet/` 拉取并钉死 `1.42.x`（记录 commit/tarball 校验和到 `vendor/janet/VERSION`）。
- `Makefile`：`make` 产出 `bin/ravel`；`tools/embed.janet` 生成 `rb_bundle.c`（所有 `rb/**` 源码拼接 + `janet_dobytes`）。
- `src/main.c`：解析 CLI 形态，退出码表骨架，NDJSON server 空实现（只回 `{"ok":true}`）。
- `git init`（仓库内独立 git）+ 首次提交 + tag `m0`。
**验收命令**：`make clean && make && make test && ./bin/ravel -v && ./bin/ravel --dump -e 'take 2 "abcde"' && ./bin/ravel -e 'take 2 "abcde"'`
**CHK-0 评审材料**：`docs/CHK-0.md`（含实测输出与待裁决问题）
**CHK-0 需裁决**
1. 是否允许 vendor Janet 源码进仓库（体积 ~1.5MB）？或改为构建时下载 + 校验和？
2. 是否在 `RavelBreve/` 内独立 `git init` 并按阶段打 tag？（父目录 `/home/uiu` 本身是 git 仓库，RavelBreve 未被跟踪）
3. Janet 钉到 `1.42.0` 还是 `1.42.x` 最新补丁（附录 C 待议）？
4. 文档与提交信息用中文？（默认：中文）

---

### M1 · 主脊：词法 → 转译 → 栈运行时 → 定义行
**覆盖**：REQ-01,02,03,04,05,30,31,32,33,34,35 + L0、L1b 最小集。
**交付**
- `lexer.janet`：RTL 切词、`"…"` 字符串、`[ ]` 引号块、`{ }` / `H{ }` 序列、长/原样字符串（v0.13：可变引号数、`''` 转义）、行末 `\` 续行、**未闭合块自动续行**、注释。
- `translate.janet`：括号内**递归反转**（括号不参与）、换名表（一张表）、定义行识别 `名字 : [ 体 ]`（**元层不参与镜像**）、产物可打印。
- `runtime.janet`：`(dyn :rb-stack)` fiber-local 栈 + `push/pop/dup/swap/rot/-rot/keep/dip/apply`。
- `dict.janet`：注册/查询/文档串、`doc`/`see`、重定义**覆盖并告警**。
- 引号压栈不求值，仅组合子触发（REQ-32）。
**验收命令**：`make test`（单元 60 / 端到端 21 / core-only 全绿），含：
`take 2 "abcde"` → `"ab"`；`- 5 3` → `2`；`= 3 3` → `true`；
`double : [ * 2 ]` 单独执行栈不变且 `double 5` → `10`；
`--dump` 输出 `(do (rb/push "abcde") (rb/push 2) (rb/take))` 形状；
两路并发 eval 栈互不污染。
**注**：M1 的验收测试已在 M0 内一并落地（主脊就是 M0 的交付内容）。
**CHK-1 需裁决**：镜像语义与边界（引号内 RTL、定义行例外、`{ }`/`H{ }` 是否参与反转）逐例确认。

---

### M2 · 词表 L0–L5
**覆盖**：REQ-06…REQ-11、REQ-25、REQ-32。
**交付**
- L1 多态序列/文本/连接（含 `,` `,,`、`take`/`drop` 四象限、`map/filter/fold`、`zip`、`show/print` 逐元素）。
- L1b/L1c/L1d：布尔比较算术、字符串工具、类型转换。
- L2 消息与 JSON：`say`/`Utter`/`to-json`/`from-json`（实现走能力层 provider，核心不含 JSON 解析）。
- L5/L5b：`if/when/unless/loop/while/try/recover`、`fail/assert/depth/dump/now/env`。
- `docs/CONFORMANCE.md` 建立：每个词 → 用例。
**验收命令**：`make test -- --layer l0,l1,l1b,l1c,l1d,l2,l5`；多态一致性用例（同一词对 `String`/`Session` 行为一致、返回新值）。
**CHK-2 需裁决**：词表覆盖报告（✅ 已实现 / ❓ 待议）；`H{ }` 嵌套与重复键语义（附录 C 待议项）；`min`/`max`/`sum` 归位。

---

### M3 · 会话、agent、钩子、流
**覆盖**：REQ-08、REQ-12…REQ-19、REQ-36。
**交付**
- `Session` 线性追加日志（REQ-12）；无任何就地编辑词（负面测试：`insert/remove/move` 不在词表）。
- `agent <Label> <Session> [ quot ]` 派生新 agent + 内部血缘；仅 `origin` 对外（REQ-13/14）。
- 广播域：`{ "id1" "coder*" }` + `*`/`?` 通配符，缺省全部未注销（REQ-15）。
- `hooks.janet`：`@on`/`@off` + 8 事件；默认 `@RoundDone` 收尾顺序 **stream → 合并进 session → 退订 → 删 stream**（REQ-18）；`@off @RoundDone` 可禁用（REQ-19）；工具调用中断**不**触发 `@RoundDone`。
- `stream.janet`：`Stream ≡ fiber`，chunk 到达即 yield/flush 并发 `@Chunk`；`next/drain/stop`；异常 → `@Fail`/`@Error`。
- mock provider（确定性脚本化回复）用于端到端。
**验收命令**：`make test -- --req 08,12..19,36`；`tests/e2e/round-trip.janet`（一轮结束后 agent 无残留 stream、session 已含回复、事件序列快照比对）。
**CHK-3 需裁决**：钩子时序表逐行核对；`@Close` vs `@Done` 触发条件；工具调用中断语义确认。

---

### M4 · 持久化与工作区
**覆盖**：REQ-20、REQ-21。
**交付**
- 版本化单文件 JSON 快照 + JSONL 增量日志（含 `agents` 血缘字段）。
- `save/load/current/compact`（`read/write` 经能力层）。
- compact 三条件：日志 > 快照 0.5 倍（主判据）/ 日志 > 1000 条 / 显式调用。
- 崩溃恢复用例（半行 JSONL 容错）。
**验收命令**：`make test -- --req 20,21`；阈值边界测试（0.5x−ε / 0.5x+ε / 1000±1）。
**CHK-4 需裁决**：快照与日志**格式冻结**（字段名、版本字段、半行容错策略）——附录 C 明确留待实现期定。

---

### M5 · CLI 与前后端分离
**覆盖**：REQ-22…REQ-25。
**交付**
- `ravel`（REPL，提示符 `ravel> `）/ `ravel -e "<一行>"` / `ravel script.breve` / `ravel --serve`。
- `--serve`：**NDJSON over stdio**，同一进程内**收 `eval` 与推 `stream`/`event` 互不阻塞**（REQ-24 验收）。
- 退出码分级全表：0/1/2/10–19/20–29/30–39/40–49/50–59/60–69/70+，每类至少 1 个测试。
- 元命令：**无前缀裸词** + 保留名表；分界由编辑器 minibuffer 承担（REQ-25）。
- `docs/PROTOCOL.md`：消息类型、字段、示例会话、背压策略。
**验收命令**：`make test -- --req 22..25`；`tests/e2e/duplex.janet`（前端持续收 stream 的同时连发 eval，断言无阻塞、顺序正确）；退出码矩阵。
**CHK-5 需裁决**：**NDJSON 协议冻结**（消息 schema、错误对象、流式分片粒度）。

---

### M6 · 能力层（net / file 外置）
**覆盖**：REQ-37 + 附录 D 验收。
**交付**
- `cap/provider.janet` 契约（`Endpoint`/`Head` + NDJSON）；首发 `native.janet`（同进程 `net`/`file`/`ev`，C 级零 IPC）。
- 可选外部进程 provider 骨架（Lua），**协议不变**；切换 provider **不改任何方言代码**（验收）。
- 核心边界测试：符号扫描确认核心产物**无 socket/文件系统调用**；删除 `cap/` 后核心仍可完成「切词 → 反转 → 栈求值 → 会话编排」（仅失外部 IO）。
- 至少一个真实 provider 用例：OpenAI 兼容 HTTP endpoint（需用户提供可达 endpoint 或本地 mock server）。
**验收命令**：`make test -- --req 37 --boundary`；`make dist-core-only && make test -- --core-only`。
**CHK-6 需裁决**：首发 provider 范围（是否含真实 HTTP LLM endpoint）；JSON provider 归属（vendored `spork/json` vs 自写 vs 外部进程）。

---

### M7 · 编辑器前端 + 全量符合性复核
**覆盖**：REQ-26…REQ-29 + REQ-01…REQ-38 全量复核。
**交付**
- 前端首发 1 个（Emacs 或 Neovim，待裁决）：
  - 底栏显示当前 token 序列（字符串占位 `"…"`，**不含内容**）；
  - 主 buffer = agent 会话视图（Session 顺序 + 末尾最新 stream），切换 agent 显示来源树（编辑器内部渲染）；
  - `show` 普通 list 打印 / `watch` 语法糖；**运行中标记由渲染层附加**；
  - 按键 `t`→`take`、`s`→`say`+字符串编辑模式、`c`→清空主 buffer。
- `docs/CONFORMANCE.md` 收口：REQ-01…38 全绿 + 负面测试（§4.9.6 Forth 特性、会话编辑词、来源树词 均不得出现在词表）。
- `docs/SPEC-FEEDBACK.md` → 供规格升到 v1.1 的修订纲要（对齐附录 B 体例）。
**验收命令**：`make test`（全量）+ 手工前端演示脚本。
**CHK-7 需裁决**：前端平台；演示是否满足「一边看输出、一边继续写」；是否发起 v1.1 规格修订。

---

## 3. 检查点一览

| CHK | 阶段 | 评审材料 | 需用户裁决（关键项） |
|---|---|---|---|
| CHK-0 | M0 | 构建可复现 + 版本钉死记录 | vendor 策略、git/tag 策略、Janet 补丁版本、文档语言 |
| CHK-1 | M1 | 镜像语义演示（含 `dump` 产物） | 引号/定义行/`{}` 的镜像边界 |
| CHK-2 | M2 | 词表覆盖报告 + 逐词用例 | ❓ 词、`H{}` 语义 |
| CHK-3 | M3 | 钩子时序快照 + 端到端 mock 编排 | `@RoundDone`/`@Toolcall`/`@Close` 语义 |
| CHK-4 | M4 | 快照/日志样例文件 | **持久化格式冻结** |
| CHK-5 | M5 | 协议文档 + duplex 测试 | **NDJSON 协议冻结** |
| CHK-6 | M6 | 边界扫描报告 + provider 切换演示 | provider 范围、JSON 归属 |
| CHK-7 | M7 | 符合性矩阵全绿 + 前端演示 | 前端平台、是否发 v1.1 |

**闸门规则**：每个 CHK 需用户明确「通过 / 打回 + 修改点」。打回则在本阶段迭代，不改动后续阶段范围；跨阶段问题记入 `docs/DECISIONS.md` 与 `docs/SPEC-FEEDBACK.md`。

---

## 4. 风险登记（实现前已知）

| # | 风险 | 影响 | 对策 |
|---|---|---|---|
| R1 | Janet 是前缀变参非栈式（REQ-02 已修正）→ 方言层必须自带栈运行时 | 转译复杂度上升 | M1 先把 `dump` 产物钉成可读文本，再扩词表 |
| R2 | 递归反转的边界（引号内 RTL vs 定义行不参与镜像）易错 | 语义静默错误 | 边界用例先行（M1 测试），每个边界一例 |
| R3 | `Session` 写时复制（附录 C） | 大 session 性能 | M3 先语义正确，千条级实测；O(1) 方案延后 |
| R4 | NDJSON 双向不阻塞需真正并发（fiber/ev） | 无法满足 REQ-24 | M5 用 duplex 测试作硬闸门 |
| R5 | Janet 无内置 JSON；核心不得含 JSON 解析（附录 D） | 归属争议 | CHK-6 裁决；默认：核心只留词，实现走 provider |
| R6 | fiber-local 栈的隔离在 `--serve` 多路 eval 下需验证 | 栈串扰 | M1 起就有并发栈隔离测试（REQ-30） |
| R7 | Spec 中 ❓ / 未冻结项多 | 反复返工 | 集中在检查点裁决，先实现无争议部分 |
| R8 | 父目录 `/home/uiu` 是 git 仓库且含坏 submodule | git 操作干扰 | RavelBreve 内独立 `git init`，所有操作限定子目录 |

---

## 5. 里程碑依赖

```
M0 ──> M1 ──> M2 ──> M3 ──> M4 ──> M5 ──> M7
                              └──> M6 ──┘   (M6 可在 M3 后并行)
```
M6（能力层）依赖 M3 的 Stream/agent 抽象；M7 依赖 M5 的协议与 M6 的 provider。

---

## 6. 现在需要你确认的问题（CHK-0 前置）

1. 计划与阶段划分是否认可？有无需要增删的阶段？
2. vendor Janet 进仓库 vs 构建时下载（校验和钉死）？
3. 在 `RavelBreve/` 内独立 `git init` + 阶段 tag，可以吗？
4. Janet 钉 `1.42.0` 还是 `1.42.x` 最新补丁？
5. 前端首发平台（Emacs / Neovim / VS Code）？
6. 是否有真实 LLM endpoint（或先用本地 mock）用于 M6？
7. 文档与提交信息默认中文，可以吗？

确认后我从 **M0** 开始，到 **CHK-0** 停下等你评审。
