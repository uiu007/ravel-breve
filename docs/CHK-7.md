# CHK-7 人工检查点：前端键位 + 待裁决项统一处置

依据规格：`ravel-breve-spec-v1.0k.md`（现行；v1.0b…v1.0j 保留为历史原文）。
本轮主题：**REPL 行编辑器（Emacs / Vim 双模式）**，以及此前遗留的规格留白 / 缺陷。

## 1. 交付

| 编号 | 内容 | 位置 |
|---|---|---|
| D-57 | REPL 行编辑器：Emacs 键位为缺省，`Esc` 进 Vim normal，再 `Esc` 回 Emacs | `rb/line.janet`、`rb/cli.janet`、`src/main.c` |
| SF-35 | 规格未规定 REPL 键位（属前端层留白）；建议只冻结「不进核心词表」「无终端仍一致」两条 | `docs/SPEC-FEEDBACK.md` |
| — | 手册新章：键位表 / 不做清单 / 扩展点 | `docs/GUIDE.md` §1.3 |
| — | 前端视角：REPL 键位与 Emacs 前端的边界、可复用形状 | `docs/FRONTEND.md` §5.1 |
| — | 单元测试 20 例（注入键源，无需终端） | `tests/unit/line.janet` |

## 2. 键位（冻结内容，改这里要同时改 GUIDE §1.3 与 `tests/unit/line.janet`）

| 动作 | Emacs | Vim normal | Vim insert |
|---|---|---|---|
| 行首 / 行尾 | `C-a` / `C-e`（`Home` `End`） | `0` / `$` | `C-a` / `C-e` |
| 左 / 右一字 | `C-b` / `C-f`（`←` `→`） | `h` / `l` | `←` `→` |
| 左 / 右一词 | `M-b` / `M-f`（`C-←` `C-→`） | `b` / `w` | `C-←` / `C-→` |
| 删前一字 / 删光标处 | `Backspace`、`C-h` / `C-d`、`Delete` | `x` | `Backspace` / `Delete` |

> **D-68 追记（v1.0j 之后）**：退格原来只删码位、不把光标左移，行长中间按退格
> 看上去像 Delete。修好后 pty 手测：
> `abcdef` + `←←←` + `BS×3` → `def`（光标跟着左移，逐字吃左边）；
> `abcd` + `←←` + `Delete` → `abd`（光标不动，删右边）。
| 删到行尾 / 行首 | `C-k` / `C-u` | `D` / — | `C-k` / — |
| 删一个词 | `C-w` | — | — |
| 整行清空 | `C-a C-k` | `dd` | `C-a C-k` |
| 撤销一步 | — | `u` | — |
| 进插入 | 直接打字 | `i` `a` `I` `A` | — |
| 回 normal | — | `Esc` | `Esc` |
| 回 Emacs | — | `Esc`（normal 下） | — |
| 历史 | `↑` `↓`（`C-p` `C-n`） | `↑` `↓` | `↑` `↓` |
| 提交 / 丢弃 / EOF | `Enter` / `C-c` / `C-d`（空行） | 同左 | 同左 |

**不做**（「如无必要勿增实体」）：kill ring、补全、多行编辑、数字前缀、寄存器、
可视模式、搜替换、`p`/`P`/`c`/`r`。

## 3. 验收

自动：

```
$ make test        → 326 单元/符合性 + 94 端到端 + 11 例程 + core-only 全绿
# v1.0f（REQ-52）后：346 单元/符合性 + 94 端到端 + 12 例程 + core-only 全绿
# v1.0g（REQ-53/54）后：365 单元/符合性 + 103 端到端 + 14 例程 + core-only 全绿
# v1.0i（REQ-58/59）后：378 单元/符合性 + 103 端到端 + 15 例程 + core-only 全绿
# v1.0j（REQ-60/61）后：391 单元/符合性 + 103 端到端 + 16 例程 + core-only 全绿
# v1.0k（REQ-62/63）后：402 单元/符合性 + 121 端到端 + 17 例程 + core-only 全绿
# v1.0l（预制的可发现性）后：412 单元/符合性 + 137 端到端 + 17 例程 + core-only 全绿

```
$ make test
测试：412  通过：412  失败：0
端到端：通过 137，失败 0
例程：失败 0 个
core-only: 通过（核心可独立装载并完成主脊）
```

## v1.0l / REQ-64 人工验收（只看输出，不需要终端）

| # | 命令 | 期望 |
|---|---|---|
| 1 | `./bin/ravel --presets` | 三份预设（mock / nvidia / opencode-go）+ **绝对目录** + 用户配置状态 + 用法；退出码 `0` |
| 2 | `./bin/ravel --presets` 里某份预设写坏 | 该行 `<读不出来：…>`，其余照列；退出码 `0` |
| 3 | `./bin/ravel --preset provier -e 1` | 退出码 `40`，报错带 `（可用：mock nvidia opencode-go…）` |
| 4 | `./bin/ravel --modes` | `default`（edit glob grep shell）与 `ptc`（eval）各带一句说明；退出码 `0` |
| 5 | 在没有 `presets/` 的目录里跑 `--presets` | 退出码 `0`；打印**实际找的绝对目录** + 「这个目录里没有 .json 预设」+ 一句「预设目录是相对当前目录的」以及改用用户配置文件的建议 |
| 5b | 在 `build/tmp`（有单测留下的坏夹具）里跑 `--presets` | 退出码 `0`；坏文件只显示 `<读不出来：原因>`，`one` / `user` 等好文件照常列出 |
| 6 | `--core-only` 构建跑 `--presets` | 退出码 `60`，stderr 说明缺能力层；`--modes` 照常 `0` |

# D-70（长行重绘 / 括号粘贴）后：408 单元/符合性 + 121 端到端 + 17 例程 + core-only 全绿
$ make test-agent  → 真 NVIDIA 14/0（不进 make test）
```

人工（pty，需要真终端；脚本见本轮临时件 `/tmp/pty*.py`，不进仓库）：

| # | 操作 | 期望 |
|---|---|---|
| 1 | `./bin/ravel`，输入 `+ 1 2` `Enter` | 打印 `3`，再出 `ravel> ` |
| 2 | `+ 1 23` 后 `←` `←` `0` `Enter` | 打印 `24`（插在中间） |
| 3 | `+ 100 200` 后 `C-←` `9` `Enter` | 打印 `9300`（按词跳） |
| 4 | `+ 1 2` 后 `C-a` `C-k` 重打 `+ 3 4` `Enter` | 打印 `7` |
| 5 | `+ 1 2` `Enter`，再 `↑` `Enter` | 再打印一次 `3`（历史） |
| 6 | 输入 `abc` `Esc` | 提示符变 `ravel> -- NORMAL -- ` |
| 7 | 接 6：`0` `x` `u` | 文本回到 `abc` |
| 8 | 接 6：`dd` `i` `+ 1 2` `Esc` `Enter` | 打印 `3` |
| 9 | 接 6：再 `Esc` | 提示符回 `ravel> `（Emacs） |
| 10 | 空行 `C-d` | REPL 退出，退出码 0 |
| 11 | `printf '+ 1 2\nquit\n' \| ./bin/ravel` | 与加键位前一致（`ravel> 3`） |
| 12 | `printf '1\n' \| ./bin/ravel --serve` | `result` 消息，协议未受影响 |
| 13 | 40 列终端里粘贴 `send say "` + 36 个中文（约 3 屏宽） | 屏上是**完整一行**（折成 3 行），提示符只出现一次，没有重复堆叠（D-70） |
| 14 | 接 13：`Backspace` 三次 | 末尾三个字消失、光标跟着左移落在新行尾 |
| 15 | 同上但**不带**括号粘贴标记地喂字节（模拟不支持的终端） | 屏上仍只有一行文本：每次重绘都先移回逻辑行首再擦到屏尾 |
| 16 | 接 13：`C-c` | 丢弃本行，回到干净提示符 |

D-70 的两条几何/粘贴行为已进单元测试（不需要终端）：
`tests/unit/line.janet` 里「重绘几何」「重绘：短行」「重绘：长行不叠印」
「重绘：行尾正好填满一行」「粘贴：整段插入」「粘贴：无宿主原语」共 6 条，
断言的是 `rb/line-render` 的**转义串本身**（文本只出现一次、开头必是回行首的上移）。

## 4. 待裁决项的统一处置（用户指示：一律用「推荐」）

| 条目 | 处置 |
|---|---|
| SF-32 | 附录 A 收 `llm` / `llm-get` / `llm-set`（L8 后的「provider 配置」一节），REQ-14 加一句「配置词只存不解析」 |
| SF-33 | REQ-30 增句：**一次求值 = 一个事务**，失败不改变栈（副作用不回滚） |
| SF-34 | 附录 F 增：真 provider 的协议/内容错误 → `code:60`，消息保留上游原文 |
| SF-35 | 本条：键位属前端，不进词表；只冻结两条不变量 |

其余 SF（14、15、16、17、18、19、20、21、22、23、24、25、26、27、28、29、30、31）
按各自条目的「建议」写进 v1.0e，实现侧差异逐条见 `docs/SPEC-FEEDBACK.md` 的
「实现现状」与 `docs/DECISIONS.md`。

---

## 5. v1.0m 追记：模式的复刻（D-72 / REQ-65 / REQ-66）

依据规格：`ravel-breve-spec-v1.0m.md`（现行；v1.0b…v1.0l 保留为历史原文）。

**做了什么。** 读 DeepSeek harness 的四个预置（`packages/bundle/web-app/presets/*.patch.yml`）
与 `plan-mode` 的说明，把「模式」这件事复刻了一遍；顺带修掉 v1.0f 的一处语义抄错
（`ptc` 把「只公示一个工具」实现成了「只注册一个工具」）。

| 编号 | 内容 | 位置 |
|---|---|---|
| D-72 | 注册 ≠ 公示（`:wire` 呈现层）+ 五预设 + 正交 plan + `read` / `write` | `rb/modes.janet`、`rb/tools.janet`、`rb/events.janet`、`cap/tools.janet` |
| REQ-65 | 模式可声明 `:wire`；四个 dsh 预置的复刻；提示模板 | `ravel-breve-spec-v1.0m.md` §4.13 |
| REQ-66 | `enter-plan` / `exit-plan` / `exit_plan_mode`：plan 正交于预置 | 同上 |
| SF-38 | 「照抄名字」与「照抄语义」的区别；不复制清单与理由 | `docs/SPEC-FEEDBACK.md` |

### 5.1 人工验收（复制粘贴即可）

```sh
make all

# ① 五个模式
./bin/ravel --modes                       # cordis / default / minimal / ptc / standard
./bin/ravel -e 'modes'                    # ("cordis" "default" "minimal" "ptc" "standard")

# ② 注册 ≠ 公示：ptc 的程序里能调全部工具，模型只看见 eval
./bin/ravel -e 'mode "ptc"
mode-of
mode-tools'                               # 七个（含 eval）
./bin/ravel -e 'mode "ptc"
invoke "eval" H{ "src" "invoke \"glob\" H{ \"pattern\" \"rb/MANIFEST\" }" }'
                                          # "rb/MANIFEST"（v1.0l 这里是「未注册的工具」）

# ③ plan 正交：不换模式，只加提示 + 一个工具
./bin/ravel -e 'enter-plan
flag "plan"'                              # true
./bin/ravel -e 'enter-plan
invoke "exit_plan_mode" H{ "plan" "# 计划" }
flag "plan"'                              # "计划已提交…" 然后 false

# ④ 两个新工具
./bin/ravel -e 'invoke "read" H{ "path" "README.md" "limit" 3 }'
./bin/ravel -e 'invoke "write" H{ "path" "build/tmp/x.txt" "content" "z" }'   # 1
```

| # | 手工动作 | 期望 |
|---|---|---|
| 1 | `./bin/ravel --modes` | 五个名字 + 每个的工具与一句说明；`ptc` 那行说「wire 上只有 eval」|
| 2 | `mode "minimal"` 后 `mode-of` / `mode-tools` | 工具只有 `("shell")`|
| 3 | 同上后 `invoke "write" H{…}` | `60`（它没装这个工具）|
| 4 | `mode "ptc"` 后 `invoke "eval" H{ "src" "invoke \"grep\" …" }` | 真结果，不是「未注册的工具」|
| 5 | `enter-plan` → `mode-of` | 模式名**没变**（还是 `ptc` / `default`），只有 `flags` 的 `plan` 变 `true`|
| 6 | 同上后 `flag-set false "plan"` | 等价于 `exit-plan`（手动出口）|
| 7 | `invoke "exit_plan_mode" H{ "plan" 1 }` | `31`（计划必须是字符串）|
| 8 | 不在 plan 时 `invoke "exit_plan_mode" H{ "plan" "# x" }` | `60`（编排级）|
| 9 | `mode "nope"` | `20`（未知模式）|
| 10 | `make test` / `make test-examples` / `make test-core-only` | 全绿（417 + 144 + 17 + core-only）|

### 5.2 边界（本轮**没有**做，需用户裁决）

- **`read_image`**（dsh 有）：本方言的消息内容是字符串，没有附件概念；要做得先给 `Utter` 加内容部件，
  那是类型系统的改动。
- **`fs-observation-policy`**（"先读后改"的强制）：本仓把它留在**提示**里（`standard` 人格会要求先读），
  不做硬约束——硬约束需要一个 per-agent 的"已读文件"集合，那是新状态。
- **多路径预设搜索**：D-71 明确不做，本版不变。

---

## 6. v1.0n 追记：模式的设定（D-73 / REQ-67）

用户报的现象（缺省模式里模型调 `shell`，整个回合以失败收场）：

```
ravel: @RoundDone 失败：流失败：工具失败：shell：shell 默认关闭：需要 RB_ALLOW_SHELL=1（它等价于绕过文件沙箱，D-61）
```

判词：「默认模式当然要有匹配它的初始设定，而不是要手动操作」。处置：**前置设定归模式声明**
（`:tools/gates` → `allow-shell`），设定不满足的工具**不上 wire**，关掉只需一行。
详见 D-73 / SF-39；规格 v1.0n §4.14 + 附录 T。

### 6.1 十步人工验收

```
# ① 开箱即用（不设任何环境变量）
./bin/ravel -e 'invoke "shell" H{ "cmd" "echo hi" }'          # "hi
"

# ② 设定是看得见的
./bin/ravel --modes                                            # 每个模式一行「设定：allow-shell=on」

# ③ 一行关掉
./bin/ravel -e 'flag-set false "allow-shell"
invoke "shell" H{ "cmd" "echo hi" }'                            # 60，错误里点名 allow-shell

# ④ 环境变量压过模式设定（两个方向）
RB_ALLOW_SHELL=0 ./bin/ravel -e 'invoke "shell" H{ "cmd" "echo hi" }'   # 60
RB_ALLOW_SHELL=1 ./bin/ravel -e 'flag-set false "allow-shell"
invoke "shell" H{ "cmd" "echo hi" }'                            # "hi
"

# ⑤ 最小模式也自洽
./bin/ravel -e 'mode "minimal"
invoke "shell" H{ "cmd" "echo ok" }'                            # "ok
"
```

| # | 手工动作 | 期望 |
|---|---|---|
| 1 | 不设 `RB_ALLOW_SHELL`，`invoke "shell"` | 能跑（缺省 `default` 配好了）|
| 2 | `--modes` | 五个模式各带 `设定：allow-shell=on` |
| 3 | `flag-set false "allow-shell"` 后 `invoke "shell"` | `60`，消息点名 `allow-shell` |
| 4 | 同上后看请求的工具表 | `shell` 不在其中（注册表里还在：`invoke` 仍是 60 而非 20）|
| 5 | `RB_ALLOW_SHELL=0` + 开关为 `true` | `60`（环境变量优先）|
| 6 | `RB_ALLOW_SHELL=1` + 开关为 `false` | 能跑（环境变量优先）|
| 7 | `mode "minimal"` 后 `invoke "shell"` | 能跑（`minimal` 也声明了设定）|
| 8 | 自造模式（`flag-set false "allow-shell"` 后 `mode-of` → `mode`） | stderr 一行告警，退出码不变 |
| 9 | `make test` | 419 单元/符合性 + 149 端到端 + 18 例程 + core-only 全绿 |
| 10 | `./bin/ravel -v` | `ravel breve 1.0n · janet 1.42.1` |

### 6.2 仍然留给用户裁决

- `read_image`（要先给 `Utter` 加内容部件）与 `fs-observation-policy`（"先读后改"的硬约束）——
  同 §5.2，本版未做。
- 多路径预设搜索（D-71 明确不做）。

---

## 7. v1.0o 追记：工具的参数（D-74 / REQ-68）

用户实测（OpenCode / DeepSeek）：模型把 `shell` 的参数写成 `{"command": …}`，
工具报「缺少参数 cmd」，**整轮以 60 收场**。根因三层：请求里 `parameters` 是空壳（模型只能猜）、
参数名只有短名（`cmd` / `path` / `old`）、失败不分账（模型手误与环境拒绝同码）。
处置见 D-74 / SF-40；规格 v1.0o §4.12 / §4.14 + 附录 U。

### 7.1 八步人工验收

```
# ① 别名：模型写 command 也照跑
RB_MOCK_TOOL='shell:{"command":"echo hi"}' RB_LLM=mock ./bin/ravel -e '…'   # 会话里有 "hi\n"

# ② 错到底：错误回给模型，本轮成功
RB_MOCK_TOOL='read:{"pth":"README.md"}' RB_LLM=mock ./bin/ravel -e '…'      # 退出码 0

# ③ 脚本路径仍是 60
./bin/ravel -e 'invoke "read" H{ "pth" "README.md" }'

# ④ 工具名写错同理（模型路径回话，脚本 60）
RB_MOCK_TOOL='shel:{"cmd":"echo hi"}' …
```

| # | 手工动作 | 期望 |
|---|---|---|
| 1 | 看请求里的 `parameters`（`rb/tool-defs`） | 有 `properties` 与 `required`，不再是空壳 |
| 2 | 工具描述里 | 每个参数都标「别名：…」|
| 3 | 模型发 `shell {"command": …}` | 成功，`shell` 真的跑了 |
| 4 | 模型发 `read {"pth": …}` | 本轮**成功**；会话里 `tool` 消息以「错误：」开头并列出「接受：…」|
| 5 | 模型发 `shel {"cmd": …}` | 同上（未知工具也是手误）|
| 6 | `invoke "read" H{ "pth" … }` | `60`，错误里有「接受：」|
| 7 | `invoke "read" H{ "path" "/etc/shadow" }` | `60`（环境侧失败不分账）|
| 8 | `./bin/ravel -v` / `make test` | `ravel breve 1.0o · janet 1.42.1`；427 + 156 + 18 + core-only 全绿 |

### 7.2 仍然留给用户裁决

- 更细的 schema（`enum` / `oneOf` / `pattern`）：当前不做（`properties` + `required` 已够，
  且危险命令的约束该在权限层，不该在 schema 里）。
- `deftool` 的用户工具是否也要参数模式：目前只有可选第四参给**能力层/模式**用；
  方言词 `deftool` 仍是三个参数（用户工具的体自己 `at`），要不要开放为第四个参数待定。

## 8. v1.0p 追记：越界与审批（D-75 / REQ-69）

一句话：**越界不再只剩退出码**。模型撞上沙箱 → 发 `@Approve` → 人（或钩子）点头 → 记一条**临时**授权
→ 重试一次 → 结果照常回给模型；不点头才 `60`。

### 8.1 八步人工验收

```sh
# 预备：一个沙箱根之外的文件
echo hi > /tmp/rb-chk8.txt

# ① 请求表长什么样（模型路径的失败带 :rb-denied 与 :rb-request）
./bin/ravel -e 'agent "c" { }
dup
send say "读 /tmp/rb-chk8.txt"
drain' | head -3            # 非交互 → 拒绝，消息点名 grant 与 RB_SANDBOX

# ② 预先授权：三个词
./bin/ravel -e 'grant "fs" "/tmp"
grants
read "/tmp/rb-chk8.txt"'

# ③ 撤销
./bin/ravel -e 'grant "fs" "/tmp"
ungrant
grants'

# ④ 自动点头（脚本 / CI 的写法）：换掉默认钩子
RB_MOCK_TOOL='read:{"path":"/tmp/rb-chk8.txt"}' ./bin/ravel -e '@off @Approve
@on @Approve [ accept-dir ]
agent "c" { }
dup
send say "读"
drain
pop
session'

# ⑤ 关掉审批（回到 v1.0o 的行为：直接 60）
RB_MOCK_TOOL='read:{"path":"/tmp/rb-chk8.txt"}' ./bin/ravel -e '@off @Approve
agent "c" { }
send say "读"
drain'

# ⑥ 脚本路径不走审批
./bin/ravel -e 'invoke "read" H{ "path" "/tmp/rb-chk8.txt" }'

# ⑦ 最直接的退路还在
RB_SANDBOX=./bin/ravel …
RB_SANDBOX=none ./bin/ravel -e 'read "/tmp/rb-chk8.txt"'

# ⑧ 例程与版本
./examples/run-all.sh
./bin/ravel -v
```

| # | 手工动作 | 期望 |
|---|---|---|
| 1 | 模型读根外文件（管道里跑） | `60`；消息里**既有** `grant` 又有 `RB_SANDBOX` |
| 2 | `grant "fs" "/tmp"` 后 `read` | 成功；`grants` 打出 `@{:key "/tmp" :kind "fs"}` |
| 3 | `ungrant` | 返回条数；`grants` 空 |
| 4 | `@off @Approve` + `[ accept-dir ]` | 本轮**成功**，会话里有 `role = "tool"` 的内容，且留下一条 `/tmp` 授权 |
| 5 | 只 `@off @Approve` | 回到旧行为：`60`，消息是原样的「沙箱拒绝」 |
| 6 | `invoke "read"` 根外 | `60`，**不产生**授权（没人替程序员点头）|
| 7 | `RB_SANDBOX=none` | 成功（D-60 的旧退路没被动过）|
| 8 | `make test` / `-v` | `437 + 162 + 19 + core-only` 全绿；`ravel breve 1.0p · janet 1.42.1` |

### 8.2 仍然留给用户裁决

- **授权要不要入档（写进工作区快照）**：本版不入档——"临时的"要有明确边界；
  跨会话的信任请用 `RB_SANDBOX` 或启动脚本里的 `grant`。
- **别的 `kind`**：网络（`:net`）、`shell` 命令白名单都可以套同一套请求表；
  当前能力层只有 `:fs` 会产出策略拒绝，所以只做了 `:fs`。
- **审批要不要进前端事件流**：现在是 stderr 的交互提示，没有 `@Approve` 的订阅接口
  （前端若要弹出对话框，需要协议里加一条）。
- **`y` / `d` 之外是否要 `a`（always，一次会话内全部目录）**：默认拒绝更安全，先不加。
