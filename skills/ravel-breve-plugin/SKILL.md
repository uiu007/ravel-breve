---
name: ravel-breve-plugin
description: Write, package, load and unload ravel breve plugins (.breve files) that add words, hooks and tools to a workspace. Use when extending a ravel breve session, shipping a bundle of dialect words to other users, or deciding whether something belongs in the core layer or the user layer.
---

# ravel breve 插件

`ravel breve` 是**波兰书写 / 类 Forth 执行**的 agent 会话编排方言（命令 `ravel`，
源文件 `.breve`，宿主 Janet）。插件就是**一个 `.breve` 文件**——没有新语法、
没有新文件格式、没有宿主侧 API。装它是 `plug`，卸它是 `unplug`。

本技能只教**用户层**扩展。**核心层**是不能插件的（见 §1）。

## 0. 三行上手

```sh
# 装（返回插件名 = 文件名去扩展名）
./bin/ravel -e 'plug "skills/ravel-breve-plugin/plugin.breve"'

# 用（词在**下一轮**才可见：同一份源在求值前就转译完了）
printf 'plug "skills/ravel-breve-plugin/plugin.breve"\nsum2 40 2\n' | ./bin/ravel
# → "plugin" / 42

# 卸（返回撤掉的项数：词 + 钩子 + 工具）
printf 'plug "skills/ravel-breve-plugin/plugin.breve"\nunplug "plugin"\n' | ./bin/ravel
# → "plugin" / 3
```

## 1. 分层铁律：核心层 vs 用户层

**这是写插件时唯一必须先想清楚的事。**

| | 核心层（**碰不得**） | 用户层（**插件唯一舞台**） |
|---|---|---|
| 内容 | 词法与字面量、转译（换名表）、栈运行时、流、agent、**钩子机制本身**、工作区与快照/日志、NDJSON 协议、退出码表、**核心词表 `rb/rename`** | 词（定义行）、钩子（`@on` / `@off`）、工具（`deftool`）、模式（`mode` / `mode-of`）、flags |
| 谁实现 | `rb/*.janet`（嵌入二进制） | 方言源码，插件就是它的打包 |
| 插件能改吗 | **不能**：不能加记号、不能加事件名（`@Start … @RoundDone` 是闭集）、不能改核心词含义 | **能**：装/卸都只动这几张表 |
| 失败会怎样 | 编译期/装载期就错，行为不可预期 | 原子回滚，工作区回到装载前 |

一条可验收的性质：**装/卸插件前后，核心词表与转译表逐字节不变**；
唯一变化是工作区里多了几个词、几个引号、几个工具体
（`tests/unit/plugins.janet` 里有一条专门断言它）。

推论：**插件能做的事，用户手打同样的源也能做**。插件的价值只有两条——
**可分发**、**可一键卸载**。如果你想要的改动不在这两列里（比如"加个 `@Turn` 事件"），
那不是插件，是规格修订。

## 2. 用户层 ABI（插件能装的三样东西）

### 2.1 词

```breve
sum2 : "两个数相加（Sum2 -- N）" [ + ]
```

- 定义行：`名字 : [ 体 ]`，可选文档串；**先声明后使用**（同一份源里可以用）。
- 词**全 0 元**：自己从数据栈取元数。**最左实参 = 第一个操作数 = 栈顶 = 先被消费**。
- **一行一条语句**：块里的换行就是语句边界。`[ at "a" + 1 ]` 写在**一行**里会被当成
  「`at` 带三个操作数」，不是三条语句——这是最常见的错。

### 2.2 钩子

```breve
@on @Close [ flag-set true "saw-close" ]   # 事件 + 引号
@off @Fail                                  # 不给引号 = 清空该事件全部钩子
```

- 事件名是**闭集**：`@Start` `@Chunk` `@Fail` `@Error` `@Close` `@Toolcall` `@Done` `@RoundDone`。
  写别的名字 → 31（`REQ-17`）。**插件不能新增事件**。
- 钩子跑完栈会被截回原深度（观察者语义，不能偷偷改变量空间）。
- 载荷压栈规则与其他词一致：**第一个操作数最后压**（在栈顶）。
  例：`@Chunk` 载荷写作 `Chunk Stream`，栈顶是 Chunk。
- ⚠️ 插件可以 `@off` 掉默认钩子，但**卸载不会把它装回来**（`@off` 是用户的显式动作）。
  想恢复：`mode "default"`。

### 2.3 工具

```breve
deftool "sum" "把两个整数相加" [ dup
at "a"
swap
at "b"
+ ]
```

- 工具体是 **0 元函数**；**参数表由宿主先压栈**，所以第一步总是 `at "参数名"`。
- 要取**两个**字段就 `dup` 保住参数表（`at` 会把表消费掉）。
- 返回值留在栈上（模型看到的就是它）。
- 工具失败 → 退出码 60（编排级），不是 20/31。

### 2.4 模式（可选，通常是"插件 × 环境"的用法）

```breve
mode "ptc"        # 装预制模式；会替换钩子表、注入系统提示、裁剪工具白名单
mode-of           # 导出当前模式（与 mode 互逆）
```

⚠️ `mode` 会**整表替换钩子**，插件挂的钩子会被一并丢掉（`unplug` 因此少算一项）。
插件里不要顺手切模式；要让用户自己切。

## 3. 完整样板（本技能自带，可直接跑）

`skills/ravel-breve-plugin/plugin.breve`：

```breve
# ① 词：两数相加
sum2 : "两个数相加（Sum2 -- N）" [ + ]

# ② 钩子：任何流关闭时，在 flags 里留个记号（`flag "saw-close"` 可读）
@on @Close [ flag-set true "saw-close" ]

# ③ 工具：给模型用
deftool "sum" "把两个整数相加" [ dup
at "a"
swap
at "b"
+ ]
```

`./examples/16-plugins.sh` 是它的可跑例程，输出：

```
ravel> "plugin"     # plug 返回插件名
ravel> ("plugin")   # plugins 台账
ravel> 42           # sum2 40 2（插件里的词）
ravel> 42           # invoke "sum" H{ "a" 40 "b" 2 }（插件里的工具）
ravel> 3            # unplug "plugin"（撤了 3 项）
ravel> ()           # 台账空了
```

钩子侧验一下（`@Close` 在流关闭时响，`drain` 会把流关掉）：

```sh
printf 'plug "skills/ravel-breve-plugin/plugin.breve"\nagent "a" { }\nsend say "hi"\ndrain\nflag "saw-close"\n' \
  | RB_LLM=mock ./bin/ravel
# → … true        （插件里的钩子确实装上了，卸载后不再有）
```

## 4. 装 / 卸的语义（必须知道，否则会写出"半装"插件）

| 语义 | 说明 |
|---|---|
| **零元词** | `plug` = `Path -- String`，`plugins` = `-- Seq`，`unplug` = `Name -- Int` |
| **不算一轮** | 装载与 PTC 的 `eval` 同级：不触发 `@RoundDone`、不往本轮列表塞东西、不写日志/快照 |
| **不外溢** | 插件里残留的操作数不会跑到调用者栈上（装载前后栈深不变） |
| **原子** | 插件里任何一步失败 → 已装的部分**全部撤销**，原错误码透出 |
| **精确卸载** | 只撤这个插件装的；它**重定义**过的词/工具，卸载时**还原旧词条** |
| **同名重装** | 先卸旧账再装，不会留孤儿注册 |
| **无传递依赖** | 插件里再 `plug` → 31；要一次装多个用 `RB_PLUGINS=a.breve,b.breve`（按序） |
| **不能碰能力** | 能力表只有宿主可写；插件不新增能力（它读自己的文件都用 `:fs/read`） |

退出码：

| 情况 | 码 |
|---|---|
| 路径不存在/不可读（含沙箱外） | 40 |
| `plug` / `unplug` 参数不是字符串 | 31 |
| `unplug` 一个没装过的名字 | 20 |
| 插件内部失败 | 原码（如 `fail` → 33） |
| 缺 `:fs/read`（`--core-only`） | 60 |

**沙箱**：文件能力默认只能读**当前目录**内的路径（`RB_SANDBOX`）。
把插件放在仓库外又不设 `RB_SANDBOX=none|/some/dir`，`plug` 会得到 40——
这不是插件坏了，是沙箱在拦。

## 5. 分发

插件就是文件，所以分发方式很土但很硬：

```sh
# ① 放到任何可读路径，让用户 plug
./bin/ravel -e 'plug "/abs/path/my.breve"'

# ② 或者让用户每次启动就装上（新工作区建好后按序装载）
RB_PLUGINS=plugins/audit.breve,plugins/toolkit.breve ./bin/ravel
```

推荐布局（本仓库的约定）：

```
plugins/<name>.breve              # 面向用户的功能包
skills/<skill>/SKILL.md           # 怎么写这类插件的说明
skills/<skill>/plugin.breve       # 与说明配套的可跑样板
```

`skills/` **不进**嵌入式 bundle（不增大二进制），它是文档 + 样板；
`rb/MANIFEST` 也不含它。

## 6. 自检清单（提交插件前逐条过）

- [ ] 只装用户层的东西（词 / 钩子 / 工具），没有试图新增事件或记号。
- [ ] **一行一条语句**；块里的换行没有被压平。
- [ ] 每个词都写成**前缀**：`+ 1` 而不是 `1 +`；没有中缀。
- [ ] 只有一元的字面量语句时，字面量在**最左**（`"!"`、`42`）。
- [ ] 字符串拼接用 `,`（`join2`），不是 `+`（`+` 只做数值加法）。
- [ ] 工具体第一步是 `at "参数"`；取多字段先 `dup`。
- [ ] 插件里再没有 `plug`（没有传递依赖）。
- [ ] `plug` 之后**用另一轮**验证词真的可用（同一份源用不到）。
- [ ] `unplug` 之后：词报 20、钩子数回到装前、工具消失、台账变空。
- [ ] 故意在插件末尾加 `fail "炸"` 试一次：确认没有留下半装状态。
- [ ] 用 `./bin/ravel --dump -e '<一行>'` 看过转译产物，确认操作数顺序是你要的。

## 7. 常见错误（都实测过）

| 现象 | 原因 | 修法 |
|---|---|---|
| `未知的词：sum2` | 同一份源里 `plug` 后立刻用 | 分两轮（REPL 换行 / 两次 `-e` / PTC `eval` 子源） |
| 栈下溢 | 词写成中缀（`3 double`） | 前缀：`double 3`，即**词在前**，字面量在后 |
| `could not find method :+ for "bob"` | 用 `+` 拼字符串 | 用 `,`（`join2`） |
| 工具里栈下溢 | 一行里塞了多条语句 | 每行一条；或先 `dup` 保住参数表再取第二个字段 |
| `未知的事件名：@Turn` | 事件名是闭集 | 只能用在册的 8 个事件；新事件要改规格 |
| `plug` 报 40 | 路径在沙箱根之外 | 把文件放进来，或 `RB_SANDBOX=none` |
| `plug` 报 60 | `--core-only` 构建（没有 `:fs/read`） | 用完整构建；这是 REQ-37 的边界，不是 bug |
