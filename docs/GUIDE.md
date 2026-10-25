# ravel breve 使用手册（例程版）

面向「想马上写起来」的读者。每条结论后面都跟着**跑得通**的例程与真实输出；
例程源码在 `examples/`，一次跑完全部例程：

```
$ ./examples/run-all.sh
  ✓ examples/01-stack.breve
  ✓ examples/02-words.breve
  ✓ examples/03-seq-text.breve
  ✓ examples/04-control.breve
  ✓ examples/05-json.breve
  ✓ examples/06-files.breve
  ✓ examples/07-agent.breve
  ✓ examples/08-tools.breve
  ✓ examples/09-hooks.breve
  ✓ examples/10-serve.sh
  ✓ examples/11-llm-config.breve
例程：失败 0 个
```

> 全部例程都是 **hermetic** 的：`RB_LLM=mock`，不联网、不花钱、结果确定
> （`examples/10-serve.sh` 也一样，它跑的是前端协议）。

---

> **只是想先跑起来？** 看 `QUICKSTART.md`（10 分钟，不含钩子/工具/协议细节）。
> 本手册是参考书，按主题查即可（目录在第五节之后每节独立）。

## 0. 30 秒上手

```
$ make all                                  # 编出 bin/ravel（嵌了 Janet 1.42）
$ RB_LLM=mock ./bin/ravel -e '+ 1 2'
3
```

`ravel breve` 只有两条规矩，记住这两条就能写：

1. **书写是波兰式（前缀）**：`take 2 "abcde"`、`+ 1 2`、`map [ * 2 ] { 1 2 3 }`。
2. **执行是类 Forth 栈机**：一行 = 一个语句，语句里的 token **反转后**执行。

于是读法是：**最左的实参 = 第一个操作数 = 最后入栈 = 栈顶 = 最先被消费**。
所有例程都遵守这条，不会出现中缀。

---

## 1. 安装与四种运行方式

```
$ make all          # 生成 bin/ravel（依赖 vendor/janet）
$ make test         # 单元 + 符合性 + 端到端（mock，全离线）
```

`bin/ravel` 有四种用法：

| 用法 | 命令 | 用途 |
|---|---|---|
| REPL | `./bin/ravel` | 交互试验，提示符 `ravel> ` |
| 一行 | `./bin/ravel -e '<源>'` | 脚本外的临时求值；打印剩余栈 |
| 脚本 | `./bin/ravel 文件.breve` | 文件里一行一个语句 |
| 服务 | `./bin/ravel --serve` | NDJSON over stdio，给前端（Emacs）用 |

辅助开关：

```
$ ./bin/ravel -v
ravel breve 1.0o · janet 1.42.1

$ ./bin/ravel -h
用法：
  ravel                     REPL（提示符 ravel> ）
  ravel -e "<一行>"           求值一行，打印剩余栈
  ravel script.breve        执行脚本
  ravel --serve             NDJSON over stdio（REQ-24）
  ravel --dump ...          打印转译产物（REQ-31）
  ravel --json ...          按协议消息形状输出（REQ-22）
  ravel --preset <名字>     启动即导入 provider 配置预设（REQ-62，可重复）
  ravel --no-config         不装载 ~/.config/ravel/config.json（REQ-63）
  ravel -v | -h
```

配置的两个开关（细节见 §14.11）：`--preset opencode-go` 一键装预设，
`--no-config` 不读用户配置文件（等价 `RB_CONFIG=-`）。

REPL 一次吃一行，栈跨行保留：

```
$ printf '2 3\n+\ndepth\nquit\n' | ./bin/ravel
ravel> 3
2
ravel> 5
ravel> 5
1
ravel> 
```

（`2 3` 一行 = 一个语句，镜像后先压 3 再压 2；`-e`/REPL 打印的顺序是**栈底 → 栈顶**，
所以看到 `3`、`2`，然后 `+` 得到 `5`，`depth` 说栈上只有 1 个东西。）

### 1.1 例程：第一个脚本

`examples/01-stack.breve`：

```
# 01 栈与镜像读法：一行一个语句，字面量填最左操作数
+ 1 2
show
- 10 4
show
take 2 "abcde"
show
{ 1 2 3 }
len
show
H{ "name" "ravel" "kind" "dialect" }
at "name"
show
```

```
$ RB_LLM=mock ./bin/ravel examples/01-stack.breve
3
6
"ab"
3
"ravel"
```

### 1.2 provider：谁来回答（环境变量 + 语言内配置）

**「provider」= 谁来回话**：真模型（`nvidia`）、还是离线假模型（`mock`）。

#### 1.2.1 `RB_LLM=mock` 是什么意思

`mock` 是**离线假 provider**：不联网、不花钱、回复是确定的。

- 缺省回复：`"回声：<最后一条消息内容>"`；用 `RB_MOCK_REPLY` 换成固定串；
  用 `RB_MOCK_TOOL` 让它装模作样发起一次工具调用（测工具循环用）。
- 流式仍然是流式：长回复按 UTF-8 边界切成几块（`@Chunk` 钩子照常触发），
  所以「钩子 / 合并 / 压缩 / 重试」全都能在 mock 上测。
- **为什么例程都用它**：文档和测试要**可照抄的输出**。真模型每次措辞都不同，
  写进手册就是假输出。所以 `examples/*` 与 `make test` 一律 `RB_LLM=mock`，
  真 provider 的测试另有入口（`make test-agent`，不进 `make test`）。

```
$ RB_MOCK_REPLY='固定回复' RB_LLM=mock ./bin/ravel -e 'agent "c" { }
dup
send say "hi"
drain'
"固定回复"
```

#### 1.2.2 换成真 provider（NVIDIA）

密钥**只**从这两处来，不进工作区、不进快照、不入库：
`NVIDIA_API_KEY` 环境变量，或 `secrets/nvidia.key`（`chmod 600`，已在 `.gitignore`）。

```
$ RB_LLM=nvidia ./bin/ravel -e 'agent "c" { }
send say "只说两个字：好的"
drain
show'
"好的"
```

#### 1.2.2b 换成真 provider（OpenCode Zen / Go，D-64）

第二个真 provider，同样是 OpenAI 兼容的 `/chat/completions`，SSE 解析与 NVIDIA
**共用一份**（`cap/oai.janet`）。密钥：`OPENCODE_API_KEY` 或 `secrets/opencode.key`。

```
$ RB_LLM=opencode ./bin/ravel -e 'llm-get "provider"
show
llm-get "model"
show
agent "c" { }
send say "只回答两个字：收到"
drain
show
usage
show'
"opencode"
"deepseek-v4.1-flash"
"收到"
@{"calls" 1 "completion-tokens" 3 "prompt-tokens" 310 "total-tokens" 313}
```

三点与 NVIDIA 不同，都已内置、无需你操心：

| 差别 | 做法 |
|---|---|
| 端点 | `https://opencode.ai/zen/go/v1/chat/completions`；`RB_OC_BASE` 可换基址（给到 `/chat/completions` 也行）|
| 必须自称客户端 | `User-Agent: ravel-breve/1.0o`（**不许**用通用 SDK 名）|
| 必须带会话头 | `x-opencode-session`，一次会话一个稳定值（取自 agent 标签，可用 `RB_OC_SESSION` 覆盖）；缺了会被 `MissingSessionID` 拒掉 |

另外：它的增量里带 `reasoning_content`（思考过程），**只取 `content`**——思考不进正文、
不进会话、不计入 `usage` 之外的任何地方；用量帧带 `opencode.allowance`（这次请求记了多少账），
`usage` 词只汇总 token 那几个数。

真 provider 的验收入口（无密钥自动跳过，不进 `make test`）：

```
$ make test-oc        # OpenCode
$ make test-agent     # NVIDIA
```

#### 1.2.3 运行中换配置：`llm` / `llm-get` / `llm-set`

环境变量只能在**启动前**定死。要在一局里换 provider、换模型、改上限，
把配置写进**工作区**（D-54）：

| 配置项 | 环境变量（次优先） | 内置缺省 | 说明 |
|---|---|---|---|
| `provider` | `RB_LLM` | `auto` | `nvidia` / `opencode` / `mock` / `auto`（`auto` = 有谁家的密钥就用谁，都没有则 `mock`） |
| `model` | `RB_MODEL` | 按 provider：NVIDIA `meta/llama-3.2-11b-vision-instruct`，OpenCode `deepseek-v4.1-flash` | 真 provider 的模型名 |
| `endpoint` | `RB_ENDPOINT` | 按 provider 的官方端点 | 兼容 OpenAI 形状的服务也能接；OpenCode 另可用 `RB_OC_BASE` 换基址 |
| `max-tokens` | `RB_MAX_TOKENS` | `512` | 本轮回复上限 |
| `temperature` | `RB_TEMPERATURE` | `0.2` | 采样温度 |
| `headers` | `RB_HEADERS` | `@{}` | 自定义请求头（`Table` 或 `K:v,…` / JSON；**覆盖同名内置头**，见 §14.9）|

**优先级：工作区配置 > 环境变量 > 内置缺省**（`llm-get` 显示的就是生效值）。

三个词（书写序照旧：最左 = 第一个操作数 = 栈顶）：

| 词 | 栈效应 | 作用 |
|---|---|---|
| `llm` | `-- Table` | 整张配置表（**活表**：`at` 读，`llm-set` 写） |
| `llm-get` | `Key -- Value` | 取**生效值**（含环境变量与缺省） |
| `llm-set` | `Value Key --` | 写一项；`Value` 为 `nil` = 删除（回落到环境变量/缺省） |

```
$ RB_LLM=mock ./bin/ravel -e 'llm-get "provider"
show
llm-get "model"
show
llm-set "nvidia" "provider"       # 从这一句之后的 send 就走真 provider
llm-set "demo-model" "model"
llm
show'
"mock"
"meta/llama-3.2-11b-vision-instruct"
@{"model" "demo-model" "provider" "nvidia"}
```

一局里换 provider，**不必重启**（下面这次是真调用，最后一轮走 NVIDIA）：

```breve
llm-set "mock" "provider"          # 先离线跑一轮
agent "c" { }
send say "只回答两个字：好的"
drain
show                                # → "回声：只回答两个字：好的"

llm-set "nvidia" "provider"         # 换真 provider
llm-set "meta/llama-3.2-11b-vision-instruct" "model"
llm-set 128 "max-tokens"
llm-get "provider"
show                                # → "nvidia"

agent "c" { }
send say "只回答两个字：收到"
drain
show                                # → "好的"（真模型说的）
```

- 白名单：写错配置项名 → 31（`未知的 LLM 配置项：provier`），不静默无效。
- `key` **不是**配置项：`llm-set "sk-..." "key"` → 60，提示改用环境变量/密钥文件。
- 保存工作区（`save`）会把配置一起写进快照；`load` 之后仍然生效——
  于是同一份 `.rbx` 在别的机器上也是「同一个 provider 配置」。

---

### 1.3 REPL 的键位：Emacs 与 Vim 双模式（D-57）

REPL 的行编辑器只在**真终端**里启用；管道 / 重定向自动退回普通行模式
（`printf ... | ravel` 的行为一点没变，脚本与测试不受影响）。

缺省是 **Emacs 模式**。按 `Esc` 进 **Vim normal 模式**，再按 `Esc` 回 Emacs——
「用 Vim 的模式切换思想」只管一件事：切换输入模式。模式在提示符上看得见：

| 模式 | 提示符 | 进入方式 |
|---|---|---|
| Emacs | `ravel> ` | 缺省；Vim normal 下再按 `Esc` |
| Vim normal | `ravel> -- NORMAL -- ` | Emacs 下按 `Esc`；插入模式按 `Esc` |
| Vim insert | `ravel> -- INSERT -- ` | normal 下 `i` / `a` / `I` / `A` |

**只收最常用的动作**（「如无必要勿增实体」）：

| 动作 | Emacs | Vim |
|---|---|---|
| 行首 / 行尾 | `C-a` / `C-e`（`Home` `End`） | `0` / `$` |
| 左 / 右一字 | `C-b` / `C-f`（`←` `→`） | `h` / `l`（`←` `→`） |
| 左 / 右一词 | `M-b` / `M-f`（`C-←` `C-→`） | `b` / `w` |
| 删前一字（光标左） | `Backspace`（0x7f 或 0x08）/ `C-h` | 插入模式下 `Backspace` |
| 删光标处（光标右） | `Delete`（`CSI 3~`）/ `C-d` | `x`（normal）/ 插入模式下 `Delete` |
| 删到行尾 | `C-k` | `D` |
| 删到行首 | `C-u` | —（用 `0 D`） |
| 删一个词 | `C-w` | —（用 `b D`） |
| 整行清空 | `C-a C-k` | `dd` |
| 撤销一步 | — | `u` |
| 进插入 | 直接打字 | `i` / `a`（后一字符）/ `I`（行首）/ `A`（行尾） |
| 历史 | `↑` `↓`（`C-p` `C-n`） | `↑` `↓` |
| 提交本行 | `Enter` | `Enter`（两种模式都行） |
| 丢弃本行 | `C-c` | `C-c` |
| EOF | `C-d`（空行） | `C-d`（空行） |

**不含**：kill ring、补全、多行编辑、Vim 的数字前缀 / 寄存器 / 可视模式 /
`hjkl` 以外的动作。一行通常就两三个词，够用即可；要更多，走下面的扩展点。

```
$ ./bin/ravel
ravel> + 1 2^A^K        # ^A = C-a：清掉重打
ravel> + 3 4
7
ravel> 随便打点什么      # 按 Esc 进 Vim normal，提示符变成 `ravel> -- NORMAL -- `
                        # 0 dd 清空，i 回到插入，Enter 提交
```

- **退格删左边、Delete 删右边**，两者是分开的：删完退格光标跟着左移，
  不会「停在原地、让文字从底下缩过去」（D-68）。基线 0x7f、0x08 都当退格，
  `CSI 3~` 当 Delete；`C-d` 在非空行 = 删光标处，在空行 = EOF。
- 历史只记**提交过的非空行**；翻到中间时打了一半的内容，翻回底部还在。
- 只在读这一行时把终端切到原始模式；**求值期间回到熟模式**，所以
  求值时按 `C-c` 是「中断程序」而不是「丢弃本行」。
- 出错处理简单但不会锁死：行编辑器抛异常 → stderr 一行提示，立刻退回行模式；
  终端状态在退出（含 `C-c`、异常）时恢复。

扩展点（前端、测试、以后加补全都从这里进）：

| 名字 | 作用 |
|---|---|
| `rb/line-reader` | 读一行的唯一入口，`(fn [prompt hist] -> String 或 nil)`；换编辑器/补全器只改这里 |
| `rb/line-emacs-keys` / `rb/line-vim-normal-keys` / `rb/line-vim-insert-keys` | 键位表（数据）：`(put rb/line-emacs-keys :ctrl-l (fn [st] ...))` 即可加键 |
| `rb/line-apply-key!` | 把一个键码应用到一个状态表（`rb/line-state`），返回动作 `nil`/`:submit`/`:eof`/`:abort` |
| `rb/line-edit` 的第三个参数 | 注入键源，单元测试用（不需要终端） |
| `rb/line-on-error` | 编辑器出错时的提示方式 |
| `rb/line-tty?` | 当前是否有终端原语（没有就自动走行模式） |

- **长行与粘贴**（D-70）：一行比终端宽时，重绘会先把自己从**上一屏的行尾**
  移回这一行的开头再擦到屏尾，所以折行的长行不会一层层叠着印；终端支持
  **括号粘贴**（bracketed paste）时整段一次插入、只重绘一次，几十个字的中文
  提示词粘进来是「一行文字」，不是「一堆重复的提示符」。单行编辑器里换行
  折成一个空格、制表折成两个空格，其余控制字符丢掉（粘贴里的 ESC
  不能把屏幕搅乱）。
- 屏幕几何（`:rows` / `:rpos` / `:col`）由 `rb/line-geom` 纯函数算出，
  `rb/line-render` 只负责把它变成转义序列——两者都能在**没有终端**的
  单元测试里断言（见 `tests/unit/line.janet` 的「重绘」几条）。

宿主侧原语表是 `(dyn :rb-term)`（`src/main.c` 提供 `tty` / `raw-on` / `raw-off` /
`read-key` / `size` / `paste-text`）：方言层取不到它就退回行模式，所以裸 `janet`
跑单元测试也能装载内核。`size` 返回 `[行 列]`（`TIOCGWINSZ`，取不到退环境变量
`COLUMNS`/`LINES`，再取不到 `24x80`）；括号粘贴读到 `ESC[201~` 为止，
正文用 `paste-text` 取，键码是 `-200`。

---

## 2. 唯一的读法：镜像

一条语句里的 token 会**反转**后执行。`--dump` 把转译产物直接打出来：

```
$ ./bin/ravel --dump -e 'take 2 "abcde"'
(do (rb/push "abcde") (rb/push 2) (rb/take))
"ab"
```

读法：写 `take 2 "abcde"`，实际执行顺序是 `"abcde"` → `2` → `take`，
所以 `take` 从栈顶先拿到 `2`（个数）、再拿到 `"abcde"`（序列）。
**最左 = 第一个操作数 = 栈顶 = 先被消费**。

定义行也能看：

```
$ ./bin/ravel --dump -e 'double : [ * 2 ]'
(do (rb/define-word "double" (fn [] (do (rb/push 2) (rb/mul))) nil "* 2" "(fn [] (do (rb/push 2) (rb/mul)))"))
```

### 2.1 一行 = 一个语句

块里、文件里都是「换行 = 语句分隔」。这是最容易踩的坑：

```
1
2
+
```

```
$ ./bin/ravel -e '1
2
+'
3
```

写成一行 `1 2 +` 就变成一个语句了：镜像后执行 `+`、`2`、`1` → 先 `+` 就栈下溢（30）。

**同一个道理**：`[ pop 1 ]` 是一个语句，镜像成「压 1 → `pop`」，即把刚压的 1 弹掉。
要「先弹掉原来的、再压 1」得写两行：

```
[ pop
  1 ]
```

### 2.2 只写一个操作数时，字面量填**最左**位置

这是镜像规则的另一半后果，务必记牢：

| 写法 | 读作 | 例（栈顶是 `n`） |
|---|---|---|
| `- 1` | `1 - n` | `5` → `-4` |
| `< 2` | `2 < n` | `5` → `true` |
| `> 2` | `2 > n`（= `n < 2`） | `5` → `false` |
| `- 5 3` | `5 - 3` | `2` |

```
$ RB_LLM=mock ./bin/ravel -e '5
- 1'
-4

$ RB_LLM=mock ./bin/ravel -e '5
< 2'
true

$ RB_LLM=mock ./bin/ravel -e '5
+ -1'
4
```

> 想算 `n - 1`？最省事的写法是 `+ -1`（加法可换）。
> 或者把 `1` 与 `swap` 分成两条语句：`1` 然后 `swap` 然后 `-`。

---

## 3. 值与字面量

| 写法 | 值 | 说明 |
|---|---|---|
| `42` `3.14` `-7` | number | |
| `"文本"` | string | 支持 `\n` `\t` `\"` `\\` |
| `true` `false` `nil` | bool / nil | |
| `{ 1 2 3 }` | tuple | 序列字面量 |
| `H{ "a" 1 "b" 2 }` | table | 映射字面量 |
| `[ ... ]` | 函数 | **引号 = 未写满的波兰式**，压栈不执行 |
| `@Start` `@Chunk` … | string | 事件名是字面记号，压栈即值 |

```
$ ./bin/ravel -e '{ 1 2 3 }
H{ "a" 1 "b" 2 }'
(1 2 3)
@{"a" 1 "b" 2}
```

引号是数据：

```
$ ./bin/ravel -e '[ * 2 ]'
#<function>
```

`#` 到行尾是注释；行尾 `\` 表示续行（语句不结束）。

---

## 4. 栈动词

| 词 | 作用 |
|---|---|
| `dup` | 复制栈顶 |
| `pop` | 弹掉栈顶 |
| `swap` | 交换栈顶两个 |
| `rot` | 栈底那个搬到栈顶（三个元素轮换） |
| `-rot` | 栈顶那个搬到栈底 |
| `keep` | `[ q ] x -- x q(x)`：留住 x，用副本跑引号 |
| `dip` | `[ q ] ... x -- ... q(...) x`：把栈顶藏起来跑引号，再放回 |
| `apply` / `call` | 跑栈顶的引号 |
| `depth` | 当前栈深度 |

实测（`-e` 的输出顺序 = 栈底 → 栈顶）：

```
$ ./bin/ravel -e '1
2
3'
1
2
3

$ ./bin/ravel -e '1
2
3
rot'
2
3
1

$ ./bin/ravel -e '1
2
3
-rot'
3
1
2

$ ./bin/ravel -e '1
2
3
swap'
1
3
2

$ ./bin/ravel -e 'keep [ * 2 ] 5'
5
10

$ ./bin/ravel -e 'dip [ * 2 ] 3 5'
10
3

$ ./bin/ravel -e '4
apply [ * 3 ]'
12
```

栈下溢一律 **30**：

```
$ ./bin/ravel -e 'pop'
ravel: 栈下溢
$ echo $?
30
```

---

## 5. 定义自己的词

语法：`名字 : [ 体 ]`，可选文档串：`名字 : "说明" [ 体 ]`。
定义行是**元层**：不参与镜像，也**没有栈效果**；装载期就注册进字典。

```
$ RB_LLM=mock ./bin/ravel -e 'double : "翻倍" [ * 2 ]
double 21'
42
```

查字典：

```
$ RB_LLM=mock ./bin/ravel -e 'double : "翻倍" [ * 2 ]
doc "double"
see "double"'
double —— 翻倍
double : [ * 2 ]
```

常量就是零元词：

```
pi : [ 3.14159 ]
* pi 2
```

```
$ RB_LLM=mock ./bin/ravel -e 'pi : [ 3.14159 ]
* pi 2'
6.28318
```

### 5.1 递归

体内可以**自引用**（转译期先占位再转译体，D-51）：

```
fact : "阶乘（递归）" [ dup
  > 2
  if [ pop
  1 ] [ dup
  -1
  +
  fact
  * ] ]
fact 5
fact 10
```

```
$ RB_LLM=mock ./bin/ravel -e '（同上）'
120
3628800
```

读法拆开看：

- `dup` → 留一份给后面的乘法；
- `> 2` → `2 > n`，即「n 小于 2」；
- `if [ pop / 1 ] [ … ]` → **条件已在栈上**的形式（§8.1）；
- 否则 `dup` → `-1` → `+`（= n-1）→ `fact` → `*`（= n × (n-1)!）。

### 5.2 完整例程

`examples/02-words.breve`：

```
$ RB_LLM=mock ./bin/ravel examples/02-words.breve
42
6.28318
double —— 翻倍
double : [ * 2 ]
120
3628800
```

---

## 6. 序列与文本

序列词是**多态**的：string、tuple、array 都能吃。

```
$ ./bin/ravel -e 'len "abcde"
first "abcde"
last "abcde"
take -2 "abcde"
drop 2 "abcde"
at 1 { 10 20 30 }
reverse "abc"
sort { 3 1 2 }
sum { 1 2 3 }'
5
"a"
"e"
"de"
"cde"
20
"cba"
(1 2 3)
6
```

组合子：`map` / `filter` / `fold`，引号在左、序列在右：

```
$ ./bin/ravel -e 'map [ * 2 ] { 1 2 3 }
filter [ > 2 ] { 1 2 3 }
fold [ + ] 0 { 1 2 3 }'
(2 4 6)
(1)
6
```

> `filter [ > 2 ]` 的读法：`2 > x`，所以只留下 `1`。想要「大于 2 的」写 `[ < 2 ]`。

连接与拆分：

```
$ ./bin/ravel -e ', "abc" "de"
,, { 1 } { 2 } { 3 }
split "," "a,b,c"
words "  a b   c "
lines "a\nb"'
"abcde"
(1 2 3)
@["a" "b" "c"]
@["a" "b" "c"]
@["a" "b"]
```

字符串工具与转换：

```
$ ./bin/ravel -e 'trim "  hi  "
replace "a" "o" "banana"
contains "nan" "banana"
starts-with "ba" "banana"
to-string 42
to-int "42"'
"hi"
"bonono"
true
true
"42"
42
```

`zip` 拉链：

```
$ ./bin/ravel -e 'zip { 1 2 } { "a" "b" }'
@[(1 "a") (2 "b")]
```

### 6.1 完整例程

`examples/03-seq-text.breve`（输出见 `./examples/run-all.sh`）：

```
# 03 序列与文本
map [ * 2 ] { 1 2 3 }
show
filter [ > 2 ] { 1 2 3 }
show
fold [ + ] 0 { 1 2 3 }
show
reverse "abc"
show
sort { 3 1 2 }
show
split "," "a,b,c"
show
lines "第一行\n第二行"
show
words "  a b   c "
show
trim "  hi  "
show
replace "a" "o" "banana"
show
,, { 1 } { 2 } { 3 }
show
zip { 1 2 } { "a" "b" }
show
```

---

## 7. 算术、比较与布尔

| 词 | 例 | 结果 |
|---|---|---|
| `+` `-` `*` `/` `mod` | `/ 7 2` | `3.5` |
| `abs` `min` `max` `sum` | `max 5 3` | `5` |
| `=` `!=` `<` `>` `<=` `>=` | `< 5 3` | `false` |
| `not` `and` `or` | `and true true` | `true` |

```
$ ./bin/ravel -e '= 1 1
!= 1 1
not false
and true true
or false true
<= 1 2
>= 1 2'
true
false
true
true
true
true
false
```

比较的左右由镜像决定：`< 5 3` 的第一个操作数是 5、第二个是 3 → `false`。

---

## 8. 控制流

`if` / `when` / `unless` / `loop` / `while` / `try` / `recover` / `retry`。

### 8.1 `if` 的两种写法

**① 条件内联**（条件由语句自己的 token 供操作数）：

```
if < 3 5 [ "yes" ] [ "no" ]
```

```
$ ./bin/ravel -e 'if < 3 5 [ "yes" ] [ "no" ]'
"yes"
```

**② 条件已在栈上**（语句里只有 `if` + 两个引号）：

```
42
< 60
if [ "及格" ] [ "不及格" ]
```

```
$ ./bin/ravel -e '42
< 60
if [ "及格" ] [ "不及格" ]'
"不及格"
```

判据在**转译期**：语句恰好是「`if` + 两个引号」就走第二种，否则走第一种。
`when` / `unless` / `loop` 同理（词 + 一个引号 = 条件/次数在栈上）。

```
$ ./bin/ravel -e 'true
when [ log "w" ]
when [ log "不会执行" ]'
w
ravel: 栈下溢                  # 第二句的 true 已经被第一句消费掉了
```

### 8.2 循环

```
$ ./bin/ravel -e 'loop 3 [ log "跑一次" ]'
跑一次
跑一次
跑一次

$ ./bin/ravel -e '3
loop [ log "跑一次" ]'         # 次数在栈上
跑一次
跑一次
跑一次
```

`while` 的条件引号自己就是完整波兰式，留一个真值在栈上：

```
$ ./bin/ravel -e '1 2 3
while [ < 1 depth ] [ + ]'
6
```

读法：栈上不止 1 个元素（`1 < depth`）就 `+` 把顶上两个合并，直到只剩 1 个。

### 8.3 错误处理

```
$ ./bin/ravel -e 'try [ fail "boom" ] [ to-string ]'
"boom"

$ ./bin/ravel -e 'retry [ 42 ] 3'
42

$ ./bin/ravel -e 'retry [ fail "boom" ] 2'
ravel: boom            # 每次都失败，重试 2 次后仍失败 → 33
```

- `try [ 体 ] [ 处理 ]`：体抛错就把错误交给处理引号（栈效果保留）。
- `recover [ 体 ] [ 处理 ]`：先记下体入口处的栈深度，出错时把栈**截回**该深度，
  再把错误交给处理引号。**只截不补**——体已经弹掉的值回不来。
- `retry [ 体 ] n`：体失败就重试，至多 n 次。
- **失败的一轮没有栈效果**（D-55）：一次求值里任何一步出错，栈回到求值前的样子。
  所以 `+ 1` 在空栈上只报 30，不会留下半截操作数；REPL 与 `--serve` 报错后
  可以从干净状态继续，不必重启。

### 8.4 完整例程

`examples/04-control.breve`：

```
$ RB_LLM=mock ./bin/ravel examples/04-control.breve
"跑一次"


"跑一次"


"跑一次"


"断言通过"


"yes"
"不及格"
6
"boom"
42
```

---

## 9. 断言、调试与诊断

| 词 | 作用 | 输出到 |
|---|---|---|
| `show` | 渲染并打印（序列逐元素） | stderr |
| `print` | 同 `show`（渲染后打印，字符串带引号） | stderr |
| `log` | 打印一行 | stderr |
| `dump` | 打印「栈深度 N」+ 整个栈（栈不变） | stderr |
| `depth` | 栈深度入栈 | — |
| `assert` | 失败 → 33 | stderr |
| `fail` | 立刻以 33 结束 | stderr |
| `now` | 当前 Unix 时间（整数秒） | — |
| `env` | 读环境变量（没有则 nil） | — |

```
$ ./bin/ravel -e 'assert < 3 5 "3 必须小于 5"
log "断言通过"'
断言通过

$ ./bin/ravel -e 'assert < 5 3 "阈值"'
ravel: 断言失败：阈值          # 33
```

**`stdout` 只承载协议**（REQ-43）：`show`/`print`/`log`/`dump` 全走 stderr，
所以 `ravel --serve` 的 stdout 永远是干净的 NDJSON。

---

## 10. JSON

```
$ ./bin/ravel -e 'to-json H{ "a" 1 "b" { 2 3 } }
from-json "{\"a\":[1,2,3]}"
at "a" from-json "{\"a\":[1,2,3]}"
len at "a" from-json "{\"a\":[1,2,3]}"'
"{\"a\":1,\"b\":[2,3]}"
@{"a" @[1 2 3]}
@[1 2 3]
3
```

JSON 能力属于能力层（`cap/json`）：核心不含 JSON 解析器，`--core-only` 构建里这些词报 **60**。

---

## 11. 文件与工作区快照

| 词 | 栈效应 | 说明 |
|---|---|---|
| `read` | `Path -- String` | 读不到 → 40 |
| `write` | `String Path --` | **覆盖**写（失败 41） |
| `current` | `-- Workspace` | 当前工作区 |
| `save` | `Workspace Path --` | 写快照 + 截断日志，并绑定该路径 |
| `load` | `Path -- Workspace` | 载入快照 + 重放日志 |
| `compact` | `Workspace --` | 写新快照、清空日志 |

**文件沙箱**（D-60）：所有文件读写都先过一道规范化检查，根 = 进程当前目录
（或用 `RB_SANDBOX=<路径>` 指定，`RB_SANDBOX=none` 关闭）。所以下面的例程写 `build/tmp/`：
越界**写** → `41`，越界**读** → `40`（读的契约本来就是「失败 = nil」，不给两条失败路径）。

```
$ ./bin/ravel -e 'write "第一行\n第二行\n" "build/tmp/ravel-demo.txt"
lines read "build/tmp/ravel-demo.txt"'
@["第一行" "第二行" ""]

$ ./bin/ravel -e 'read "build/tmp/ravel-demo.txt"
len'
20

$ ./bin/ravel -e 'read "/etc/hostname"'
ravel: 文件不存在或无权限：/etc/hostname     # 40（沙箱根外，读不到）
$ ./bin/ravel -e 'write "x" "/tmp/ravel-demo.txt"'
ravel: 写入失败：/tmp/ravel-demo.txt（沙箱拒绝（根 = …）：/tmp/ravel-demo.txt；…）   # 41
```

### 11.1 快照：注意参数序

`save` 弹的是「先工作区、后路径」，所以**路径要先入栈、工作区在栈顶**：

```
"build/tmp/ravel-demo.rbx"
save current
```

`examples/06-files.breve` 就是这两行 + 一个 `log`。

**载入的词下一轮才可见**：`load` 是运行期动作，而转译在它之前。所以同一个 `-e` 里
`load` 完立刻用那个词会报 20；分成两次求值（REPL / `--serve` / 两次 `-e`）就正常。
`examples/10-serve.sh` 里有用协议读快照的对照。

---

## 12. agent 与会话

| 词 | 栈效应 | 说明 |
|---|---|---|
| `agent` | `Label Session [ quot ] -- Agent` | 新开 agent（引号可选 = 起始行为） |
| `say` | `String -- Utter` | `role = "user"` |
| `saysys` | `String -- Utter` | `role = "system"` |
| `append` | `Utter Agent -- Agent` | 只追加（不发请求） |
| `session` | `Agent -- Session` | 取会话副本 |
| `send` | `Utter Agent -- Stream` | 发一轮，产物是**流** |
| `resend` | `Agent|Stream -- Stream` | 按现有会话重发 |
| `bcast` | `Utter Domain -- list Stream` | 广播到一组 agent |
| `drain` | `Stream -- String` | 取尽流文本 |
| `next` | `Stream -- Chunk|nil` | 取一块 |
| `stop` | `Stream -- Stream` | 中止流 |
| `watch` | `Agent -- Stream` | 视图流（主屏渲染源） |
| `subscribe` / `unsubscribe` | `Agent -- Agent` | 恢复 / 移出缺省广播域 |
| `->` | `Agent Agent -- Agent` | 线性血缘边 |
| `onfail` | `[ quot ] Agent -- Agent` | 失败回退引号 |
| `origin` | `Agent -- Seq` | 来源 |

### 12.1 一轮对话

```
agent "c" { }
dup
send say "你好"
drain
show
session
to-json
show
```

```
$ RB_LLM=mock ./bin/ravel examples/07-agent.breve
"回声：你好"
"[{\"content\":\"你好\",\"role\":\"user\"}]"
```

**一次求值 = 一轮**：`@RoundDone` 在求值**结束后**才把流合并进会话，
所以同一次求值里 `session` 还看不到 assistant。想在脚本里观察合并结果，
要么下一轮再看，要么用手动路径（§13.2），要么用 `--serve` 分两次请求（§15）。

### 12.2 第二轮、system 消息、广播

```
agent "c" { }
dup
append saysys "你是简洁的助手"
dup
send say "一"
drain
pop
pop
dup
send say "二"
drain
pop
session
map [ Content ]
```

> 每次 `send` 之后 `drain` 会压上一段文本，观察会话前记得 `pop` 掉它。

```
$ RB_LLM=mock ./bin/ravel -e '（同上）'
@["你是简洁的助手" "一" "二"]
```

```
$ ./bin/ravel -e 'agent "a" { }
agent "b" { }
bcast say "hi" { }'          # 空域 = 全部活 agent
```

（每轮结束默认钩子把回复合并进会话，所以 `bcast` 之后两个 agent 的 `session` 都多出
`user` + `assistant` 两条。）

### 12.3 血缘

```
$ ./bin/ravel -e 'agent "a" { }
agent "b" { }
->
origin'
("a")
```

---

## 13. 钩子

事件：`@Start` `@Chunk` `@Fail` `@Error` `@Close` `@Toolcall` `@Done` `@RoundDone`。
注册用 `@on 事件 [ 引号 ]`，注销用 `@off 事件 [ 引号 ]`（不给引号 = 清空该事件）。

**钩子不许改栈**（D-25）：钩子跑完，栈会被恢复到跑之前的深度。

### 13.1 观察块到达

```
@on @Chunk [ log
pop ]
agent "c" { }
send say "hi"
drain
```

```
$ RB_LLM=mock ./bin/ravel -e '（同上）'
"回声"


"：h"


"i"


"回声：hi"
```

（前几行来自 `log`：每块到达一次；最后一行是 `drain` 的返回值。）

`examples/09-hooks.breve` 是同一件事的脚本版（顺带演示手动合并）：

```
$ RB_LLM=mock ./bin/ravel examples/09-hooks.breve
"回声"


"：h"


"i"


"[{\"content\":\"hi\",\"role\":\"user\"},{\"content\":\"回声：hi\",\"role\":\"assistant\"}]"
"回声：hi"
```

### 13.2 关掉默认收尾钩子，自己合并（手动路径）

```
@off @RoundDone
agent "m" { }
dup
send say "hi"
append utter
session
to-json
```

```
$ RB_LLM=mock ./bin/ravel -e '（同上）'
"[{\"content\":\"hi\",\"role\":\"user\"},{\"content\":\"回声：hi\",\"role\":\"assistant\"}]"
```

自动路径与手动路径产出**同样的 session**：自动路径是默认 `@RoundDone` 钩子
（`Stream → Utter` → `append`），手动路径就这两步自己写。

### 13.3 上下文压缩

压缩策略属于使用者（核心只给零件）。一个「只留最近 4 条、换新 agent」的词：

```
shrink : "把会话截成最近 4 条，换新 agent" [ dup
  session
  take -4
  agent "c2" ]
```

```
shrink : "把会话截成最近 4 条，换新 agent" [ dup
  session
  take -4
  agent "c2" ]
agent "c" { }
dup
append say "1"
dup
append say "2"
dup
append say "3"
dup
append say "4"
dup
append say "5"
shrink
dup
session
len
show
pop
session
len
show
```

```
$ RB_LLM=mock ./bin/ravel -e '（同上）'
4
5
```

新 agent 只剩最近 4 条，老 agent 仍是 5 条（会话只追加、不改写，REQ-12）。

### 13.4 失败重试

重试也是钩子层的事，核心不内置：

```
@on @Fail [ pop resend pop ]
```

`@Fail` 的载荷是 `Fail Stream`（栈顶是 `Stream`），`resend` 接受 `Agent` 或 `Stream`。
不装这个钩子，同一次失败**不会**被静默重试。

---

## 14. 工具（函数调用）

```
deftool "add2" "把参数 a 加 2" [ at "a"
to-int
+ 2 ]
invoke "add2" H{ "a" 40 }
```

```
$ RB_LLM=mock ./bin/ravel examples/08-tools.breve
42
```

- `deftool`：`Name Desc [ quot ] --`，注册进工作区的工具表。
- `invoke`：`Name Json -- Json`，不经模型直接调用（脚本、测试、钩子都能用）。
- 模型自决调用：让 mock「模型」发起一次调用，看默认钩子跑通、会话里留下 `role:"tool"`：

```
$ RB_MOCK_TOOL='add2:{"a":40}' RB_LLM=mock ./bin/ravel -e 'deftool "add2" "把参数 a 加 2" [ at "a"
to-int
+ 2 ]
agent "c" { }
dup
send say "用 add2 算 40 加 2"
drain
pop
session
map [ Role ]'
@["user" "assistant" "tool"]
```

工具跑完后**同一条流继续**吐 assistant 文本；`@off @Toolcall` 之后事件照样推出，
但工具不跑——流停在「待外部动作」，需要前端 `invoke` + `append` + `resend` 接管。

真 provider 版本见 `tests/e2e/agent.sh`（`make test-agent`，不进 `make test`）。

---

### 14.5 处理流程：模式 ⇄ 钩子（dsh 四个预置的复刻）

「一轮请求怎么被处理」在这里是**一份数据**（模式），不是隐式的实现细节。
模式和**工作区现状**可以来回转换：`mode` 装进去，`mode-of` 取出来。

```
modes
```

```
$ RB_LLM=mock ./bin/ravel -e 'modes'
("cordis" "default" "minimal" "ptc" "standard")
```

模式表的形状（`mode-of` 的产物）：
`@{:kind :mode :name :doc :flags :hooks :prompt :tools :wire}`，
其中 `:hooks` **8 个事件全在**（未声明 = 空数组），于是"没挂钩子"和"没写这个事件"不会混淆。

五个预制模式（v1.0m / REQ-65）：`default` 是本仓的最小缺省，
另外四个是 [DeepSeek harness](https://github.com/deepseek-ai/deepseek-harness)
`packages/bundle/web-app/presets/*.patch.yml` 的复刻：

| 模式 | 工具 | 人格 / 提示 | 对应 dsh |
|---|---|---|---|
| `default` | 六个默认工具 | 无 | —（本仓自有）|
| `standard` | 六个默认工具 | 编码 agent（`{{model}}`）+ 工作目录 | `standard.patch.yml` |
| `ptc` | 六个默认工具 + `eval`，但 `:wire` 上只有 `eval` | PTC 说明 + 隐藏工具的绑定清单 | `ptc.patch.yml` |
| `minimal` | 只有 `shell` | **就一句** "You are a helpful software engineer assistant." | `minimal.patch.yml` |
| `cordis` | 六个默认工具 + `plugin` | `standard` + 「你可以修改自己」 | `cordis.patch.yml` |

每个模式还带**设定**（`--modes` 会印出来）：目前只有 `allow-shell`，
`shell` 靠它——声明了 `shell` 的模式一并把它带上（`设定：allow-shell=on`），于是"装好就能用"，
而不是让人再去设环境变量（§14.5.4 / REQ-67）。

> **不复制**：`web`（核心不含网络，REQ-37）、`jobs` / `schedule`（`shell` 已够）、
> `subagent`（本方言的 `agent` / `send` 就是语言级子代理）、`todo`（栈与会话已能表达）、
> `present` / `plugin-market`（没有对应基础设施）。

#### 注册 ≠ 公示（`:wire`）

一个模式的工具分两层：

- **注册**（`:tools`）：工具表里有它，`invoke` 调得到；
- **公示**（`:wire`）：`send` 时请求的 `tools` 字段里有它（模型**直接**看得见）。

`ptc` 就是"全都注册、只公示 `eval`"：模型看得到的只有 `eval` 一个工具，
而它写的程序里可以 `invoke` **任何**已注册工具。这与 dsh 的 PTC 一致
（wire 上只有 `run_code`，SDK 里能调全部）——两组工具于是被写进 `ptc` 的系统提示。

```
$ RB_LLM=mock ./bin/ravel -e 'mode "ptc"
mode-of
mode-tools'
("edit" "eval" "glob" "grep" "read" "shell" "write")
```

#### 14.5.1 切到 PTC 模式

- `ptc` **只公示一个工具** `eval`：模型不再逐步发 `tool_call`，而是把它要做的多步编排写成
  **一段 ravel 程序**，交给 `eval` 跑；返回的**栈顶**就是工具结果。
- 切模式会**撤掉所有预制模式声明过的工具**（避免模式互相污染）；用户自己的 `deftool` 不受影响。
- `ptc` 还带一段系统提示，它**只进请求**（前置一条 `role:"system"`），**不进会话历史**——
  否则历史会被说明文字污染，切回 `default` 后旧提示还留着。
- `mode-prompt` 给的是**模板原文**（`{{model}}` / `{{cwd}}` 还没代入）；
  替换发生在 `send` 那一刻，所以换模型 / 换目录立刻生效，不用重建模式。

### 14.5.2 完整例程：程序内串多个工具

```
deftool "add2" "把参数 a 加 2" [ at "a"
to-int
+ 2 ]
mode "ptc"
agent "c" { }
dup
send say "用程序算 40 加 2"
drain
pop
session
map [ Role ]
```

```
$ RB_MOCK_TOOL='eval:{"src": "invoke \"add2\" H{ \"a\" 40 }"}' RB_LLM=mock ./bin/ravel examples/12-ptc.breve
@["user" "assistant" "tool"]
```

模型只发**一次** `eval`；程序里那句 `invoke "add2" H{ "a" 40 }` 在 `eval` 内部运行。
真模型下把 `RB_MOCK_TOOL` 去掉即可（`ptc` 的系统提示会告诉它怎么写程序）。

程序失败（栈下溢、词不存在…）→ `60`（编排级），本轮作废，栈回到求值前（D-55）。

### 14.5.3 plan：正交于模式的开关（`enter-plan` / `exit_plan_mode`）

dsh 的 plan mode 不是第五个预置——它是**正交**的：`/plan` 进出，工具不换，只换提示。
本仓用**开关**复刻同一件事：

```
enter-plan
flag "plan"
```

```
$ RB_LLM=mock ./bin/ravel -e 'enter-plan
flag "plan"'
true
```

打开 `plan` 之后，本轮 system 提示 = 模式提示 + plan 段落（先探索、别改文件、把计划写全）；
同时 `exit_plan_mode` 才出现在 wire 上（**渐进披露**：没进过 plan 的会话看不见它）。

模型交计划时调用它（参数 `{ plan }`，markdown 以 `#` 开头）：

```
$ RB_LLM=mock ./bin/ravel -e 'enter-plan
invoke "exit_plan_mode" H{ "plan" "# 计划" }
flag "plan"'
"计划已提交，已退出 plan 模式：\n\n# 计划"
false
```

- 手动退出：`exit-plan`（同 dsh 的 `/plan off`）。
- 不在 plan 模式时调 `exit_plan_mode` → `60`。
- 进 plan **不换模式名、不换工具集、不换钩子**——这正是"正交"的意思。

### 14.5.4 模式的设定：工具与设定必须自洽（REQ-67）

v1.0m 复刻了 dsh 四个预置，却漏了预置带的**设定**：`default` 声明了 `shell`，
而 `shell` 那时要 `RB_ALLOW_SHELL=1`——于是在缺省模式里，模型第一次调 `shell` 就在回合中途失败：

```
ravel: @RoundDone 失败：流失败：工具失败：shell：shell 默认关闭：需要 RB_ALLOW_SHELL=1（…）
```

"装好就能用"被破坏成"看得见却一调就失败"。v1.0n 把这件事写成三条：

- **设定属于模式**：能力层声明「工具 → 前置设定」（能力键 `:tools/gates`，当前 `shell → allow-shell`）；
  模式声明了带前置设定的工具，就必须把开关一起声明。五个预制模式一律 `allow-shell = true`，
  所以**不切模式也是配好的**。
- **设定不满足的工具不上 wire**：模型看不见就不会在回合中途撞墙；注册表里它还在，
  `invoke` 给出点名到设定的 `60`。
- **可查、可关**：`--modes` 印设定；关掉一行 `flag-set false "allow-shell"`
  （或 `RB_ALLOW_SHELL=0`，环境变量优先）。

```
$ RB_LLM=mock ./bin/ravel -e 'invoke "shell" H{ "cmd" "echo hi" }'
"hi\n"
$ RB_LLM=mock ./bin/ravel --modes
  default    工具：edit glob grep read shell write
             设定：allow-shell=on
```

> 为什么不全交给环境变量：环境变量是**每台机器**的，工具清单是**每个模式**的。
> 后者才是"这个模式装了什么就该能用什么"的表达；环境变量只当显式覆盖（`RB_ALLOW_SHELL=0` 压过关）。

### 14.5.5 工具的参数：形状、别名、手误回给模型（REQ-68）

模型的工具调用是**它猜出来的**：请求里如果不写参数形状，它只能从描述里推。
v1.0n 之前的请求带的是空壳 `{"type":"object","additionalProperties":true}`——
于是 OpenCode / DeepSeek 把 `shell` 的参数写成 `command`，工具报「缺少参数 cmd」，
**整轮以 60 收场**。v1.0o 三件事：

1. **形状要写**：公示的每个工具都带具体 `parameters`（`properties` + `required`），
   属性描述里连别名一起写。
2. **别名要认**：`command` = `cmd`、`file_path` = `path`、`old_string` = `old`、`query` = `pattern`……
   取参先查规范名，再查别名（只「认」，不做语义变换）。
3. **手误回给模型**：模型发起的调用里，**参数错误**（缺参数 / 名字不认识 / 工具名写错）
   作为 `role = "tool"` 的结果回给它，本轮**继续**；环境侧失败（沙箱、读不到、执行失败）仍是 `60`。

```
# 别名：模型写 command 也照跑
$ RB_MOCK_TOOL='shell:{"command":"echo hi"}' RB_LLM=mock ./bin/ravel -e '...'
"hi\n"

# 名字彻底写错：错误回给模型，本轮不当失败
$ RB_LLM=mock ./bin/ravel -e 'invoke "read" H{ "pth" "README.md" }'
ravel: 工具失败：read：缺少参数 path（接受：path / file_path / filepath / file / filename）
$ echo $?
60
```

注意最后一条：**`invoke` 不走**"回给模型"那条路。脚本里的参数是程序员写的，
错了必须报 60；只有模型发起的调用才有"让它自己改一次"的余地。
用 `--modes` 看不到参数形状（那是给模型的），要查就看工具描述或规格 §4.14 的表。

### 14.5.6 历史标记：第几轮、从哪来、在哪个模式下

Utter 上默认打三个标记，**全部可关**：

| 开关 | 标记 | 含义 |
|---|---|---|
| `history-turn` | `:turn` | 第几轮（agent 内递增）|
| `history-origin` | `:from` | 产生它的 agent 标签 |
| `history-mode` | `:mode` | 产生它的处理流程名 |

```
agent "c" { }
dup
send say "hi"
drain
pop
session
```

```
$ RB_LLM=mock ./bin/ravel -e 'agent "c" { }
dup
send say "hi"
drain
pop
session'
@[@{:content "hi" :from "c" :mode "default" :role "user" :turn 1}]
```

关掉其中两个：

```
flag-set false "history-turn"
flag-set false "history-origin"
agent "c" { }
dup
send say "hi"
drain
pop
session
```

```
$ RB_LLM=mock ./bin/ravel -e 'flag-set false "history-turn"
flag-set false "history-origin"
agent "c" { }
dup
send say "hi"
drain
pop
session'
@[@{:content "hi" :mode "default" :role "user"}]
```

- 标记**不进请求**：`send` 重建的消息只有 `role` / `content` / `tool_calls`，
  provider 看不到本方言的内部记号。
- `flag` 读开关，未定义 → `nil`；`flag-set` 的值必须是布尔，否则 `31`。

### 14.5.7 把自己的钩子收成模式

`mode-of` 取的是**当前工作区**（包括你自己 `@on` 的钩子）：

```
@on @Chunk [ ]
mode-of
mode-name
```

```
$ RB_LLM=mock ./bin/ravel -e '@on @Chunk [ ]
mode-of
mode-name'
"default"
```

这份表可以存起来（`to-json` / 写文件），以后 `mode` 装回去——钩子、开关、提示、工具一起回来。

> 注意：`mode` 是**整体替换**钩子表，不是追加。想在某个模式上加观察者，先 `mode` 再 `@on`。

---

### 14.6 默认工具包（`read` / `write` / `edit` / `grep` / `glob` / `shell`）

能力层（`cap/tools.janet`）建工作区时就装好六个工具，所以 `invoke` 直接能用，
模型自决调用走的也是同一批（REQ-48 的默认 `@Toolcall` 钩子）：

```
invoke "glob" H{ "pattern" "src/*.c" }
```

```
$ RB_LLM=mock ./bin/ravel -e 'invoke "glob" H{ "pattern" "src/*.c" }'
"src/main.c"
```

| 工具 | 参数 | 结果 |
|---|---|---|
| `read` | `{ path, offset?, limit? }` | 带行号逐行读；`offset` 从 1 起，`limit` 缺省 400 / 上限 2000；截断时提示续读 |
| `write` | `{ path, content }` | **原子替换**整个文件（临时文件 + rename），返回字节数 |
| `edit` | `{ path, old, new }` | 把 `old` 的所有出现换成 `new`（**字面量**）；一处没找到 → `60` |
| `grep` | `{ pattern, path? }` | 逐行 `path:行号: 文本`（字面量，最多 200 条）|
| `glob` | `{ pattern, dir? }` | `*` / `?` 段内、`**` 任意层；一行一个路径（最多 200 条）|
| `shell` | `{ cmd }` | `sh -c` 的 stdout；非零退出附 `[退出码 N]`；需要设定 `allow-shell`（缺省开）|

```
$ RB_LLM=mock ./bin/ravel -e 'invoke "grep" H{ "pattern" "beta" "path" "build/tmp/g.txt" }'
"build/tmp/g.txt:2: beta"
$ RB_LLM=mock ./bin/ravel -e 'invoke "edit" H{ "path" "build/tmp/g.txt" "old" "beta" "new" "gamma" }'
"已改 1 处：build/tmp/g.txt"
```

- 参数还可以写**别名**（§14.5.5）：`command` = `cmd`、`file_path` = `path`、`old_string` = `old`……
  模型常写的那几个都在表里；`invoke` 用别名的效果与规范名相同。
- 五个文件工具都守 **D-60 的沙箱**（根 = 当前目录）：越界 → `60`（工具本体失败）。
- `grep` / `glob` 是**字面量/通配**，不是正则：`edit` 的 `old` 抄错一个字就会报「找不到」。
- `shell` 有自己的**前置设定** `allow-shell`（§14.5.4）：它随模式一起来，所以缺省就能用；
  一句 `sh -c` 等于绕过文件沙箱，所以关掉它只需要一行：

```
$ RB_LLM=mock ./bin/ravel -e 'invoke "shell" H{ "cmd" "ls src" }'
"main.c\n"
$ RB_LLM=mock ./bin/ravel -e 'flag-set false "allow-shell"
invoke "shell" H{ "cmd" "ls src" }'
ravel: 工具失败：shell：shell 已被关掉：allow-shell 设定为 false（…）    # 60
$ RB_ALLOW_SHELL=0 RB_LLM=mock ./bin/ravel -e 'invoke "shell" H{ "cmd" "ls src" }'
ravel: 工具失败：shell：shell 已被关掉：…                                # 60（环境变量压过模式设定）
```

- 它们**不是方言词**：在脚本里写 `edit` 是 20（未知的词），要么 `invoke`，要么让模型调用。
- 切模式（§14.5）时这些工具会跟着当前模式走；你自己 `deftool` 的工具不受影响。

---

### 14.7 用量记账：`usage`

provider 报的 token 用量会记进**工作区**（不是某个流），`usage` 读一份**拷贝**：

```
agent "c" { }
send say "你好"
drain
usage
show
```

```
@{:calls 1 :completion-tokens 5 :prompt-tokens 2 :total-tokens 7}
"回声：你好"
```

要点：

1. **`calls` = 报过账的 provider 请求数**。一轮工具调用会跨多次请求，因此一次 `send`
   可能让 `calls` 加 2（工具批一次 + 最终文本一次），token 也各记一笔。
2. 用量块是**元信息块**：不产生 `@Chunk`、不进流文本、不参与渲染——所以它不会污染回复。
3. 真 provider 未必每帧都带 `usage`；不带就不记（`calls` 不涨），**不会报错**。
4. 阈值触发的压缩就靠它起头（REQ-50 仍要求压缩策略写在钩子里）：

```
@on @RoundDone [ at "total-tokens" usage
8000 >
if [ "该压缩了" log ] [ ] ]
agent "c" { }
send say "你好"
drain
```

（`if` 的两个引号写法要求「条件已在栈上」，所以条件单独成一行；写成
`... 8000 > if [ … ] [ … ]` 会被当成"条件内联"的形式而报错。）

实际压缩仍按 §13.3 的写法（`take` + `saysys` + 新 `agent`），核心不内置算法。

### 14.8 取消：`cancel` 与 `stop` 的血缘传播

```
agent "c" { }
send say "你好"
stop
cancel
show
```

- `stop` 停**一条**流；如果这条流属于上游 agent（`->` 的前者），沿血缘把下游一并停——
  上游作废，下游的产物就没有意义（`onfail` / 广播域用的是同一条边）。
- `cancel` 停**所有还开着的流**，返回停下的个数（空工作区 = `0`）。
- 协议侧同名请求 `{"type":"cancel"}` → `{"ok":true,"stopped":N}`，**不结束会话**；
  前端「停止按钮」就发它。
- 截止时间：`RB_STREAM_DEADLINE_MS=5000` 给每条流 5 秒。超时 = 流失败 + 退出码 `60`
  （编排级），不是「空回复 + 0」。

### 14.9 自定义请求头：`headers`

有些网关不认默认的请求头：要 `X-Trace`、要组织号、要一个自家客户端的
`User-Agent`。这些**不是 provider 的事**，所以放进配置（D-65）：

```
llm-set H{ "X-Trace" "abc-123" "User-Agent" "my-agent/1" } "headers"
agent "c" { }
send say "只回答两个字：收到"
drain
show
```

规则四条：

1. **两种写法都行**：工作区配置给表（如上），或环境变量 `RB_HEADERS` 给
   `X-Trace:abc-123,User-Agent:my-agent/1`（也可给 JSON 对象）。
2. **同名覆盖内置**：`User-Agent`、`Accept` 都能换；没覆盖的项（`Authorization`、
   `Content-Type`）照旧由 provider 生成。所以**别**把 `Authorization` 往 `headers` 里塞——
   密钥不属于配置（会随快照落盘，见 §1.2.3 与 D-54）。
3. **对拉模型列表也生效**（§14.10）——网关连 `/models` 都要关门时这一点很要紧。
4. 优先级照旧：**工作区配置 > 环境变量 > 空**；写 `nil` = 删掉该项。

坏输入（JSON 不是对象、既不是表也不是字符串）报 **31**：这是配置写错了，
不是编排失败。

### 14.10 模型列表与自动配置：`llm-models` / `llm-auto`

模型名是最易变的东西。与其把名字焊在环境变量里，不如**问一次**：

```
llm-models
len
show
llm-auto
show
llm-get "model"
show
```

- `llm-models`：`-- Seq`。真的请求一次 `GET <基址>/models`（基址 = 端点去掉
  `/chat/completions`），压回模型名数组。**不缓存**：列表会变，缓存就是隐藏状态。
- `llm-auto`：`-- String`。拉列表 → 挑一个 → **写回工作区 `model`** → 压回名字。
  挑选顺序：**工作区里显式设过的 `model`（还在列表里就保留）** > `RB_MODEL_PREFER`
  （逗号分隔）> provider 内置偏好 > 列表第一条。内置**缺省**不算「显式设过」——
  否则偏好表永远轮不到它。
- 想让每轮都重新解析：`llm-set "auto" "model"`——`model` 是 `"auto"` 时，
  每次请求前解析一次（结果落回工作区，`dump` 看得见）。

真 provider 上的样子（OpenCode，38 个模型）：

```
$ RB_LLM=opencode ./bin/ravel -e 'llm-models
len
show
llm-auto
show
llm-get "model"
show'
38
"deepseek-v4.1-flash"
"deepseek-v4.1-flash"
```

换一个偏好：

```
$ RB_LLM=opencode RB_MODEL_PREFER=kimi-k3,qwen3.8-max ./bin/ravel -e 'llm-auto
show'
"kimi-k3"
```

`mock` provider 不联网：列表就是 `@["mock"]`，`llm-auto` 得 `"mock"`。
所以例程与测试仍然 hermetic（见 `examples/15-headers-models.breve`）。

### 14.11 一键配置：预设（`llm-import` / `llm-export`）

一次设四项配置（provider / 模型 / 上限 / 温度）要四行 `llm-set`。**预设**把它压成一行，
并且能存下来给下次、给别的机器、给同事：

| 词 | 栈效应 | 作用 |
|---|---|---|
| `llm-import` | `NameOrPath -- Table` | 导入预设；**只**覆盖预设里出现的键 |
| `llm-export` | `Path -- Int` | 把**显式配置**写成预设文件；返回写入项数 |

**名字解析**：带 `/` 或以 `.json` 结尾 = 路径；否则 = `presets/<名字>.json`。仓库自带三份：

```
$ ls presets/
mock.json  nvidia.json  opencode-go.json
```

`presets/opencode-go.json` 长这样（**没有密钥**，密钥只从环境变量或 `secrets/*.key` 来）：

```json
{ "provider": "opencode", "model": "deepseek-v4.1-flash", "max-tokens": 1024, "temperature": 0.2 }
```

#### 先看有什么（`--presets` / `--modes`，v1.0l）

「有哪些预设、装的是什么、在哪个目录」不用翻仓库：

```
$ ./bin/ravel --presets
配置预设（/home/u/project/RavelBreve/presets）：
  mock           provider=mock       model=mock
  nvidia         provider=nvidia     model=meta/llama-3.2-11b-vision-instruct
  opencode-go    provider=opencode   model=deepseek-v4.1-flash
用户配置文件：已关闭（RB_CONFIG=- / --no-config）
用法：ravel --preset <名字>  或  ravel --preset presets/<名字>.json（相对当前目录）

$ ./bin/ravel --modes
处理流程模式：
  cordis     工具：edit glob grep plugin read shell write
             dsh preset cordis 的复刻：standard + 改自己（plugin 工具装卸插件）
  default    工具：edit glob grep read shell write
             缺省：收尾钩子把流合并进会话，工具调用自动执行（REQ-18 / REQ-48）
  minimal    工具：shell
             dsh preset minimal 的复刻：只有 shell；人格是完整系统提示，不带运行时上下文
  ptc        工具：edit eval glob grep read shell write
             dsh preset ptc 的复刻：wire 上只有 eval（呈现层），程序里 invoke 任何工具
  standard   工具：edit glob grep read shell write
             dsh preset standard 的复刻：编码 agent 的人格 + 完整文件工具 + shell
用法：mode "<名字>"（在方言里切换；`modes` 词也一样能列名字）
```

- 两个开关都是**只读查询**：不建工作区、不求值、不装载任何预设，**输出即结果**，退出码 `0`。
- 目录里没有 `.json` 也返回 `0`（并明说"这个目录里没有"）；某份预设**写坏了**只影响它那一行
  （显示 `<读不出来：原因>`），其余照列——一本目录里有一页坏了，不该导致整本书不能查。
- `--core-only` 下 `--presets` → **60**（那时没有能力层、没有 JSON）；`--modes` 属核心，照常可用。
- **名字打错不用猜**：报错直接给可用名字
  （`预设文件不存在或无权限：presets/provier.json（可用：mock nvidia opencode-go）`）。
- **搜索路径没有变**（v1.0l 明确"不做多路径搜索"）：名字仍只查 `presets/<名字>.json`（相对当前目录）。
  要在任何目录都能用，就把配置放进用户配置文件（REQ-63）而不是加搜索路径——
  隐式搜索路径会制造"到底装的是哪一份"的歧义。

#### 三种用法

**① 启动时一键装**（最省事）：

```
$ ./bin/ravel --preset opencode-go -e 'llm-get "provider"
show'
"opencode"
```

环境变量写法等价：`RB_PRESET=opencode-go`（逗号分隔可以一次装几份，按序叠加）。

**② 用户配置文件**：把预设存到 `~/.config/ravel/config.json`（或 `RB_CONFIG` 指定的路径），
**下次启动自动装**，stderr 会通报一行：

```
$ printf '{"provider":"opencode","model":"deepseek-v4.1-flash"}\n' > ~/.config/ravel/config.json
$ ./bin/ravel -e 'llm-get "provider"
show'
ravel: 已装载配置 /home/u/.config/ravel/config.json
"opencode"
```

不想让它生效：`--no-config`（等价 `RB_CONFIG=-`）。**测试里一律关掉**（`make test` 已经这么做了）。

**③ 运行中导入 / 导出**：

```
$ RB_LLM=mock ./bin/ravel -e 'llm-import "opencode-go"
llm-set 2048 "max-tokens"
llm-export "build/tmp/mine.json"
show'
4
```

导出的就是「显式配置」，再 `llm-import` 回来**逐键一致**（往返）：

```
$ ./bin/ravel --preset build/tmp/mine.json -e 'llm-get "max-tokens"
show'
2048
```

#### 四条硬规则

1. **只写白名单键**：预设里出现 `key` → 60；拼错配置项（`provier`）→ 31。与 `llm-set` 同一份校验。
2. **只覆盖出现的键**：一份预设只改它写了的项，别的原样保留——所以预设**可叠加**。
3. **导出只导显式的**：`endpoint`、`temperature` 这类由环境变量或缺省推出来的值**不写进预设**
   （`RB_OC_BASE` 是这台机器的事）。要固化就显式 `llm-set` 一次。
4. **密钥永不进预设**：`headers` 里带 `Authorization` / `api-key` / `token` / `secret` /
   `cookie` 之类 → 导出报 **60**，且不创建文件。预设天生是要被复制、提交、贴给别人的。

#### 优先级（D-54 的延伸）

**`--preset` / `llm-set`（运行中写的）> 用户配置文件 > 环境变量 > 内置缺省**。
用户配置文件之所以在环境变量之上，是因为它**写进工作区配置**——而工作区配置本来就赢环境变量。

#### 一条命令配好 OpenCode Go

`tools/oc-setup.sh` 把「存密钥 + 存配置」合成一步（**不是词**，是宿主脚本）：

```
$ tools/oc-setup.sh sk-xxxx            # 密钥 → secrets/opencode.key，预设 → ~/.config/ravel/config.json
$ tools/oc-setup.sh --verify sk-xxxx    # 顺手拉一次模型列表验证
$ tools/oc-setup.sh --local             # 不想写家目录：配置写 ./.ravel.json（用 RB_CONFIG 指它）
```

- 密钥文件已存在时**拒绝覆盖**（`--force` 换，换之前自动留 `.bak`）——防止手滑把能用的钥匙冲掉。
- 密钥与配置**分开放**：配置可以随便复制，密钥不会跟着跑。

## 15. 前端协议（`--serve`）

一行一条 JSON。裸文本行 = `eval` 的简写；显式请求：

```json
{"type":"eval","src":"+ 1 2","id":7}
{"type":"ping"}
{"type":"reset"}
{"type":"cancel"}
{"type":"quit"}
```

响应：`hello` / `pong` / `result` / `chunk` / `close` / `event` / `bye`。
细节见 `docs/PROTOCOL.md`，前端契约见 `docs/FRONTEND.md`。

`examples/10-serve.sh`（真实输出）：

```
$ ./examples/10-serve.sh
{"protocol":1,"type":"hello","version":"ravel breve 1.0o · janet 1.42.1"}
{"ok":true,"stack":["@{:kind :agent :label \"c\" … :turn 0}"],"type":"result"}
{"n":0,"stream":"c","text":"回声","type":"chunk"}
{"n":1,"stream":"c","text":"：你","type":"chunk"}
{"n":2,"stream":"c","text":"好","type":"chunk"}
{"ok":true,"stream":"c","type":"close"}
{"ok":true,"stack":["…","\"回声：你好\""],"type":"result"}
{"ok":true,"stack":["@[\"你好\" \"回声：你好\"]"],"type":"result"}
{"ok":true,"stack":["@[\"你好\" \"回声：你好\"]"],"type":"result"}
{"ok":true,"stack":["@[\"你好\" \"回声：你好\"]","42"],"type":"result"}
{"ok":true,"stack":["@[\"你好\" \"回声：你好\"]","42","2","1"],"type":"result"}
{"ok":true,"stack":[],"type":"result"}
{"code":20,"error":"未知的词：w","ok":false,"type":"result"}
{"protocol":1,"type":"pong"}
{"protocol":1,"type":"bye"}
```

三个要点：

1. **工作区跨请求保留**：第二条请求还能用第一条请求里的 agent；栈也保留（`42`、`2`、`1` 越堆越多）。
2. **`chunk` 立刻推**，`close` 一轮一次；前端只按 `n` 排序即可。
3. **`reset`** 丢掉工作区，之后的 `w` 就成了未知的词（20）。

---

## 16. 退出码

| 码 | 含义 | 触发例 |
|---|---|---|
| 0 | 成功 | 一切正常 |
| 1 | 一般失败 | — |
| 2 | 用法 / 协议错误 | `--serve` 收到坏 JSON、`eval` 缺 `src` |
| 10 | 字符串未闭合 | `"unterminated` |
| 11 | 块未闭合 | `[ 1 2` |
| 12 | 非法转义 | `"\q"` |
| 20 | 未知的词 | `未知的词` |
| 21 | 多余的 `}` | `{ 1 } }` |
| 22 | 定义或字面量非法 | `名字 : 1` |
| 23 | 宿主编译失败 | — |
| 30 | **栈下溢** | `pop` |
| 31 | 类型 / 取值 | `len 3`、`map 5 { 1 }` |
| 32 | 元数错误 | 引号参数个数不对 |
| 33 | `fail` / 断言失败 | `fail "炸了"` |
| 40 | 读失败 | `read "/nope"` |
| 41 | 写失败 | `write "x" "/nope/x"` |
| 50 | 内部错误 | — |
| 51 | 宿主内部 | — |
| 60 | 编排 / 能力缺失 | 未注册的工具、真 provider 报错（坏模型名、404 错误页）、`--core-only` 里的 JSON 词 |

```
$ ./bin/ravel -e 'pop'; echo $?
ravel: 栈下溢
30

$ ./bin/ravel -e 'len 3'; echo $?
ravel: expected string, symbol, keyword, array, tuple, table, struct or buffer, got 3
31

$ ./bin/ravel -e 'invoke "nope" { }'; echo $?
ravel: 未注册的工具：nope（先 deftool 注册，REQ-48）
60
```

---

## 17. 插件与 skills

**插件 = 一个 `.breve` 文件**，用方言本身写。没有新语法、没有新文件格式、没有宿主侧 API：
它就是「一串定义行 + `@on` + `deftool`」打包成可分发、可一键卸载的东西。

### 17.1 三个词

```
plug "plugins/audit.breve"      # Path -- String（插件名 = 文件名去扩展名）
plugins                         # -- Seq（已装，升序）
unplug "audit"                  # Name -- Int（撤掉的项数：词 + 钩子 + 工具）
```

```
$ printf 'plug "skills/ravel-breve-plugin/plugin.breve"\nplugins\n' | ./bin/ravel
ravel> "plugin"
ravel> ("plugin")
```

**词在下一轮才可见**（转译先于执行，和 `load` 一样）：同一份源里 `plug` 后立刻用会报 20。
REPL 里一行就是一轮，所以：

```
$ printf 'plug "skills/ravel-breve-plugin/plugin.breve"\nsum2 40 2\n' | ./bin/ravel
ravel> "plugin"
ravel> 42
```

### 17.2 插件里能装什么（用户层 ⊂ 插件）

| 装什么 | 写法 | 卸载时 |
|---|---|---|
| 词 | `名字 : "说明" [ 体 ]` | 从字典删除；若它重定义了旧词则**还原旧词条** |
| 钩子 | `@on @Close [ … ]` | 从钩子表摘掉那一个引号 |
| 工具 | `deftool "名字" "说明" [ … ]` | 从工具表删除（旧工具体一并还原）|

**核心层装不了**：词法 / 转译 / 栈 / 流 / agent / 钩子机制 / 持久化 / 协议 / 退出码 / 核心词表
都不是插件能碰的；事件名也是闭集（`@Start` … `@RoundDone` 之外 → 31）。
判断标准很简单：**这件事用户手打同样的源能不能做**——能，就是插件；不能，那是规格修订。

样板（`skills/ravel-breve-plugin/plugin.breve`，可直接跑）：

```breve
sum2 : "两个数相加（Sum2 -- N）" [ + ]

@on @Close [ flag-set true "saw-close" ]

deftool "sum" "把两个整数相加" [ dup
at "a"
swap
at "b"
+ ]
```

```
$ ./examples/16-plugins.sh
ravel> "plugin"
ravel> ("plugin")
ravel> 42
ravel> 42
ravel> 3
ravel> ()
```

（依次是：插件名 / 台账 / 插件里的词 / 插件里的工具 / 撤了几项 / 台账空了。）

### 17.3 装与卸的语义

- **不算一轮**：装载不触发 `@RoundDone`、不往本轮列表塞东西、不写日志/快照；
  栈深前后不变（插件里残留的操作数不外溢）。
- **原子**：插件里任何一步失败 → 已装的部分**全部撤销**，原错误码透出。
  ```
  $ ./bin/ravel -e 'plug "tests/fixtures/plugins/fail.breve"'; echo $?
  ravel: 插件炸了

  33
  ```
- **精确撤销 + 同名重装**：`unplug` 只撤这个插件的；同名插件再装 = 先卸旧账，不留孤儿注册。
- **无传递依赖**：插件里再 `plug` → 31。要一次装多个：
  ```
  $ RB_PLUGINS=plugins/audit.breve,plugins/toolkit.breve ./bin/ravel -e 'plugins'
  ("audit" "toolkit")
  ```
- **不能新增能力**：能力表只有宿主可写。所以 `--core-only` 构建下 `plug` 报 **60**
  （它读插件文件本身要用 `:fs/read`）——这是 REQ-37 的边界，不是 bug。
- **已知的不可逆副作用**：插件可以 `@off` 掉默认钩子，`unplug` **不会**把它装回来
  （`@off` 是用户对工作区的显式动作）；想恢复就 `mode "default"`。
- 沙箱默认只允许读**当前目录**：插件放在别处又不设 `RB_SANDBOX` → 40。

### 17.4 写插件时的三个硬约束

1. **一行一条语句**：`[ at "a" + 1 ]` 写在**一行**里 = `at` 带三个操作数，不是三条语句。
2. **词一律前缀**（`+ 1` 不是 `1 +`）；字符串拼接用 `,`（`join2`），`+` 只做数值加法。
3. **工具体第一步是 `at "参数"`**，参数表由宿主压栈；取第二个字段前先 `dup` 保住表。

完整的写插件指南（分层、ABI、自检清单、常见错误表）在 `skills/ravel-breve-plugin/SKILL.md`；
装上你的 agent 客户端后可以直接当 skill 用。

---

## 18. 常见坑（十二条）

1. **一行 = 一个语句**。`1 2 +` 不是「压 1、压 2、加」，是镜像后的 `+ 2 1` → 30。
   要分步就换行。
2. **只写一个操作数时，字面量填最左**：`- 1` 是 `1 - n`，`< 2` 是 `2 < n`。
   算 `n - 1` 写 `+ -1`。
3. **块里也要换行**：`[ pop 1 ]` 会先压 1 再 `pop`。要「弹掉再压 1」写两行。
4. **`-e` / REPL 的打印顺序是栈底 → 栈顶**，字符串带引号（渲染文本）。
5. **一次求值 = 一轮**：默认 `@RoundDone` 在求值结束后才合并会话；
   同一次求值里 `session` 看不到 assistant——用下一轮或手动路径。
6. **钩子不许改栈**：跑完会恢复到原深度。
7. **`save` 的参数序**：路径先入栈，工作区在栈顶（`save current`）。
8. **`load` 载入的词下一轮才可见**：同一个 `-e` 里立刻用会报 20。
9. **未冻结的词**（`seq` `par` `Json` `push`）仍然是 20；别指望它们。
10. **诊断只走 stderr**：`show`/`print`/`log`/`dump` 不进 stdout，stdout 只有协议。
11. **报错不脏栈**：失败的那次求值整体回滚（D-55），栈上看不到半截操作数；
    想查现场就先用 `dump`，或者在出错**前**把值留好。
12. **配置在启动后也能改**：`RB_LLM` 等环境变量只是缺省；`llm-set "mock" "provider"`
    当场生效（优先级：工作区配置 > 环境变量 > 缺省，D-54）。

---

## 19. 词表速查

| 层 | 词 |
|---|---|
| L0 栈 | `dup` `pop` `swap` `rot` `-rot` `keep` `dip` `apply` `call` |
| L1 序列 / 文本 | `,` `,,` `len` `first` `last` `take` `drop` `map` `filter` `fold` `split` `at` `nth` `reverse` `sort` `zip` `show` `print` `wait` `retry` `log` |
| L1b 算术 / 布尔 | `=` `!=` `<` `>` `<=` `>=` `not` `and` `or` `+` `-` `*` `/` `mod` `abs` `min` `max` `sum` |
| L1c 字符串 | `trim` `replace` `contains` `starts-with` `ends-with` `lines` `words` |
| L1d 转换 | `to-string` `to-int` |
| L2 消息 / JSON | `say` `saysys` `Role` `Content` `to-json` `from-json` `at` |
| L3 会话 / 发送 | `send` `bcast` `resend` `append` `session` |
| L4 agent / 编排 | `agent` `origin` `watch` `unsubscribe` `subscribe` `->` `onfail` |
| L5 控制流 | `if` `when` `unless` `loop` `while` `try` `recover` |
| L5b 错误 / 环境 | `fail` `assert` `depth` `dump` `now` `env` |
| L6 元词表 | `:` `see` `doc` `define` |
| L7 持久化 / 工作区 | `read` `write` `current` `save` `load` `compact` `usage` |
| L8 钩子 / 工具 | `@on` `@off` `deftool` `invoke` `resend` `stop` `cancel` `drain` `next` |
| L9 前端 | `watch` `subscribe` `unsubscribe` |
| L9b 插件 | `plug` `plugins` `unplug` |
| L10 处理流程 | `mode` `modes` `mode-of` `mode-name` `mode-prompt` `mode-tools` `flag` `flag-set` `enter-plan` `exit-plan` |
| provider 配置 | `llm` `llm-get` `llm-set` `llm-models` `llm-auto` `llm-import` `llm-export` |

完整栈效应见 `ravel-breve-spec-v1.0o.md` 附录 A；未冻结项见 `docs/SPEC-FEEDBACK.md`
（v1.0e 已把 SF-14…SF-35 冻结；v1.0f 加 REQ-52 处理流程层；v1.0g 加沙箱与默认工具；
v1.0h 加用量 / 取消 / 截止时间；v1.0i 加自定义请求头与模型列表；
v1.0j 加插件 ABI 与 skills；v1.0k 加配置预设与启动装载；v1.0l 加预制的可发现性；
v1.0m 加 dsh 四个预置的复刻、`wire` 呈现层与正交的 plan）。

---

## 20. 例程目录

| 文件 | 主题 |
|---|---|
| `examples/01-stack.breve` | 镜像读法、字面量、`at` |
| `examples/02-words.breve` | 定义词、文档串、常量、递归 |
| `examples/03-seq-text.breve` | 序列 / 文本工具全览 |
| `examples/04-control.breve` | 条件、循环、`try`、`retry`、断言 |
| `examples/05-json.breve` | JSON 往返 |
| `examples/06-files.breve` | 文件读写 + 工作区快照 |
| `examples/07-agent.breve` | 一轮对话与会话 |
| `examples/08-tools.breve` | 工具定义与 `invoke` |
| `examples/09-hooks.breve` | `@Chunk` 钩子、手动合并路径 |
| `examples/10-serve.sh` | 前端协议：`chunk`/`close`/跨请求状态/`reset` |
| `examples/11-llm-config.breve` | provider 配置：`llm-get` 生效值、`llm-set` 预置 |
| `examples/12-ptc.breve` | PTC 模式：`mode`、只有 `eval` 工具、程序内串工具 |
| `examples/13-tools.breve` | 默认工具包：`glob` / `grep` / `edit`（`shell` 默认关）|
| `examples/14-usage-cancel.breve` | 用量记账（`usage`）与取消（`stop` / `cancel`）|
| `examples/15-headers-models.breve` | 自定义请求头（`headers`）、模型列表（`llm-models`）与自动配置（`llm-auto`）|
| `examples/16-plugins.sh` | 插件：`plug` / `plugins` / `unplug` 的装-用-卸全程 |
| `examples/17-presets.sh` | 配置预设：`--preset` / `RB_PRESET` / 用户配置文件 / `llm-import` / `llm-export` |
| `examples/18-modes.sh` | 处理流程模式：五个预置、wire（注册 ≠ 公示）、plan 正交、模式设定（REQ-67）|
| `examples/run-all.sh` | 一次跑完上面全部 |

```
$ ./examples/run-all.sh; echo $?     # 0 = 全绿
```
