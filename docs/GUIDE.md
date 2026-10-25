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
ravel breve 1.0h · janet 1.42.1

$ ./bin/ravel -h
用法：
  ravel                     REPL（提示符 ravel> ）
  ravel -e "<一行>"           求值一行，打印剩余栈
  ravel script.breve        执行脚本
  ravel --serve             NDJSON over stdio（REQ-24）
  ravel --dump ...          打印转译产物（REQ-31）
  ravel --json ...          按协议消息形状输出（REQ-22）
  ravel -v | -h
```

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

#### 1.2.3 运行中换配置：`llm` / `llm-get` / `llm-set`

环境变量只能在**启动前**定死。要在一局里换 provider、换模型、改上限，
把配置写进**工作区**（D-54）：

| 配置项 | 环境变量（次优先） | 内置缺省 | 说明 |
|---|---|---|---|
| `provider` | `RB_LLM` | `auto` | `nvidia` / `mock` / `auto`（`auto` = 有密钥就真、否则 mock） |
| `model` | `RB_MODEL` | `meta/llama-3.2-11b-vision-instruct` | 真 provider 的模型名 |
| `endpoint` | `RB_ENDPOINT` | NVIDIA 官方端点 | 兼容 OpenAI 形状的服务也能接 |
| `max-tokens` | `RB_MAX_TOKENS` | `512` | 本轮回复上限 |
| `temperature` | `RB_TEMPERATURE` | `0.2` | 采样温度 |

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
| 删前一字 / 删光标处 | `Backspace` / `C-d`（`Delete`） | `x`（normal） |
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

宿主侧原语表是 `(dyn :rb-term)`（`src/main.c` 提供 `tty` / `raw-on` / `raw-off` /
`read-key`）：方言层取不到它就退回行模式，所以裸 `janet` 跑单元测试也能装载内核。

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

### 14.5 处理流程：模式 ⇄ 钩子（PTC）

「一轮请求怎么被处理」在这里是**一份数据**（模式），不是隐式的实现细节。
模式和**工作区现状**可以来回转换：`mode` 装进去，`mode-of` 取出来。

```
modes
```

```
$ RB_LLM=mock ./bin/ravel -e 'modes'
("default" "ptc")
```

模式表的形状（`mode-of` 的产物）：`@{:kind :mode :name :doc :flags :hooks :prompt :tools}`，
其中 `:hooks` **8 个事件全在**（未声明 = 空数组），于是"没挂钩子"和"没写这个事件"不会混淆。

### 14.5.1 切到 PTC 模式

```
mode "ptc"
mode-of
mode-tools
```

```
$ RB_LLM=mock ./bin/ravel -e 'mode "ptc"
mode-of
mode-tools'
("eval")
```

- `ptc` **只留一个工具** `eval`：模型不再逐步发 `tool_call`，而是把它要做的多步编排写成
  **一段 ravel 程序**，交给 `eval` 跑；返回的**栈顶**就是工具结果。
- 切模式会**撤掉所有预制模式声明过的工具**（避免模式互相污染）；用户自己的 `deftool` 不受影响。
- `ptc` 还带一段系统提示，它**只进请求**（前置一条 `role:"system"`），**不进会话历史**——
  否则历史会被说明文字污染，切回 `default` 后旧提示还留着。

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

### 14.5.3 历史标记：第几轮、从哪来、在哪个模式下

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

### 14.5.4 把自己的钩子收成模式

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

### 14.6 默认工具包（`edit` / `grep` / `glob` / `shell`）

能力层（`cap/tools.janet`）建工作区时就装好四个工具，所以 `invoke` 直接能用，
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
| `edit` | `{ path, old, new }` | 把 `old` 的所有出现换成 `new`（**字面量**）；一处没找到 → `60` |
| `grep` | `{ pattern, path? }` | 逐行 `path:行号: 文本`（字面量，最多 200 条）|
| `glob` | `{ pattern, dir? }` | `*` / `?` 段内、`**` 任意层；一行一个路径（最多 200 条）|
| `shell` | `{ cmd }` | `sh -c` 的 stdout；非零退出附 `[退出码 N]`；**默认关闭** |

```
$ RB_LLM=mock ./bin/ravel -e 'invoke "grep" H{ "pattern" "beta" "path" "build/tmp/g.txt" }'
"build/tmp/g.txt:2: beta"
$ RB_LLM=mock ./bin/ravel -e 'invoke "edit" H{ "path" "build/tmp/g.txt" "old" "beta" "new" "gamma" }'
"已改 1 处：build/tmp/g.txt"
```

- 三个文件工具都守 **D-60 的沙箱**（根 = 当前目录）：越界 → `60`（工具本体失败）。
- `grep` / `glob` 是**字面量/通配**，不是正则：`edit` 的 `old` 抄错一个字就会报「找不到」。
- `shell` 默认关闭，要显式开：

```
$ RB_LLM=mock ./bin/ravel -e 'invoke "shell" H{ "cmd" "ls src" }'
ravel: 工具失败：shell：shell 默认关闭：需要 RB_ALLOW_SHELL=1（…）    # 60
$ RB_ALLOW_SHELL=1 RB_LLM=mock ./bin/ravel -e 'invoke "shell" H{ "cmd" "ls src" }'
"main.c\n"
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
{"protocol":1,"type":"hello","version":"ravel breve 1.0h · janet 1.42.1"}
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

## 17. 常见坑（十二条）

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

## 18. 词表速查

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
| provider 配置 | `llm` `llm-get` `llm-set` |

完整栈效应见 `ravel-breve-spec-v1.0h.md` 附录 A；未冻结项见 `docs/SPEC-FEEDBACK.md`
（v1.0e 已把 SF-14…SF-35 冻结；v1.0f 加 REQ-52 处理流程层；v1.0g 加沙箱与默认工具；
v1.0h 加用量 / 取消 / 截止时间）。

---

## 19. 例程目录

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
| `examples/run-all.sh` | 一次跑完上面全部 |

```
$ ./examples/run-all.sh; echo $?     # 0 = 全绿
```
