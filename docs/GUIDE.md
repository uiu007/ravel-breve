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
ravel breve 1.0d · janet 1.42.1

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

### 1.2 provider 开关（只有它影响「谁来回话」）

| 环境变量 | 取值 | 说明 |
|---|---|---|
| `RB_LLM` | `mock` / `nvidia` / `auto`（缺省） | 换 provider 不用改一行方言代码 |
| `RB_MOCK_REPLY` | 任意字符串 | mock 的固定回复；缺省是「回声：<最后一条消息>」 |
| `RB_MOCK_TOOL` | `工具名` 或 `工具名:{json}` | 让 mock「模型」发起一次工具调用 |
| `RB_MODEL` | 模型名 | 真 provider 的模型 |
| `NVIDIA_API_KEY` | 密钥 | 也可放 `secrets/nvidia.key`（600 权限，不入库） |
| `RB_MAX_TOKENS` | 整数 | 真 provider 的 max_tokens |
| `RB_ENDPOINT` | URL | 换端点（兼容 OpenAI 形状的服务） |
| `RB_DEBUG_SSE` | 非空 | 把 SSE 原始行打到 stderr |

```
$ RB_MOCK_REPLY='固定回复' RB_LLM=mock ./bin/ravel -e 'agent "c" { }
dup
send say "hi"
drain'
"固定回复"
```

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
| `< 2` | `2 < n` | `5` → `false` |
| `> 2` | `2 > n`（= `n < 2`） | `5` → `true` |
| `- 5 3` | `5 - 3` | `2` |

```
$ RB_LLM=mock ./bin/ravel -e '5
- 1'
-4

$ RB_LLM=mock ./bin/ravel -e '5
< 2'
false

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
- `recover [ 体 ] [ 处理 ]`：出错时把栈**回滚**到进 `try` 之前的深度。
- `retry [ 体 ] n`：体失败就重试，至多 n 次。

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

```
$ ./bin/ravel -e 'write "第一行\n第二行\n" "/tmp/ravel-demo.txt"
lines read "/tmp/ravel-demo.txt"'
@["第一行" "第二行" ""]

$ ./bin/ravel -e 'read "/tmp/ravel-demo.txt"
len'
20

$ ./bin/ravel -e 'read "/nope"'
ravel: 文件不存在或无权限：/nope     # 40
```

### 11.1 快照：注意参数序

`save` 弹的是「先工作区、后路径」，所以**路径要先入栈、工作区在栈顶**：

```
"/tmp/ravel-demo.rbx"
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

## 15. 前端协议（`--serve`）

一行一条 JSON。裸文本行 = `eval` 的简写；显式请求：

```json
{"type":"eval","src":"+ 1 2","id":7}
{"type":"ping"}
{"type":"reset"}
{"type":"quit"}
```

响应：`hello` / `pong` / `result` / `chunk` / `close` / `event` / `bye`。
细节见 `docs/PROTOCOL.md`，前端契约见 `docs/FRONTEND.md`。

`examples/10-serve.sh`（真实输出）：

```
$ ./examples/10-serve.sh
{"protocol":1,"type":"hello","version":"ravel breve 1.0d · janet 1.42.1"}
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
| 60 | 编排 / 能力缺失 | 未注册的工具、`--core-only` 里的 JSON 词 |

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

## 17. 常见坑（十条）

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
| L7 持久化 | `read` `write` `current` `save` `load` `compact` |
| L8 钩子 / 工具 | `@on` `@off` `deftool` `invoke` `resend` `stop` `drain` `next` |
| L9 前端 | `watch` `subscribe` `unsubscribe` |

完整栈效应见 `ravel-breve-spec-v1.0d.md` 附录 A；未冻结项见 `docs/SPEC-FEEDBACK.md`。

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
| `examples/run-all.sh` | 一次跑完上面全部 |

```
$ ./examples/run-all.sh; echo $?     # 0 = 全绿
```
