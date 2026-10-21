# ravel breve

**波兰（前缀）式书写、类 Forth 栈机执行**的 **agent 会话编排方言**，宿主为 Janet 1.42.x（amalgamated，静态嵌入）。

- 命令：`ravel`，脚本扩展名 `.breve`，提示符 `ravel> `
- 规格（现行）：`ravel-breve-spec-v1.0d.md`（agent 基本能力定稿，待 CHK-6 追认）；
  `ravel-breve-spec-v1.0c.md` / `ravel-breve-spec-v1.0b.md` 保留为历史（不删改）
- 规格反馈（缺陷/留白）：`docs/SPEC-FEEDBACK.md`
- 开发计划与检查点：`PLAN.md`

## 构建与验收

```sh
make                 # 构建 bin/ravel（vendor/janet 静态嵌入）
make test            # 单元 + 符合性 + 端到端 + 附录 D（core-only）
make check-vendor    # 校验 vendor/janet 的 sha256
bash tests/e2e/agent.sh  # 真 provider 验收（NVIDIA；无密钥则跳过）
```

验收现状：**M6**（词表 L0–L9 + 持久化 + CLI / NDJSON 协议 v1 + agent 基本能力：
工具调用 / 收尾钩子重试 / 上下文压缩 / 编排边）。
`make test` → 292 单元/符合性 + 80 端到端 + core-only 全绿；`make test-agent` → 真 NVIDIA 10/0。

```sh
make clean && make
./bin/ravel -v                         # ravel breve 1.0d · janet 1.42.1
./bin/ravel --dump -e 'take 2 "abcde"' # (do (rb/push "abcde") (rb/push 2) (rb/take))
./bin/ravel -e 'take 2 "abcde"'        # "ab"
./bin/ravel -e 'map [ * 2 ] { 1 2 3 }' # (2 4 6)
./bin/ravel -e 'filter [ < 2 ] { 1 2 3 4 }' # (3 4)
./bin/ravel -e 'at "a" H{ "a" 1 }'     # 1
./bin/ravel -e 'to-json H{ "a" 1 }'    # "{\"a\":1}"（CLI 打印字符串带引号）
```

## 用法

```sh
ravel                       # REPL（栈跨行保留）
ravel -e '<一行>'            # 求值一行并打印剩余栈
ravel script.breve          # 执行脚本
ravel --serve               # NDJSON over stdio（前后端分离，REQ-24）
ravel --json ...            # 结果按协议消息形状输出（REQ-22）
ravel --dump ...            # 打印转译产物（REQ-31）
ravel -v | -h
```

REPL 的元命令是**裸词**（REQ-25）：`help` / `clear` / `quit` / `exit`。
它们**不是方言词**（在代码里写 `help` 是 20 未知的词）——`watch`、`save`、`load` 是方言词，故不在此列。

## 方言要点

```breve
take 2 "abcde"        # 第一个操作数 2，第二个 "abcde"  →  "ab"
- 5 3                 # 第一个操作数减第二个          →  2
= 3 3                 # →  true
3 3 =                 # 非法波兰式（= 左侧无操作数）→ 栈下溢 30
double : [ * 2 ]      # 定义行（元层，不参与镜像）
{ 1 2 3 }             # 字面量：数据，不参与镜像（REQ-44）→ tuple (1 2 3)
H{ "a" 1 }            # 映射字面量 → table @{"a" 1}
[ * 2 ]               # 引号：延迟代码，只由组合子触发（REQ-32）
map [ * 2 ] { 1 2 3 } # → (2 4 6)
filter [ < 2 ] { 1 2 3 4 }  # 引号被补成 `< 2 元素` → (3 4)
if > 5 3 [ "big" ] [ "small" ]  # → "big"
try [ 7
fail "boom" ] [ to-string ]     # 分语句：7 先入栈 → 栈 [7 "boom"]
```

> ⚠️ **最易误读的一条**：组合子的引号是**未写满的波兰表达式**，隐藏实参补在**最右**。
> `filter [ < 2 ] seq` 即 `< 2 元素`（第一个操作数 2、第二个操作数 元素）。
> 直接推论：**栈上已有的值只能落在最右操作数位置**；要让它当第一个操作数就 `swap`。
> 详见 `docs/DECISIONS.md` D-18 与 `docs/SPEC-FEEDBACK.md` SF-12。
double 5              # →  10
apply [ * 2 ] 21      # 引号压栈即数据，由组合子触发 → 42
```

规则：**语法 = 波兰（前缀）表达式；执行 = 类 Forth 栈机**。
由此得**唯一方向规则**：**最左实参 = 第一个操作数 = 栈顶 = 先被消费**。
实现走**镜像原理（前缀 → 后置转换）**：`切词 → 递归镜像 → 换名 → 宿主求值`，无字节码、无自研 VM（REQ-02）。

## agent 编排（M3）

```breve
agent "coder" { }             # 开一个 agent（栈上的变量）
dup
send say "用一句话说你好"      # 发消息 → 产物是 Stream（不回写会话）
pop                           # 丢掉流句柄；收尾钩子仍会把它并回会话
session                       # → 会话：用户那条 + 助手回复
```

一轮结束（每条语句/每个请求）时默认 `@RoundDone` 钩子对**每个 stream** 做四步：
**① 解析绑定 → ② `Stream → Utter` → ③ `append` 进 agent → ④ 退订并删 stream**（REQ-18）。

不想自动合并就关掉它，手动走同样两步（结果与自动路径逐条相同，REQ-19/REQ-46）：

```breve
agent "coder" { }
@off @RoundDone
dup
send say "你好"
utter                         # Stream → Utter（唯一转换）
append                        # Utter → 追加进 agent 会话
```

流是**惰性、逐块**的，可以自己拉（REQ-08 / REQ-36）：

```breve
agent "coder" { }
@on @Chunk [ show ]           # 每块到达即打印（到达即 flush）
send say "数到三，用空格分隔"
drain                         # → 全文
```

广播（带可选域，支持 `*` / `?`，缺省全部未注销 agent，REQ-15）：

```breve
agent "coder1" { }
agent "coder2" { }
agent "reviewer" { }
bcast say "hi" { "coder*" }   # → list Stream（2 个）
```

真机 provider：把密钥放进 `secrets/nvidia.key`（已在 `.gitignore`，不入库）或 `NVIDIA_API_KEY`；
`RB_LLM=mock` 走离线确定性 provider，`RB_MODEL` 换模型。`make test` 全程离线，
`bash tests/e2e/agent.sh` 才是真机验收（无密钥自动跳过）。

## 持久化与工作区（M4）

**工作区 = 字典（函数与常量）+ 栈（变量）**（REQ-30）。两半都可落盘、可复原：

```breve
x : [ * 2 ]                    # 字典
42 "hi"                        # 栈（镜像后栈顶是 42）
save current "ws.json"         # 单文件 JSON 快照
```

另一个进程（或下次启动）：

```breve
load "ws.json"                 # → 工作区句柄（Path -- Workspace）
pop                            # 句柄用完丢掉
x 21                           # → 84：字典与栈都回来了
```

- 落盘格式（D-33）：`ws.json` = 快照（`kind`/`version`/`dict`/`stack`/`agents`），
  `ws.json.log` = **JSONL 增量日志**，每轮一行；写日志时崩溃留下的**半行会被容忍**并告警。
- 字典只存 **ravel 源**，载入时重新转译（D-34）——文件里没有宿主机序。
- `compact` 三条件（REQ-21）：① 日志 > 快照 0.5 倍；② 日志 > 1000 条；③ 显式 `compact current`。
  小工作区会因此频繁 compact（D-37，已提 SF-18）。
- **载入进来的词下一轮才解析得到**（转译先于执行，D-38）：`load` 之后的同一轮里调新词会报 20。
- 核心不碰文件：`read` / `write` / `save` / `load` / `compact` 全部经 `:fs/*`、`:json/*`
  能力键；`--core-only` 时报 60。

## agent 的基本能力（M6 / v1.0d）

新能力**全部由「词 + 钩子 + 流 + 工作区的表」组合出来**，没有新语法、没有新类型：

```
# 工具调用（REQ-48）：注册 → 模型自己决定何时调 → 同一条流继续吐文本
deftool "add2" "把 a 加 2" [ at "a"
+ 2 ]
invoke "add2" H{ "a" 40 }          # 42（手动调用；自动执行由 @Toolcall 的默认钩子做）

# 重试（REQ-49）：@Fail 载荷 = 失败流，resend 接受 Agent 或 Stream
@on @Fail [ pop resend pop ]

# 上下文压缩（REQ-50）：截近几轮 + system 摘要 + 新 agent（新血缘，不动老会话）
@on @RoundDone [ pop take -4 session pop saysys pop dup agent "sum" { } pop ]
```

- 角色只是 `Utter` 的字段（REQ-47）：`saysys "你是助手"`、`Utter "tool" "42"`。
- 模型发起工具调用 → 一条 `event` 消息（协议 3.4）→ 默认钩子跑工具 → 结果以 `role:"tool"`
  追加 → **重发同一个流**。`@off @Toolcall` 后流停在 `:tool`（「待外部动作」），
  前端可用 `invoke` + `append` + `resend` 接管（D-45 / D-46）。
- 编排边（REQ-51）：`->`（血缘）、`onfail`（失败回退引号）、`subscribe`（恢复缺省广播域，
  推翻 D-44）。`seq` / `par` 未冻结 → 不实现（SF-25）。

## 前后端分离与协议（M5）

编辑器只是前端（渲染 + 输入），`ravel --serve` 是唯一求值者，两者用 **NDJSON over stdio**（协议 v1，
见 `docs/PROTOCOL.md`、`docs/FRONTEND.md`）：

```sh
$ printf '%s\n' '{"type":"ping"}' 'agent "c" { }' '{"type":"eval","src":"+ 1 2","id":7}' | ravel --serve
{"protocol":1,"type":"pong"}
{"ok":true,"stack":["@{:kind :agent :label \"c\" …}"],"type":"result"}
{"id":7,"ok":true,"stack":["…","3"],"type":"result"}
```

- 裸文本一行 = `eval` 的简写；`{ 1 2 }` 这种以 `{` 开头的**字面量**仍当源码（判定见 D-39）。
- 流式：求值过程中就有 `{"type":"chunk","stream":"c","n":0,"text":"ab"}`，
  结束时 `{"type":"close","stream":"c","ok":true}`——**收 eval 与推流互不阻塞**（REQ-24）。
- 工作区（字典 + 栈）跨请求保留（REQ-42）；`{"type":"reset"}` 换一个干净的。
- stdout **只承载协议**：方言的 `print`/`show` 与所有诊断走 stderr（D-40 / REQ-43）。
- 前端订阅：`watch`（L9）给出 agent 会话的**只读视图流**——先回放历史，再随 `append` 吐新增条目，
  每次请求处理完后推送（每次至多 64 块）。视图流不进本轮列表，因此不会被收尾钩子并回会话（D-42）。

## 目录

```
vendor/janet/     janet 1.42.1 amalgam（VERSION 记录 sha256）
src/main.c        宿主入口：嵌入 bundle、启动 CLI、返回退出码
rb/               方言核心（随宿主静态嵌入；rb/MANIFEST 决定装载顺序）
cap/              能力层（可整目录剔除；核心不静态依赖，REQ-37）
tools/embed.janet 由 MANIFEST 生成 build/rb-bundle.janet 与 build/rb_bundle.c
tests/            unit / conformance / e2e（+ 附录 D 的 core-only 验收）
examples/         使用手册里的可跑例程（mock，hermetic；run-all.sh 一次跑完）
docs/             符合性矩阵、决策记录、协议草案、规格反馈
```

## 文档

| 文件 | 内容 |
|---|---|
| `docs/GUIDE.md` | **使用手册（例程版）**：从栈读法到 agent / 钩子 / 工具 / 协议 |
| `docs/CONFORMANCE.md` | REQ ↔ 测试矩阵（每条 REQ 的可执行验收） |
| `docs/DECISIONS.md` | 规格未冻结处的实现决策（D-xx） |
| `docs/PROTOCOL.md` | NDJSON over stdio 协议 v1（M5 冻结） |
| `docs/FRONTEND.md` | 前端契约：REQ-26/27/29 ↔ 协议动作表（M7，编辑器侧） |
| `docs/SPEC-FEEDBACK.md` | 规格缺陷与待裁决项（CHK-1…CHK-6） |
