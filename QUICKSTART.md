# ravel breve 快速上手

**用波兰式书写、跑在栈机上**的 agent 会话编排语言（宿主 Janet，命令 `ravel`，脚本 `.breve`）。

本页只讲「让它跑起来、写出第一个能用的脚本」所要的那点东西，约 10 分钟。
其余的当参考书查：完整手册 `docs/GUIDE.md`，规格 `ravel-breve-spec-v1.0o.md`。

---

## 1. 三十秒

```sh
make                                # 构建 bin/ravel（Janet 已 vendored）
./bin/ravel -e '+ 1 2'              # → 3
./bin/ravel                         # REPL：提示符 ravel> ，quit 或 Ctrl-D 退出
```

三种跑法：

| 用法 | 命令 |
|---|---|
| 一行 | `./bin/ravel -e '<源>'` |
| 脚本 | `./bin/ravel 我的.breve` |
| 服务 | `./bin/ravel --serve`（NDJSON over stdio，给前端用） |

```sh
make test                           # 全部验收（离线 mock）
```

REPL 是**单行**编辑器：一行比终端宽时会折行显示（不会叠印），支持终端括号粘贴，
粘进来的换行会变成一个空格；一行 = 一个语句，所以「多行」请写成多次回车或一个文件。

---

## 2. 只有一条读法：**词在前，最左的实参是第一个操作数**

```sh
./bin/ravel -e 'take 2 "abcde"'     # "ab"   ← 第一个操作数 2，第二个 "abcde"
./bin/ravel -e '- 5 3'              # 2
./bin/ravel -e ', "a" "b"'          # "ab"   ← 拼字符串用 ,（+ 只做数值加法）
```

写反**不是另一种风格**，是栈下溢：

```sh
$ ./bin/ravel -e '3 3 ='
ravel: 栈下溢                       # 退出码 30
```

两条附则：

- **一行 = 一个语句**。`dup swap` 不是两条语句，是 `(swap (dup))`——要两件事就写两行。
- `{ 1 2 3 }` 是**数据**（元组），不参与镜像；`[ … ]` 是**引号**（一段可执行的词序列），
  定义词、`if` 分支、`map` 的参数都用它。

想看清转译结果：加 `--dump`。

```sh
$ ./bin/ravel --dump -e 'take 2 "abcde"'
(do (rb/push "abcde") (rb/push 2) (rb/take))     # ← 转译产物
"ab"                                             # ← 然后照常求值
```

---

## 3. 五张常用卡片

**① 栈动词**

```sh
./bin/ravel -e '* dup 7'            # 49   ← dup 复制栈顶，* 再乘起来
./bin/ravel -e '1
2
swap'                               # 2 1  ← swap 交换栈顶两个（按栈底→栈顶打印）
./bin/ravel -e 'pop 1 2'            # 2    ← pop 丢掉栈顶
```

**② 序列 / 文本**

```sh
./bin/ravel -e 'len { 1 2 3 }'                  # 3
./bin/ravel -e 'map [ * 2 ] { 1 2 3 }'          # (2 4 6)
./bin/ravel -e 'filter [ < 2 ] { 1 2 3 4 }'     # (3 4)
./bin/ravel -e 'split "," "a,b,c"'              # @["a" "b" "c"]
./bin/ravel -e 'take 2 "abcde"'                 # "ab"
./bin/ravel -e 'nth 1 { "x" "y" }'              # "y"   （take/first 对元组返回元组）
./bin/ravel -e 'at "k" H{ "k" 42 }'             # 42
```

`+` 只加数字，`sum` 求和，`fold` 折叠；`show` 打印并**保留**值，`print` 打印并**消费**。

**③ 定义自己的词**

```sh
./bin/ravel -e 'double : [ * 2 ]'           # 定义行不产出值
./bin/ravel 我的.breve                      # 文件里：double : [ * 2 ] 然后 double 21
```

```breve
# 我的.breve
double : [ * 2 ]              # 定义（元层，不参与镜像）
double 21                     # 42
greet : "打招呼" [ , "你好，" ]   # 带文档串：见 greet 可查
greet "世界"                   # "你好，世界"
```

> 定义只在**同一份源**里「后面」可见；`-e 'double : [ * 2 ] double 21'` 不行——
> 一个文件/一份源 = 一轮 = 转译先行。要即定义即用，就分两次调用（或直接写进文件）。

**④ 条件与循环**

```sh
./bin/ravel -e 'if < 3 5 [ "yes" ] [ "no" ]'     # "yes"
./bin/ravel -e 'loop 3 [ log "跑一次" ]'          # 三行「跑一次」
./bin/ravel -e 'try [ fail "炸了" ] [ show ]'     # 抓住错误，show 出错误值
```

条件已经在栈上时，只给 `if` 和两个引号：`true` 换行 `if [ "a" ] [ "b" ]`。
`when` / `unless` / `loop` 同理（词 + 一个引号 = 条件/次数在栈上）。

**⑤ JSON 与文件**

```sh
./bin/ravel -e 'to-json H{ "a" 1 }'              # "{\"a\":1}"
./bin/ravel -e 'at "a" from-json "{\"a\":1}"'    # 1
./bin/ravel -e 'write "hi" "build/tmp/x.txt"'    # 写文件（沙箱内；越界 41）
./bin/ravel -e 'read "build/tmp/x.txt"'          # 读回 "hi"（读不到 → 40）
```

---

## 4. 接上真模型（一行）

配置有四项：provider / 模型 / 上限 / 温度。**预设**把它们压成一行：

```sh
./bin/ravel --presets                                  # 先看有哪些（名字 / provider / model / 目录）
./bin/ravel --preset opencode-go                       # OpenCode Go
./bin/ravel --preset nvidia                            # NVIDIA
RB_PRESET=opencode-go ./bin/ravel                      # 环境变量写法（逗号分隔可叠加）
```

名字打错也会告诉你有哪些：

```sh
./bin/ravel --preset provier -e '1'
# ravel: 预设文件不存在或无权限：presets/provier.json（可用：mock nvidia opencode-go；`ravel --presets` 看全部）
```

> `presets/` 是**相对当前目录**的（不是搜遍全盘）：所以要在任何目录都能用，请走下面的用户配置文件。

存成用户配置，以后**每次启动自动生效**（stderr 通报一行，`--no-config` 可关）：

```sh
mkdir -p ~/.config/ravel && cp presets/opencode-go.json ~/.config/ravel/config.json
./bin/ravel
# ravel: 已装载配置 /home/u/.config/ravel/config.json
```

不想用预设，就手打（与预设同一份白名单）：

```breve
llm-set "opencode" "provider"
llm-set "deepseek-v4.1-flash" "model"
llm-get "provider"                     # 看生效值
llm-models                             # 问一次真·模型列表
```

密钥走环境变量或密钥文件，**永不进配置/预设**：

```sh
export OPENCODE_API_KEY=sk-...                # 或 NVIDIA_API_KEY
# 或者：echo sk-... > secrets/opencode.key && chmod 600 secrets/opencode.key
```

一条命令配好（存密钥 + 存预设 + 可选验证）：

```sh
./tools/oc-setup.sh sk-...            # 密钥 → secrets/opencode.key，预设 → ~/.config/ravel/config.json
./tools/oc-setup.sh --verify sk-...   # 顺手拉一次模型列表
```

处理流程模式（`mode` 词能换的那套）也一样能查：

```sh
./bin/ravel --modes
# cordis     工具：edit glob grep plugin read shell write
#            设定：allow-shell=on
# default    工具：edit glob grep read shell write
#            设定：allow-shell=on
# minimal    工具：shell
#            设定：allow-shell=on
# ptc        工具：edit eval glob grep read shell write
#            设定：allow-shell=on
# standard   工具：edit glob grep read shell write
#            设定：allow-shell=on
```

离线试玩就不用密钥：`RB_LLM=mock ./bin/ravel`。本页后续的例子都假设 mock 或已配好。

---

## 5. 一轮对话

```breve
agent "coder" { }              # 建一个 agent（{ } = 空血缘）
send say "数到三，用空格分隔"    # say → 消息，send → 流（惰性、逐块）
drain                          # 拉完 → 全文
```

```sh
$ RB_LLM=mock ./bin/ravel -e 'agent "coder" { }
send say "hi"
drain
show'
"回声：hi"                       # mock provider 的回显；真模型这里就是回答
```

`session` 看这个 agent 的会话记录：

```sh
$ RB_LLM=mock ./bin/ravel -e 'agent "c" { }
dup
send say "你好"
drain
pop
session
map [ Content ]
show'
"你好"
```

（`map [ Content ]` 只挑出内容；`to-json` 还能看到 `role` / `turn` / `from` 等标记。）
里面**还没有** assistant：一次求值 = 一轮，
默认的收尾钩子要等求值**结束后**才把回复合并进会话。

**同一份源里要继续问**，就得自己把回复合并进去（`utter` 把流变成一条回复，
`append` 追加进 agent）：

```breve
agent "c" { }
dup                        # 留住 agent（下面每次 send 都要用）
send say "一"
utter
append
dup
send say "二"
drain
pop
session
map [ Content ]
show
```

```
$ RB_LLM=mock ./bin/ravel 上面这段.breve
"一"
"回声：一"
"二"
```

（`dup` / `pop` 只是为了让每一步都拿到 agent；写成脚本时也可以分多份源，
让默认收尾钩子替你合并——见 `docs/GUIDE.md` §12.2。）

---

## 6. 钩子与工具（够用的最小片段）

**钩子**：不想 `drain`，想边到边看——用 `@on`。

```breve
@on @Chunk [ show ]            # 每块到达就打印（这里是 mock 的三块："回声" "：h" "i"）
agent "coder" { }
send say "hi"
drain
@off @Chunk                    # 用完关掉（否则每轮都打）
```

**工具**：给模型一个能在你机器上执行的函数。工具体是 **0 元函数**，参数从栈上取：

```breve
deftool "add2" "把参数 a 加 2" [ at "a"
to-int
+ 2 ]
invoke "add2" H{ "a" 40 }      # 42（不经模型，直接调）
```

模型要调工具时，`send … drain` 会自己跑完「模型 → 工具 → 模型」的循环
（详见 `docs/GUIDE.md` §14，例程 `examples/08-tools.breve`）。

---

## 7. 报错时先看这三个数字

| 退出码 | 意思 | 常见原因 |
|---|---|---|
| **30** | 栈下溢 | 操作数写在了词后面（`3 3 =`）|
| **20** | 未知的词 | 拼错，或该词还没定义/没装载（插件里的词下一轮才可见）|
| **31** | 类型/取值错误 | 参数类型不对、坏 JSON、拼错的配置项 |

其余（40 读不到 / 41 写不进 / 60 缺能力 / 33 `fail`）见 `docs/GUIDE.md` §16。

诊断信息一律走 stderr，**stdout 只承载协议**——所以

```sh
./bin/ravel -e 'take 2 "abcde"' > out.txt     # out.txt 里只有 "ab"
```

---

## 8. 下一步读哪一页

| 想干的事 | 去哪儿 |
|---|---|
| 完整教程（栈 / 文本 / 控制流 / JSON，带例程）| `docs/GUIDE.md` §2–§11 |
| agent / 会话 / 广播 / 血缘 | `docs/GUIDE.md` §12 |
| 钩子：收尾、压缩、重试 | `docs/GUIDE.md` §13 |
| 工具、模式（PTC）、用量、取消 | `docs/GUIDE.md` §14 |
| 配置：请求头、模型列表、预设 | `docs/GUIDE.md` §14.9–§14.11 |
| 前端（`--serve` 协议）| `docs/GUIDE.md` §15、`docs/PROTOCOL.md` |
| 写插件 | `skills/ravel-breve-plugin/SKILL.md` |
| 可跑的成套例程 | `examples/`（`./examples/run-all.sh`）|
| 规格条文（REQ / 退出码 / 词表）| `ravel-breve-spec-v1.0o.md` 附录 A、E |
| 词表速查 | `docs/GUIDE.md` §19 |
