# 决策记录（D-xx）

规格未冻结、或规格留白处的**实现决策**。每条都写明：内容 / 理由 / 何时需要裁决。
凡标「待裁决」者，在最近的人工检查点（CHK）由用户确认后转为「已冻结」。

> **v1.0c 追记**：用户指示「自行修改 spec」后，已新建 `ravel-breve-spec-v1.0c.md`。
> 下列决策已**写进规格**，从「实现自定」升格为「规格要求」：
> **D-02 → REQ-39**、**D-03 → REQ-40**、**D-04 → §4.9.1 推论**、**D-05 → REQ-41 + 附录 E**、
> **D-06 → REQ-30/42/45/46**、**D-12 → REQ-44**（`H{}` 语义冻结）、**D-15 → REQ-43**（stdout 只承载协议）。
> 下列仍为纯实现细节：D-07（注册表形态）、D-09/D-10（Janet 陷阱留档）、D-11（测试装载）、D-13、D-14、D-16。

---

## D-01 宿主 vendor 策略（已冻结，CHK-0 复核）

- **内容**：`janet 1.42.1` amalgamated build 直接 vendor 进仓库：`vendor/janet/{janet.c,janet.h,shell.c}`；
  来源 commit `e1963cdfe0148f83601907727e00bd672d798115`（tag `v1.42.1`），sha256 记在 `vendor/janet/VERSION`。
- **理由**：REQ-38 要求钉版本 + amalgam 静态嵌入；vendor 使构建可复现、离线可用。
- **复核**：`make check-vendor`。

## D-02 注释语法（**已升格为 REQ-39**）

- **内容**：`#` 起，至行末。块内同样适用。
- **理由**：宿主同源，最小惊讶；`;` 留给将来（避免与 Forth 观感混淆）。
- **裁决**：已由规格 v1.0c REQ-39 冻结。

## D-03 块内换行的语义（**已升格为 REQ-40**）

- **内容**：块内换行 = **语句分隔**；每条语句**各自独立反转**；语句之间**保持书写序**。
  转译产物把块体展平为一个 `do`（语义等价于逐语句嵌套 `do`）。
- **理由**：保留 REQ-04「一行 = 一条指令流」与 REQ-03「块内递归反转」两条同时成立；
  若整块当作一条语句反转，则多行块的书写序会整体倒置，与 REQ-04 冲突。
- **证据**：`[ 1 pop` / `* 2 ]` → `(do (rb/pop) (rb/push 1) (rb/push 2) (rb/mul))`。
- **裁决**：已由规格 v1.0c REQ-40 冻结。

## D-04 比较运算的实参次序（**已由 §4.9.1 推论导出**）

- **内容**：与算术一致——**书写序最左的实参 = 栈顶 = 先消费**。故 `< 5 3` → `false`
  （第一个操作数 5 不满足「小于」第二个操作数 3）。
- **理由**：REQ-01 的「波兰式 + 类 Forth」表述下，这不是选择，而是**唯一结论**（最左实参 = 第一个操作数）；无需为比较另设规则。
- **裁决**：已由规格 v1.0c §4.9.1 冻结。

## D-05 退出码具体取值（**已升格为 REQ-41 + 附录 E**）

| 码 | 含义 | 码 | 含义 |
|---|---|---|---|
| 0 | 成功 | 30 | 栈下溢 |
| 1 | 一般失败 | 31 | 类型错误 |
| 2 | 用法错误 | 32 | 元数错误 |
| 10 | 字符串未闭合 | 33 | `fail` |
| 11 | 块未闭合 | 40 | 读失败 |
| 12 | 非法转义 | 41 | 写失败 |
| 20 | 未知的词 | 50 | 内部错误 |
| 21 | 多余的 `]` | 51 | 宿主内部错误 |
| 22 | 定义行不合法 | 60 | 编排预留 |
| 23 | 宿主编译失败 | 70+ | 保留 |

- **理由**：区间由 REQ-23 固定，区间内的具体值是实现细节；给满便于前端分支。
- **裁决**：已由规格 v1.0c REQ-41 + 附录 E 冻结。

## D-06 工作区 = 字典 + 栈（**已升格为 REQ-30 / REQ-42 / REQ-45 / REQ-46**）

- **内容**：**工作区 = 字典绑定（函数与常量）+ 栈（变量）**，二者**都是持久状态**，可多工作区。
  - **字典**：`名字 : [ 体 ]` 定义的函数 + 常量绑定。
  - **栈**：变量——工作区的活值（含 `Agent`）；因此“标签 → agent”的解析是**栈上搜索**（可预先绑定优化）。
  - **并发在流层**（`Stream` ≡ fiber），不在求值层；一轮产出 `list Stream`，钩子逐元素处理。
  - `--serve` 与 REPL 都**复用同一个 env** → 字典与栈都跨行/跨请求保留；清栈是前端的事。
- **理由**：用户两次澄清：“不需要过分分离”；“工作区就是字典绑定（函数与常量）+ 栈（变量）”。
  因此栈**不是**“用完即弃的临时空间”，而是工作区的变量空间。
- **当前实现的简化**：`rb/dict` 仍是**模块级全局**（= 单一隐式工作区）；
  多工作区落地（M4 / REQ-20）时字典需移入工作区对象。
- **证据**：`e2e/cli.sh`：`1`/`2` 两行的栈累积为 `["1","2"]`；`f : [ * 2 ]` 后 `f 21` 可用。
- **实现**：`rb/cli-serve-loop` 建一次 env 后复用；`rb/new-env` 的栈即工作区变量空间。

## D-07 能力层边界（REQ-37 / §4.11）

- **内容**：`rb/MANIFEST` 中以 `cap/` 开头的行属于**可剔除能力层**；`make core-only` 会生成去掉这些行的 bundle。
  核心通过**显式注册表** `rb/cap` 取用能力（`rb/cap-put` / `rb/cap-get` / `rb/cap?`），
  不使用字面符号引用 `cap/*`（否则核心在编译期就静态依赖 cap/）。
- **理由**：REQ-37 要求核心不含 net/file/http/crypto，且剔除后仍可装载。
- **验收**：`make test-core-only`（剔除 cap/ 后：主脊、定义行、引号/apply、dump 全部仍可用；
  `--serve` 缺 cap/json 时给出可读错误并退出 50）。

## D-08 JSON 归属（待 CHK-6）

- **内容**：核心**不含** JSON 解析/生成；`cap/json.janet` 提供 `cap/json/encode`（M0 为占位编码器：
  字符串/数字/布尔/nil/数组/表，**键按字符串序排序**以保证协议输出确定）。解码留待 M6。
- **理由**：附录 D 验收项；REQ-37 要求能力外置。
- **裁决**：CHK-6（真实 provider 归属）。

## D-09 行读入与 EOF（实现陷阱留档）

- **内容**：Janet `getline` 在 **EOF 返回空 buffer**（不是 `nil`），且返回值含尾部换行。
  REPL / `--serve` 一律以「空输入 = EOF」结束循环，并 `string/trimr` 去掉尾换行。
- **理由**：M0 曾因 `while` 等到 `nil` 而**空转**（`--serve` 挂起）。
- **回归**：`e2e/cli.sh` 的 REPL / `--serve` 管道用例（EOF 必须退出）。

## D-10 环境条目的形态（实现陷阱留档）

- **内容**：Janet 1.42 的环境条目是**绑定表**：`janet_def` 存 `@{:value v}`，`janet_var` 存 `@{:ref @[v]}`。
  故 `(get (curenv) 'name)` 返回的是**表**而非值。核心统一用 `rb/env-get` 解包。
- **理由**：动态查词（`doc`/`see`、能力层查拔、装载期自检）都需要正确的解包语义。

## D-11 测试装载方式（实现约束）

- **内容**：测试文件按 **form 逐个 eval** 进同一环境（`tests/run.janet` → `tests/runner.janet`），
  与宿主 `janet_dobytes` 语义一致。
- **理由**：`dofile` 每文件开新环境；`eval-string` 一次编译全部 form，跨 form/跨文件前向引用会失败。
  内核本身是「逐 form 编译执行」的。
- **推论**：`tests/run.janet` 在装载 bundle **之前**不能出现任何 `rb/*` 符号（编译期解析）。

## D-12 集合字面量（**M2 落地；语义已升格为 REQ-44**）

- **内容**：M0 只实现引号块 `[ … ]`（= 延迟代码，REQ-32）。
  `{ … }`（序列）/ `H{ … }`（映射）**延后到 M2**，与 REQ-06/REQ-09 的类型落地一起做。
- **理由**：先打通主脊。语义已由规格 v1.0c REQ-44 冻结：**字面量是数据、不参与镜像、内部只允许字面量、重复键后者覆盖并告警**。
- **影响**：M0 中 `sum [ 1 2 3 ]` 之类会得到「引号对象」而非列表，属预期。

## D-13 文档与提交语言

- **内容**：文档、注释、提交信息用中文；标识符与词名用 ASCII 英文。

## D-14 词元数约定（§4.9.3）

- **内容**：**所有方言词都是 0 元**（自己 pop 所需元数、push 结果）；`rb/push` 是唯一的 1 元原语。
- **理由**：REQ-31 要求「每个方言词编译为一次栈操作调用」，元数由词自己负责才可能与宿主调用约定解耦。

## D-15 `--dump` 与 `--serve` 的组合（**已升格为 REQ-43 的约定**）

- **内容**：`--serve --dump` 时，转译产物写 **stderr**（`dump: …`），stdout 只保留 NDJSON。
- **理由**：stdout 是协议通道，不能被日志污染。

## D-16 仓库边界

- **内容**：`RavelBreve/` 内独立 `git init`，不触碰父目录 `/home/uiu` 的 git（含坏 submodule）。
  `build/`、`bin/ravel` 不入库（`.gitignore`）。
- **理由**：避免污染父仓库；产物可由 `make` 复现。

## D-17 L1 序列词的形态多态（M2）

- **内容**：一张表定死多态规则（`rb/seq-kind` / `rb/seq-elems` / `rb/seq-build`）：
  `String` → 元素是单字符字符串、结果仍是 `String`；`tuple` → `tuple`；`array` → `array`；
  其他 → 运行时类型错误（31）。
- **理由**：REQ-10 要求 `Session`（= `Utter` 的 array）直接复用 L1 词且返回**新值**，不得就地改写。
- **实现陷阱**：Janet 的 `slice` **总返回 tuple**（对 array 也如此）→ 一律经 `rb/seq-build` 重建形态。
- **实现陷阱**：`string/split " " "a  b"` 保留空段 → `words` 需过滤空串。
- **验收**：`U:words-l1`（四象限 × 三形态）、`C:req-11`、`C:req-10`。

## D-18 组合子引号 = 未写满的波兰表达式（M2，**需规格裁决 SF-12**）

- **内容**：组合子的引号是一个**少写了一个操作数的波兰表达式**；组合子把隐藏实参补在
  **最右**（书写序最后）。补完仍是波兰式，**不引入任何中缀读法**：
  | 写法 | 引号被补成 | 结果 |
  |---|---|---|
  | `filter [ < 2 ] { 1 2 3 4 }` | `< 2 元素` | `(3 4)` |
  | `map [ - 10 ] { 1 2 3 }` | `- 10 元素` | `(9 8 7)` |
  | `fold [ - ] 0 { 1 2 3 4 }` | `- 累加值 元素` | `-10` |
  | `keep [ * 2 ] 5` | `* 2 栈顶值`（引号自带 1 个操作数） | 栈 `[5 10]` |
- **直接推论**：**栈上已有的值只能落在最右操作数位置**（它比引号内字面量先入栈）。
  要让它当第一个操作数，必须先 `swap`。这是「前缀书写 + 栈机执行」的必然结果，不是实现选择。
- **计数循环也只写波兰式**：`depth` 把当前深度压栈，故
  `1 2 3` 后接 `while [ < 1 depth ] [ + ]` 即「`< 1 depth`」（1 小于 depth 时继续），
  结果栈 `[6 1]`。**不需要也不应该用 `swap`/`dup` 堆栈杂耍。**
- **理由**：规格只说「引号作用在同一数据栈上」，未说隐藏实参的位置，故记 SF-12 请求补例。

## D-19 `try` vs `recover`（M2，**需 CHK 裁决**）

- **内容**：`try [体] [处理]` —— 失败时把错误值压栈后跑处理引号，**保留**体引号已产生的栈效果；
  `recover [体] [处理]` —— 失败时先把栈**回滚**到 try 前深度，再压错误值跑处理引号。
- **理由**：REQ-17 的 `@Fail`/`@Error` 需要「保留部分结果」与「干净重来」两种策略。
- **实现陷阱**：`protect` 是**宏**，`(protect (body-q))` 才能捕获；`(protect (fiber/new …))` 只求值一次。
  实测 `protect` **不隔离环境**（同一工作区，栈效果可见）。
- **注意**：`7 fail "boom"` 里 `7` **不会**入栈（镜像后 `fail` 先执行）；要保留部分结果须**分语句**写
  `try [ 7\nfail "boom" ] [ to-string ]`。
- **验收**：`U:words-l5`。

## D-20 `split` 的元数（M2，**需规格裁决 SF-11**）

- **内容**：实现为 **2 元** `split SEP String -- seq`（附录 A 的 1 元记法 `String -- seq` 无法表达显式分隔符）。
- **理由**：`words`/`lines` 已覆盖「按空白/换行」的 1 元场景；显式分隔符必须带参数。
- **验收**：`U:words-l1`。

## D-21 `retry` 的次序与语义（M2）

- **内容**：`retry [q] n -- …`；成功则保留 `q` 的栈效果；失败则回滚到调用前深度并重试，最多 `n` 次；
  仍失败则抛出最后一次错误。`q` 非函数或 `n` 非数字 → 运行时类型错误（31）。
- **实现陷阱**：镜像后**引号在栈顶**，必须先弹 `q` 再弹 `n`（曾因次序反了导致**死循环**）。
- **验收**：`U:words-l5`。

## D-22 `Utter` / `Session` 的表示（M2）

- **内容**：`Utter` = `@{:role String :content String}`；`Session` = `Utter` 的 **array**。
  于是 REQ-10 的「Session 复用 L1 词」**自动**满足（D-17 的 array 分支）。
  `Role`/`Content` 是访问器；`say` 缺省 `role = "user"`（REQ-29）。
- **理由**：不引入额外包装类型，保持「复杂度可见」；宿主 table/array 可直接互操作（Json 亦然）。
- **验收**：`U:words-l2`、`C:req-06-07-types`。

## D-23 `swap` 的镜像次序修正（M2，**实现缺陷留档**）

- **现象**：M0 的 `rb/swap` 先 `(array/push s b)` 再 `(array/push s a)`，结果与操作前**完全相同**（空操作）；
  M0 的测试期望值恰好按错误行为写，故一直是绿的。
- **修正**：按「左 = 栈顶」推导——操作前 `[Y X]`（X 在顶），操作后应为 `[X Y]`（Y 在顶），
  故须**先压 a（X）再压 b（Y）**。
- **教训**：栈原语的测试必须由「栈效应记法」**独立推导**期望值，不能从实现输出反推。
- **验收**：`C:req-09`（`swap 1 2` → `[1 2]`）。

## D-24 `rb/at` 对 String 返回单字符（M2）

- **内容**：`at n "abc"` → `"b"`（单字符字符串），不是宿主字节码 `98`。
- **理由**：D-17 的多态表要求 String 的元素是单字符字符串（与 `map`/`filter`/`take` 一致）。
- **验收**：`U:words-l1`。

## D-25 钩子不改变量空间（M3）

- **内容**：`rb/emit` 在**每个钩子前后**把栈截断回调用前的深度 `d0`；载荷按「第一个操作数在栈顶」压入
  （`(reverse payload)` 逐个 push）。
- **理由**：钩子是**自动行为**（复杂度可见要求它不能悄悄改工作区）；REQ-17 的载荷契约又要保留。
  于是「钩子能读到载荷、但读不到也写不坏宿主语句的栈」。
- **实现陷阱**：迭代钩子前必须 `array/slice` 拷贝——钩子可能就地改数组。
- **验收**：`U:events`（载荷序 + 栈截断）。

## D-26 消息在前、目标在后：`send Utter Agent -- Stream`（M3）

- **内容**：`append Utter Agent -- Agent`、`send Utter Agent -- Stream`、`resend Utter Agent -- Stream`、
  `bcast Utter Domain -- list Stream`。
- **理由**：D-18 的推论——**栈上已有的值只能落在最右操作数位置**。agent 是栈上的变量（REQ-30），
  所以「目标」必须是最右实参，`send say "hi"` 才能直接吃栈上的 agent；语序上也自然（「把消息发给 agent」）。
- **影响**：附录 A 的词形表仍是旧次序（`send Agent Utter`），已记入 SF-14 请规格侧修订。
- **验收**：`C:req-12-13-agent`、`C:req-15-bcast`、`C:req-45-46-round`。

## D-27 流 / provider 失败 → 退出码 60（M3）

- **内容**：编排层失败统一落 `60`（附录 E 预留段）。触发点：`Stream` 进入 `:failed` 后
  `drain`/`utter` 抛错；`cap/llm-chat` 取不到 provider、返回非函数、provider 内部报错。
- **理由**：这类失败不是「方言用错」（30/31/33），也不是「文件/用法」（2/40），是**外部依赖失败**；
  单列一段让脚本能区分「我的程序写错了」与「模型那头炸了」。
- **实现陷阱**：`drain` 原先只返回已取到的部分文本、**静默吞掉失败** → 改为抛错（坏密钥的端到端验证靠它）。
- **验收**：`U:stream`（失败流）、`tests/e2e/agent.sh`（坏密钥 → 60）。

## D-28 HTTP 走 FIFO，不用 `os/spawn` 的 pipe（M3）

- **现象**：`os/spawn` 建出的 pipe 在 `JANET_EV` 下两端都是 `O_NONBLOCK` → `file/read` 立刻假 EOF，
  流式解析拿不到任何块（`drain` 返回 `""` 且不报错）。
- **方案**：`mkfifo` + `bash -c 'exec > FIFO 2> ERRFILE; curl …'` + `file/read :line` 阻塞读；
  读尽后 `os/proc-close`（**自带 wait**，不能再 `os/proc-wait`）取退出码、读 ERRFILE 诊断、`rm -f`。
- **代价**：依赖 `mkfifo`/`bash`/`curl`（只在能力层 `cap/http.janet`，核心不含，REQ-37 不受影响）。
- **验收**：`tests/e2e/agent.sh`（真流式逐块）。

## D-29 默认 `@RoundDone` 经 `var` 间接层挂上（M3）

- **原因**：`rb/ws-new`（`rb/events.janet`，装载序在前）就要预挂默认钩子，而默认钩子的实现在
  `rb/round.janet`（装载序在后）→ 前向引用。
- **方案**：`rb/ws-new` 注册 `(fn [] (when rb/default-round-done (rb/default-round-done)))`；
  `rb/round.janet` 末尾 `(set rb/default-round-done …)`。
- **验收**：`U:events`（默认钩子存在）、`C:req-45-46-round`。

## D-30 `rb/round-finish` 在 env fiber 里 emit（M3）

- **内容**：`(fiber/new (fn [] (rb/emit "@RoundDone" [ss])) :e env)`，使钩子里的
  `(dyn :rb-ws)` / `(dyn :rb-stack)` 命中**工作区**；fiber 出错转 60。
- **理由**：收尾钩子是方言词写的代码，必须和普通语句共享同一个工作区（REQ-42）。
- **配套**：一轮**失败/中断**时走 `rb/round-abort`——**不**触发 `@RoundDone`（REQ-18 排除中断），
  只清空本轮列表，避免残留 stream 混进下一轮。
- **验收**：`C:req-45-46-round`（收尾后本轮清空）。

## D-31 mock provider 按 UTF-8 字符切块（M3）

- **现象**：按字节 `string/slice` 切 "回声：hi" 会切坏多字节字符。
- **方案**：`cap/chars` 用 lead-byte 宽度求字符边界，至多 4 块；回复取自 `RB_MOCK_REPLY`。
- **验收**：`C:req-08-stream`（四块 ab/cd/ef/gh）。

## D-32 渲染保留 UTF-8（M3）

- **现象**：`%q` 把中文印成 `"\xE9\x97\xAE"`，对中文用户不可读。
- **方案**：`rb/render` 手写递归渲染：字符串只转义 `\\` `"` 与不可打印 ASCII，**高位字节原样输出**；
  容器逐个递归（形态与 Janet 字面量一致，仍可回读）；其余标量交给 `%q`。
- **边界**：容器的键须可排序（方言里的表都是关键字键）；`--serve` 的机器可读输出仍走 `cap/json`。
- **验收**：`tests/e2e/cli.sh`（渲染：保留 UTF-8）。

## D-33 持久化格式冻结（M4）

- **内容**：`<path>` 单文件 JSON 快照 + `<path>.log` JSONL 增量日志。
  - 快照：`{"kind":"ravel-workspace","version":1,"dict":{名:{"doc","src"}},"stack":[…],"agents":[{label,live,turn,origin,session}]}`
  - 日志每行：`{"v":1,"n":<序号>,"defs":[{name,src,doc}],"stack":[…]}`（只写**本轮变化**的 defs）。
  - 载入顺序：校验 `kind`/`version` → 重建 agent 注册表 → 清空字典按源重定义 → 恢复栈 → 重放日志。
  - 末行半截 / 坏行：**容忍**，告警后忽略（崩溃恢复），不让载入失败。
- **理由**：REQ-20 只给「版本化单文件 + JSONL」，字段留白（SF-17）；此处冻结以便前端与用户脚本可依赖。
- **验收**：`unit/store.janet`、`conformance/req-20-workspace.janet`。

## D-34 词条存 ravel 源，不存宿主序（M4）

- **内容**：字典词条四段 `:body`（thunk）/ `:doc` / `:src`（ravel 源）/ `:code`（宿主序）。
  快照只写 `:src`；载入时重新转译。
- **理由**：存宿主机序会把实现细节焊进文件格式（违反「复杂度可见」）；存源则同一快照跨实现可读。
- **代价**：载入比直接反序列化慢一点（一次性转译），且载入时的转译要能报错（坏源 → 23）。

## D-35 `save`/`compact` 只接受当前工作区（M4）

- **内容**：实参须是 `current` 给出的那个句柄（与 `(env :rb-ws)` 同一张表），否则 31。
- **理由**：方言里只有一个工作区（REQ-30），「保存别人的工作区」没有语义；早失败胜过静默无操作。
- **验收**：`C:req-20-workspace`（`save H{ } …` → 31）。

## D-36 值编码按需加 `"$"` 标签（M4）

- **内容**：`nil`/布尔/数字/字符串原样；其余加标签 `tuple`/`array`/`utter`/`table`/`keyword`/`symbol`/
  `agent-ref`/`stream`/`workspace`/`opaque`。Stream **不持久化**（栈编码时丢弃）；Agent 存 label，载入时按
  `agents` 表解析回同一个实例。
- **环形防护**：工作区表特判成 `{"$":"workspace"}`（`:env` ↔ `:rb-ws` 是环）；其余表超过 12 层退化为
  `{"$":"opaque","type":"deep"}`。
- **踩坑**：`load` 会把工作区压栈（`Path -- Workspace`），若照普通表编码就会经由 `:env` → `:rb-stack`
  **无限递归挂死**（表现为 `save`/`load` 之后整轮不返回）。

## D-37 小工作区会每轮 compact（REQ-21 主判据的后果）

- **现象**：判据 ① 是「日志 > 快照的 0.5 倍」。十来个词的小工作区快照只有 ~150 字节，一行日志 ~110 字节，
  于是**几乎每轮都触发** compact：日志被立即清空，`seq` 归零。
- **处置**：按规格字面实现（不擅自加下限），写入本文档，并在 `docs/SPEC-FEEDBACK.md` 提 SF-18
  （建议加「日志 ≥ 512 字节」之类的下限）。
- **测试影响**：测「增量日志」的用例先把快照撑大（`pad!`），否则观察不到多行日志。

## D-38 载入进来的词要下一轮才解析得到（M4）

- **原因**：转译在**执行之前**完成（REQ-31/REQ-33），`load` 是执行期动作。同一段源码里 `load` 之后的
  语句在转译时字典还是旧的，故 `load …` 后同轮调用新词报 20。
- **处置**：文档写清「载入后先 `pop`，下一轮再用新词」；不改转译模型（那会引入隐藏的两阶段求值）。
- **同理**：`load` 的结果是工作区句柄，会留在栈上——REQ-20 的 `Path -- Workspace` 就是如此，用户 `pop` 掉即可；
  `rb/render` 因此把工作区渲染成 `#<workspace>` 占位（否则打印栈会把 `:env` 的环无限展开）。

## D-39 NDJSON 协议 v1 冻结（M5 / CHK-5）

- **请求集**：裸文本（= 不带 `id` 的 `eval`）、`eval`、`ping`、`hello`、`reset`、`quit`；
  响应集：`result`、`chunk`、`close`、`pong`、`hello`、`bye`。
- **一行一消息**：一个请求恰有一条**终结**响应；求值过程中可先冒出任意多条 `chunk`/`close`。
- **JSON 请求判定**：行首 `{` 之后（跳过空白）紧跟 `"` 才算 JSON；因此 `{ 1 2 }` 仍是字面量表达式
  （否则方言的元组字面量在 `--serve` 里无法书写）。
- **`id` 原样回显**：请求带 `id` 就回显，用于前端配对；没有就不带该字段。
- **错误不终止**：坏 JSON / 未知 `type` / 缺 `src` → `result{ok:false,code:2}`，循环继续（REQ-42）。
- **chunk 序号**：`n` 从 0 起、按流独立连续（前端排序/去重）；`close.ok=false` 表示该流失败。
- **`reset`**：换一个全新工作区（字典 + 栈 + agent + 视图流），因此也是前端 `clear` 的落点。
- **验收**：`C:req-24-duplex`、`tests/e2e/cli.sh`（协议段）、`docs/PROTOCOL.md`。

## D-40 方言输出与协议输出分流（M5）

- **问题**：`show`/`print` 默认写 stdout，会污染 `--serve` 的协议流（REQ-43「stdout 只承载协议」）。
- **做法**：`rb/runtime.janet` 加 `rb/out-sink`；`rb/new-env` 把它注入 env 的 `:out`，
  于是求值 fiber 里的 `print`/`show` 写进捕获 buffer；每轮结束由 `rb/cli-out-flush!` 转到 **stderr**。
- **坑**：协议 sink 自己也用 `print`，会被同一 capture 截获（chunk 消息“消失”）→ sink 改为显式
  `file/write stdout` + `file/flush`。

## D-41 元命令保留名表：`quit` / `exit` / `help` / `clear`（M5）

- **约束**：REQ-09 一个名字只有一种词性 → 保留名**不得**是方言词。
  故 `watch`（L9）、`save` / `load` / `current` / `compact`（L7）**不进**表；
  M2 曾把 `watch`/`save`/`load`/`agents` 列为元命令，M5 修正（`agents` 还是 §5 的禁用词）。
- **分发位置**：只在 **REPL**（`rb/cli-meta`）。协议侧裸行一律当源码——按 REQ-25，元命令属于
  **前端**的命令表；前端把 `clear` 翻成 `{"type":"reset"}`。
- **`clear` 语义**：清空变量空间（数据栈），保留字典与钩子（字典是工作区的一部分，REQ-20）。
- **验收**：`C:req-25-meta-commands`、`e2e/cli.sh`（`help`/`clear`/`quit`）。

## D-42 `watch` = 只读视图流（M5 / REQ-28）

- **形态**：`watch Agent -- Stream`，先补历史会话条目，再随 `append` 吐新增；一条目一块。
- **不进本轮列表**：视图流的 `:agent` 为 nil 且 `:watch true`，**不**进 `ws :round`。
  否则默认收尾钩子会把它当本轮产物 `append` 回会话——会话会自我膨胀（实测过）。
- **取尽不 close**：`rb/stream-next!` 对视图流「暂时没有新条目」返回 nil 但保持 `:open`；
  发 `close` 会让前端误判这一轮结束（REQ-08 的 close 只属于真流）。
- **推送**：`rb/watch-tick!` 在每次请求处理完后推进所有视图流，每次至多 **64 块**
  （宁可下轮再推，也不让输入饿死 → REQ-24 双向不阻塞）。视图流不随快照持久化（是活的观察者）。
- **验收**：`C:req-28-show-watch`、`C:req-24-duplex`、`e2e/cli.sh`（watch 推送段）。

## D-43 REQ-22「输出 JSON」= 显式 `--json` 开关（M5）

- **歧义**：REQ-22 说 CLI「输出 JSON」，但没说何时。默认把所有输出都做成 JSON 会让人类使用时难读。
- **选择**：缺省人类可读（逐元素打印剩余栈）；`--json` 时输出一条协议 `result` 消息。
- **失败仍给分级码**：`--json` 不吞退出码（`ravel --json -e 'nope'` → 退出码 20，stdout 是失败消息）。
- **记入反馈**：SF-21。

## D-44 不实现 L9 的 `subscribe`（M5）

- **冲突**：附录 A 的 L9 列了 `watch` / `subscribe` / `unsubscribe`，而 L4 已有
  `unsubscribe Agent -- Agent`（M3 实现并测试）。REQ-09 一个名字一种词性 → 不能两义并存。
- **选择**：保留 L4 的 `unsubscribe`（语义明确：注销出缺省广播域），**不实现** `subscribe`；
  L9 的「订阅」能力由 `watch` 覆盖（前端拿视图流）。
- **记入反馈**：SF-20。

## D-45 工具调用循环在**同一条流**里跑，默认钩子自动执行（M6 / REQ-48）

- **形状**：`send` 时把 `rb/tool-defs` 塞进 provider 请求的 `tools`；模型返回工具调用时
  ①发 `@Toolcall`（载荷 `Call Stream`）②本轮不触发 `@RoundDone` ③结果以 `role:"tool"`
  追加 ④**重发同一个 Stream**继续吐文本。
- **默认执行 = `@Toolcall` 上的默认钩子**：跑工具 → 追加 `tool` 消息 → 让流继续。
  `@off @Toolcall` 之后事件照发、工具不跑，流冻在 `:tool`（D-46）。
- **为什么不开新流**：前端看到「一条回复」比「一条回复 + 一条工具回显」自然，
  且符合 REQ-45「一轮 = list Stream」的最小改动。
- **会话四段**：`user` → `assistant(tool_calls)` → `tool` → `assistant`。
  其中 `assistant(tool_calls)` 存的是 **provider 的原始形状**（OpenAI 兼容的字符串键表），
  这样回放给 provider 时不用再翻译。
- **协议**：`@Toolcall` 单发一条 `event` 消息（`docs/PROTOCOL.md` 3.4），
  其余钩子事件不推（`chunk`/`close` 已覆盖，重复推会让前端双计）。
- **验收**：`C:req-47-51-capabilities`（mock 全链路）、`e2e/cli.sh`（协议 event）。

## D-46 停在工具调用上的流 = 状态 `:tool`（冻结，不 close）（M6 / REQ-48）

- **状态机**：`:new → :open → :done | :failed | :stopped`，新增 **`:tool`**。
- **`@off @Toolcall` 后**：流不 close、不 done，`rb/stream-next!` 返回 nil 但不改状态
  （与视图流的「暂时没有新条目」区分：视图流是常态，`:tool` 是**待外部动作**）。
- **`drain` 遇到 `:tool`** → 报 60「流停在待外部动作」；**`round-finish` 预扫到 `:tool`**
  → 清空本轮列表并按 REQ-18 报 60（本轮未完成）。
- **接管方式**（明文，不隐含）：`invoke` 跑工具 → `append` 结果 → `resend` 复活这条流。
- **验收**：`C:req-47-51-capabilities`。

## D-47 `onfail Agent [quot] -- Agent` 失败回退；`->` 记来源边；`subscribe` 恢复广播（M6 / REQ-51）

- **`onfail`**：把引号存进 agent 的 `:onfail`；默认 `@RoundDone` 钩子转换流时失败、
  且该流没有被更新的流取代，就执行引号并把栈顶当作**替代回复**并入会话（本轮仍完成）。
  引号在 `onfail` 里**先出栈**（书写 `onfail [ … ]`，agent 留在栈上）。
- **`->`**：`且 a b` 记 `b.origin ⊇ a`（最左实参 = 第一个操作数，先出栈 = `from`），
  返回后者；血缘只增不改（`origin` 词可读）。
- **`subscribe`**：**推翻 D-44**。它和 `unsubscribe` 是**一对反义动词**
  （注销出缺省广播域 / 恢复缺省广播域），不违反 REQ-09「一个名字一种词性」。
- **验收**：`C:req-47-51-capabilities`。

## D-48 能失败后重试，只能靠钩子 + `resend`（M6 / REQ-49）

- **核心不内置重试策略**：`@on @Fail [ pop resend pop ]` 就是全部——`resend` 接受
  **Agent 或 Stream**，所以在 `@Fail` 钩子里不需要解析标签。
- **失败流不并入会话**：默认钩子转换失败时先看「是否已被更新的流取代」；被取代 → 丢弃，
  所以重试成功后会话里只有成功那条 assistant 消息。
- **没装钩子 = 不重试**（明确报错，不静默重试）。`@Fail` 载荷 = `Fail Stream`。
- **收尾多趟**：一轮里钩子可能新建流（重试/回退），`round-finish` 用「版本号 `:round-rev`」
  判断列表还在变就再跑一趟（上限 64 趟，超过报 60）；钩子关着（列表不再变）就结束。
- **验收**：`C:req-47-51-capabilities`（`@on @Fail` 重试、`resend Stream`）。

## D-49 上下文压缩策略在用户侧，核心只给零件（M6 / REQ-50）

- **核心不内置任何压缩算法**：文档给出的标准写法是
  `@on @RoundDone [ … take -4 session … saysys … agent … ]`——截取近几轮 + 用 system 消息
  装摘要 + 新建 agent（新血缘，不动老会话）。
- **为什么放钩子层**：压缩是**策略**（保留几轮、怎么总结），策略进核心会变成不可关闭的隐含规则
  （违反「复杂度可见」）。
- **验收**：`C:req-47-51-capabilities`（钩子里改出摘要会话 + 多一个 agent）。

## D-50 `rb/render` 对函数/纤程给**定值**；`at` 的下标类型要检查（M6 打磨）

- **函数不打印地址**：`<function 0x…>` 每进程都不同 → 同一工作区的 `stack` 输出不可复现，
  测试与前端 diff 都会抖。改为 `#<function>` / `#<fiber>`（`rb/render`）。
- **`at` 的类型**：`n seq` 里的 `n` 对序列必须是整数（给键就报 31 类型错）；
  表/结构体仍按任意键取，缺键 = `nil`（这与 L1 多态一致，但不再静默吞掉用错下标的情况）。
- **能力调用失败的分级**：`rb/cap-call` 保留能力层自带的分级码（如 `:fs/*` 的 40/41），
  其余宿主级错误统一报 **31**（类型/值），不再落到「30 = 栈下溢」。
- **验收**：`unit/words-l0.janet`、`unit/words-l2.janet`、`conformance/*`（全绿）。

## D-51 递归 + 栈上条件的形式（`if [ 真 ] [ 假 ]`）

**问题**：`if cond [ 真 ] [ 假 ]` 按镜像执行成 `[假] [真] cond if`——先压两个引号，再算 cond。
因此 cond **只能**由它自己的 token 供操作数；条件若已算成栈上的值，两个引号会压在它上面，
`if` 拿到的是引号而不是布尔值。

**决定**（两条，都在**转译期**定，运行期无歧义）：

1. **语句里只有「词 + 引号」时走 stack 变体**：
   `if [ 真 ] [ 假 ]`、`when [ 体 ]`、`unless [ 体 ]`、`loop [ 体 ]`
   → 转译成 `rb/if-stack` / `rb/when-stack` / `rb/unless-stack` / `rb/loop-stack`，
   条件（或次数）**从引号底下**取。判据 = token 数恰好 = 词 + n 个块（`rb/stack-form?`）。
   只要语句里还有别的 token（如 `if < 2 [ … ] [ … ]`）就走原形，行为完全不变。
2. **定义行先占位、再转译体**（`rb/translate-def`）：体内可以**自引用**（递归）。
   否则 `fact : [ … fact … ]` 在转译期就报 20「未知的词」。

**用法**：

```
fact : [ dup
  > 2                      # 字面量填最左操作数 → 读作「2 > 栈顶」，即 n < 2
  if [ pop
  1 ] [ dup
  -1                       # n-1：加法可换，写 + -1 最省事
  +
  fact
  * ] ]
fact 5                     # 120
```

**注意（同一条法则的两个后果）**：

- 只写**一个**操作数时，字面量填**最左**位：`< 2` = `2 < 栈顶`，`- 1` = `1 - 栈顶`（不是减一）。
  想算 `n - 1`：写 `+ -1`（等价），或把 `1` 与 `swap` 分成两条语句。
- **一行 = 一个语句**：`[ pop 1 ]` 会镜像成「压 1 → pop」，即弹掉刚压的 1。要「弹掉再压 1」得写成两行。

**记录**：SF-29（规格缺「条件已算成值」的写法与递归说明）。

**验收**：`unit/words-l5.janet`（栈上形式 + 递归）、`conformance/req-05-definition.janet`（自引用）。

## D-52 定义行可带文档串（`名字 : "说明" [ 体 ]`）

- **问题**：字典里本来就有 `:doc` 字段，REQ-35 也说 `doc` / `see` 从字典读，但**没有语法**能写文档串——
  `doc` 永远是空串。
- **决定**：定义行接受两种形式：
  - `名字 : [ 体 ]`（REQ-34 的三 token 原形，`doc` 为空串）；
  - `名字 : "说明" [ 体 ]`（四 token，把说明交给 `rb/define-word`）。
  判据在转译期（`rb/def-doc?`），运行期无歧义；三 token 形式**完全不变**。
- **记录**：SF-30（建议把四 token 形式写进 REQ-34）。
- **验收**：`conformance/req-05-definition.janet`。

## D-53 宿主原生错误归入 31（30 只留给栈下溢）

- **问题**：`rb/error-code` 原先把**任何**不带 `:rb-code` 的宿主错误都映射成 30，
  于是 `len 3`（对 number 取长度）、`mod "x" 2` 这类**类型错**报 30——与附录 E
  「30 = 栈下溢 / 31 = 类型错误」冲突（D-50 已在能力调用处改成 31，这里补齐全局）。
- **决定**：`rb/error-code` 把宿主原生错误映射为 **31**；方言层自己 `rb/raise` 的错误码不变。
  因此 `pop` 仍是 30（方言层下溢），`len 3` / `mod "x" 2` 是 31。
- **影响**：`conformance/req-23-exit-codes.janet` 的 `len 3` 断言由 30 改 31，并补 `pop` = 30。
- **注**：宿主错误里也有越界之类的非类型错（如下标越界），一并归 31——附录 E 没有更细的码，
  记在 `docs/SPEC-FEEDBACK.md` 的 SF-31。

## D-54 provider 配置放进工作区（`llm` / `llm-get` / `llm-set`）

- **问题**：provider / 模型 / 端点 / 上限 / 温度原来只读环境变量（`RB_LLM`、`RB_MODEL`……），
  只能在**进程启动前**定死：一局里想先离线跑、再切真模型，只能重启——而重启会丢掉
  栈、字典、会话、钩子。REQ-14 又明确工作区 = 字典 + 栈（+ agent 等运行时对象），
  provider 恰恰是「这一局怎么说话」，天然属于工作区。
- **为什么不放词里**：常量词 `[ H{ … } ]` 每次调用都重建表，`llm-set` 改不到它；
  放词里还会让「改配置」变成「重定义词」，语义与持久化都更绕。
- **决定**：
  - 工作区新增 `:config`（普通表），三个词是它唯一入口：
    `llm -- Table`、`llm-get Key -- Value`、`llm-set Value Key --`。
  - **书写序**：`llm-set "nvidia" "provider"`（值在前、键在后）——镜像后栈顶是**值**、
    次顶是**键**，与 D-03「最左 = 第一个操作数 = 栈顶」一致；`nil` 值 = 删除该项。
  - **优先级**：工作区配置 > 环境变量 > 内置缺省。解析在能力层（`cap/config.janet`
    的 `cap/cfg`），核心只**存**不**解析**——核心不认识 provider 名字，也不读环境变量
    （守住 REQ-37 的能力边界）。
  - **白名单**：`provider model endpoint max-tokens temperature`；拼错 → 31。
  - **密钥不在其中**：`key` 被明确拒绝（60），密钥只从 `NVIDIA_API_KEY` 或
    `secrets/nvidia.key` 来。理由：快照/日志会把工作区整份落盘（REQ-20），
    密钥一旦可配置就一定会有人的 `.rbx` 里带密钥。
  - **持久化**：快照新增 `"llm"` 段（纯 JSON 对象）；日志行只在配置变化时带 `"llm"`。
    载入/重放时写回 `:config`。
- **记录**：SF-32（附录 A 补三个词；建议 REQ-14 的「工作区」段写明 provider 配置属于工作区）。
- **验收**：`tests/unit/config.janet`、`examples/11-llm-config.breve`。

## D-55 失败的一轮没有栈效果（求值级回滚）

- **问题**：栈下溢原本发生在**执行中**：`+ 1` 先压 `1`、再 `+` 时才发现栈不够，于是报错
  退出，**半截操作数留在栈上**。REPL / `--serve` 里每条语句是独立一次求值，下一行
  接着执行，就带着被污染的栈——看起来像「REPL 挂了」「必须重启」。
- **为什么不做事前静态校验**：`rb/push`/`rb/pop` 之外还有引号体、钩子、能力回调会改栈，
  栈深度不是编译期常量（`depth` 本身是运行时值）。静态算深度会给出「有时对有时错」的
  假保证，比回滚更糟。
- **决定**：`rb/run-source` 在求值前拷一份栈（`array/slice`），出错时把栈还原到求值前，
  再把错误抛出。即「**一次求值 = 一个事务**」：失败的一轮不产生任何栈效果。
  - 与 REQ-18 一致：失败的一轮本来就不触发 `@RoundDone`、不合并会话；现在连栈也不动。
  - 范围是一次求值（一条语句、一段脚本、协议里一个 `eval` 请求），不是逐语句：
    一段脚本中途失败 = 整段没有栈效果（更可预测，也避免「执行了一半」的中间态）。
  - 副作用（已写的文件、已发的请求）**不回滚**——只回滚栈。文档明说。
- **顺带修的观感问题**：REPL 在管道/重定向下 stdout 是块缓冲，错误（stderr）会先于
  提示符出现，看着像「重新开了一个 REPL」。现在每条报告前后 `flush`。
- **记录**：SF-33（规格没说失败求值的栈语义；建议写进 REQ-30/附录 E 附近）。
- **验收**：`tests/unit/config.janet`（D-55 用例）、`tests/e2e/cli.sh`（报错后可继续）。

## D-56 真 provider 的非 SSE 响应必须报错，不许静默空回复

- **问题**：模型名写错时 NVIDIA 返回 HTTP 404 + 纯文本 `404 page not found`。
  原来的 SSE 解析只认 `data:` 行与「整段 JSON 且带 `detail`/`error`/`message`」两种错误体，
  纯文本页两边都不匹配 → 被忽略 → 流正常结束、回复是空串、退出码 0。
  「模型名错了却成功返回空话」是最难查的一类问题。
- **决定**：SSE 解析里凡是不属于已知字段（`data:` `event:` `id:` `retry:` `:`）的行，
  都按错误处理：
  - 能解成 JSON 且带 `detail`/`error`/`message` → 用它报 60；
  - 能解成 JSON 且带 `status` → 报 60 并带上 HTTP 状态码与 `title`；
  - 连 JSON 都不是 → 报 60 并附上该行前 200 字节。
- **注**：这条不影响 hermetic 测试（`cap/mock` 走另一条路径），只在真 provider 上生效；
  `make test-agent` 里用「坏模型名」这一例覆盖（见 `tests/e2e/agent.sh`）。
- **验收**：`RB_MODEL=不存在的模型 RB_LLM=nvidia ./bin/ravel -e '…'` → 60 且消息里含
  `404 page not found`。

## D-57 REPL 行编辑器：Emacs 键位 + Vim 模式切换（前端层）

- **需求**：给 `ravel` 的 REPL 加 Emacs 与 Vim 两种编辑键位，用 **Vim 的模式切换**
  在两者间切换；只收最常用的动作；错误处理简单但**留好 API**。
- **分层**：键位属于**前端**，不进方言核心——核心词表、转译、协议一律不动。
  新增 `rb/line.janet`（装载序在 `words/l9` 之后、`cli` 之前），`rb/cli.janet` 的 REPL
  把 `getline` 换成 `(rb/line-read prompt hist)`。`--serve`、`-e`、脚本路径**不变**。
- **三种模式**（用 Vim 的模式概念当开关，不引入第二套切换键）：
  | 模式 | 提示符 | 切换 |
  |---|---|---|
  | `:emacs`（缺省） | `ravel> ` | normal 下按 `Esc` |
  | `:vim-normal` | `ravel> -- NORMAL -- ` | Emacs 下按 `Esc`；insert 下按 `Esc` |
  | `:vim-insert` | `ravel> -- INSERT -- ` | normal 下 `i`/`a`/`I`/`A` |
  - 模式必须有**可见**标记：两级模式不给提示就是「按了没反应」。
  - `Esc` 是唯一开关（不新增 `C-x` 之类第二开关）：Emacs → normal → Emacs 两级往返。
- **最小集合**（用户：「如无必要勿增实体」）：
  Emacs：`C-a C-e C-b C-f C-k C-u C-w C-d C-c C-l Tab` + 方向键 + `M-b/M-f`（`C-←/C-→`）。
  Vim normal：`h l 0 $ w b i a I A x D dd u`；insert：可打印字符 + `Esc` + 编辑键。
  **不做**：kill ring、补全、多行、数字前缀、寄存器、可视模式、`P`/`p`、`c`/`r`、搜替换。
- **实现**：不依赖宿主终端库。
  - `src/main.c` 提供终端原语表 `rb-term`（`tty` / `raw-on` / `raw-off` / `read-key`），
    `read-key` 在 C 里做原始模式读取 + `ESC` 歧义消解（ESC 后 40ms 无后续字节 = 单按 Esc）
    + UTF-8 组装 + CSI/SS3 解析（`A/B/C/D/H/F`、`~3`、`;5`/`;3` 修饰 → 按词移动）。
  - 方言层用**间接层**取它：`(dyn :rb-term)`（同 D-29）。取不到（裸 `janet` 跑单测、
    非 unix 宿主）就 `rb/line-tty?` = false → 自动走 `getline` 行模式，内核照样装载。
  - 文本按**码位数组**存（CJK 退格只删一个字），宽度粗算（宽字符 2 列），
    重绘用 `\r ESC[K <提示符+文本> \r ESC[<列>C`，不做换行/滚动计算。
- **错误处理**（用户：「简单的就好，保留好 API」）：
  - 原始模式只在**读这一行**时开，读完立刻 `raw-off`（求值期间是熟模式，
    所以 `C-c` 在求值时仍是中断程序，不会吞掉）；`atexit` 兜底恢复终端。
  - `rb/line-read-tty` 用 `try` 包住编辑器：任何异常 → `rb/line-on-error` 一行提示 →
    立即退回 `getline`；**不会**因为编辑器坏了就不能用 REPL。
  - 扩展点（都是公开数据/var，不必改 `rb/line.janet`）：
    | 名字 | 作用 |
    |---|---|
    | `rb/line-reader` | 读一行的唯一入口 `(prompt hist) -> String 或 nil` |
    | `rb/line-emacs-keys` / `rb/line-vim-normal-keys` / `rb/line-vim-insert-keys` | 键位表：`键 -> (fn [st] 动作)` |
    | `rb/line-apply-key!` | 键码 → 动作（`nil`/`:submit`/`:eof`/`:abort`），写回 `(st :action)` |
    | `rb/line-edit` 第三参数 | 注入键源（单元测试不需要终端） |
    | `rb/line-on-error` | 出错提示方式 |
- **语义细节**：
  - `C-d` 空行 = EOF；非空 = 删光标处字符（Emacs 习惯）。
  - `C-c` = 丢弃本行（返回 `nil`，REPL 什么也不做，继续读）。
  - 历史只记提交过的非空行；翻历史时把「打了一半的内容」存进 `:saved`，翻回底部还原。
  - Vim `dd` / `u` / `x` / `D` 都基于同一份撤销栈（最多 32 步）。
  - insert 下 `Esc` 光标左移一格（同 Vim）；`a` 也是「后一字符」。
- **为什么不改 `getline`**：宿主的 `getline` 是行缓冲的，没有按键事件；
  要「边打边改」只能自己进原始模式。同时保留 `getline` 作为无终端时的实现。
- **验收**：`tests/unit/line.janet`（20 例，注入键源，覆盖三种模式、历史、CJK、
  撤销、扩展点、无终端退回）；端到端仍由 `tests/e2e/cli.sh` 的管道用例覆盖；
  pty 手工验收见 `docs/CHK-7.md`。

## D-58 compact 主判据加下限 512 字节（v1.0e 的 SF-18 处置）

- **问题**：REQ-21 的主判据是「日志 > 快照的 0.5 倍」。小工作区（十来个词）快照 ~300 字节、
  一行日志 ~120 字节 → 大约两轮就超过 0.5 倍，于是**每轮都 compact**；
  增量日志退化成「每轮全量重写」，与 REQ-20 的意图正好相反。
- **决定**：`rb/store-compact-needed?` 改为
  `日志 > max(0.5 × 快照, 512 字节)`，另两个条件（> 1000 条 / 显式 `compact`）不变。
  - 512 是常量 `rb/store-log-floor`（不是散落的魔数），并写进规范（v1.0e 的 REQ-21）。
  - 判据仍然**可见**：`rb/store-log-ratio` 照旧给出 `:log` / `:snap` / `:ratio`，只是触发多一个下限。
- **验收**：`tests/unit/store.janet`（0.5 边界 + 512 下限）、
  `tests/conformance/req-21-compact.janet`（判据接线 + 小工作区三轮不 compact）。

## D-59 处理流程显式化：模式 ⇄ 钩子（v1.0f 的 REQ-52）

- **问题**：「一轮请求怎么被处理」过去只存在于**钩子表的当前状态**里——读者要自己 `show` 一张
  八事件表、再推断"谁在跑、谁被 `@off` 了、有没有 system 提示、哪些工具在场"。这与 spec 的
  「复杂度可见」原则不符；也没有"预设流程"可一键切换（例如只让模型交程序、不逐步发 tool_call）。
- **决定**：把这份状态**显式化**为数据，并允许**双向**转换：
  - **模式** = `@{:kind :mode :name :doc :flags :hooks :prompt :tools}`；`hooks` 形状规范：
    **8 个事件全在**（未声明 = 空数组），于是"没有钩子"与"没写这个事件"不会混淆。
  - `mode`（`Name|Mode --`）= 模式 → 工作区：整体替换钩子表、写 `:flags`、写 `:mode-prompt`、
    **撤掉所有预制模式声明过的工具**再装本模式声明的工具（模式之间不互相污染）。
    未知名字 → 20；非模式表 → 31。
  - `mode-of`（`-- Mode`）= 工作区 → 模式；与 `mode` **互逆**。为了能逐项 `deep=` 比较：
    预制 `default` 的钩子对象与 `ws-new` 用的是**同一批函数对象**；`mode-of` 的 `:doc`
    在有同名预制时沿用预制文档（否则文档会破坏往返相等）。
  - 自省名词（只读）：`mode-name` / `mode-prompt` / `mode-tools`。**没有**给模式表加
    "关键字字面量"或 `at :name` 之类通道——方言没有关键字字面量（SF 已冻结），
    所以字段访问一律走名词。
- **历史标记（开关缺省全开）**：`:turn` / `:from` / `:mode` 打在 Utter 上。
  - 只用三个开关名（`history-turn` / `history-origin` / `history-mode`），`flag` / `flag-set` 读写。
  - **标记不进请求**：请求由 `rb/messages-of` 重建，只含 `role` / `content` / `tool_calls`
    等协议字段——否则 provider 会看到本方言的内部记号。
- **PTC（预制模式 `ptc`）**：仿 DeepSeek harness 的 Programmatic Tool Calling。
  - 只留**一个**工具 `eval`；模型把它要做的多步编排写成**一段 ravel 程序**（程序里 `invoke`），
    `eval` 跑完返回**栈顶**作为工具结果 → 多步编排不再消耗模型回合。
  - 模式的系统提示**只进请求**（前置换一条 `role:"system"`），**不进会话历史**：
    否则历史被说明文字污染，切模式后旧提示还留着。
  - `eval` 内部求值走 `nested?`：**不做一轮收尾**，否则会在 `@Toolcall` 钩子里递归触发
    `@RoundDone`（顺带把中间量并进会话）。
  - 程序失败 → 60（编排级），并保留 D-55（失败无栈效果）。
- **为什么不另起执行机制**：模式只是**钩子集合的显式表示**；`@off @Toolcall` + 手动
  `invoke`/`append`/`resend` 照样可用。因此"模式 ⇄ 钩子"必须能来回，而不是两套并行语义。
- **验收**：`tests/unit/modes.janet`（往返 `deep=`、开关、PTC 工具、提示只进请求）、
  `tests/conformance/req-52-modes.janet`（词层往返、ptc 一轮只一次工具调用、
  程序内 `invoke` 串多工具、失败 60、标记可关）；`tests/e2e/cli.sh` 的 watch/session
  期望同步带上标记。

## D-60 文件沙箱：根 = 当前目录，越界写 41 / 读 40（v1.0g 的 REQ-53）

- **问题**：能力层 `:fs/*` 是任意路径；模型（或一段 PTC 程序）一句话就能把内容写到
  仓库外、或把 `~/.ssh/id_rsa` 读进会话。REQ-37 只规定了「能力可剔除」，没规定边界。
- **决定**：`cap/fs.janet` 的五个能力入口统一先过 `cap/fs-check`：
  - 根 = `RB_SANDBOX`（缺省 = `os/cwd`）；`RB_SANDBOX=none|*` 关闭（脚本要跨目录时显式开）。
  - **规范化之后再判**：存在 → `os/realpath`（解符号链接）；不存在 → 父目录 `realpath` + 基名。
    因此 `sub/../../etc/x` 也拦得住（测试里就钉了这一条）。
  - 越界写 → 能力抛错，`rb/store-file-write` 归 **41**；越界读 → `cap/fs-read` 返回 nil，
    `read` 归 **40**。**读不另造一个错误码**：读的契约本来就是「读不到」。
- **为什么不放在词里**：`write`/`save`/`compact` 全都经能力层（REQ-37），
  边界只有一处才守得住；`--core-only` 时本来就没有文件能力，边界自然不存在。
- **副作用（已改）**：`tests/e2e/cli.sh`、`examples/06-files.breve`、`docs/GUIDE.md`
  原来写 `/tmp/…`，现在一律写 `build/tmp/…`（仓库内 = 沙箱根内）。
- **验收**：`tests/unit/fs-sandbox.janet`（根内外、`..` 绕路、换根、`none`、`size` 也守门）、
  端到端「根外写 41 / 根外读 40 / 根内仍可写」。

## D-61 默认工具包（v1.0g 的 REQ-54）

- **问题**：agent 只有「聊」的能力；要让它改文件、搜内容、找文件，用户得自己写 `deftool`
  ——而这些恰恰是最常用的四个动作。
- **决定**：能力层 `cap/tools.janet` 注册 `edit` / `grep` / `glob` / `shell`，并注册
  `:tools/install`；`rb/ws-new` 建工作区时若该能力在场就装进工具表。
  - **不进核心词表**（附录 D 不变）：它们是**工具表项**，`invoke` 调用，模型自决调用走
    既有 `@Toolcall` 默认钩子（REQ-48）。`--core-only` 时工具表为空。
  - **`edit` 是字面量替换**（不是正则）：一处没找到 → `60`（模型通常把 old 抄错了）。
  - **`grep` / `glob` 是字面量/通配**：`*` `?` 段内、`**` 任意层；各限 200 条（防炸栈）。
  - **`shell` 默认关闭**：`RB_ALLOW_SHELL=1` 才跑。一句 `sh -c` 等于绕过 D-60，
    所以它必须是显式选择；未开 → `60`。
  - **输出捕获**：janet 1.42 的 `os/execute :p` 只是「查 PATH」，stdio 直接接本进程；
    要拿到 stdout 只能自己 `os/spawn` + 重定向到临时文件（`os/tmpname` 也不存在，用 TMPDIR/pid/序号）。
- **与模式（D-59）的关系**：工作区新增 `:mode-tools`（当前模式装了哪些工具）。
  切模式时**只撤这一批**，再装新模式声明的那批——用户自己 `deftool` 的工具（比如 PTC 程序里
  要 `invoke` 的）不受影响；`ptc` 仍然只留 `eval`。
  预置 `default` 模式的 `:tools` = 能力层的同一批函数对象，所以 REQ-52 的 `deep=` 往返仍成立。
- **验收**：`tests/unit/cap-tools.janet`（四个工具 + 沙箱守门 + shell 开关）、
  `tests/conformance/req-47-51-capabilities.janet`（模型发起 `edit` → 文件真被改 + 结果回会话）、
  端到端沙箱三条、`core-only` 仍通过（工具表为空）。

## D-62 用量记账（v1.0h 的 REQ-55）

- **问题**：花掉多少 token 只有 provider 知道；编排层看不见就无法做「按用量压缩 / 成本上限」。
- **决定**：provider 可在**取尽之前**吐一个**元信息块** `@{:usage {...}}`。
  - 块**不是文本**：不发 `@Chunk`、不进 `(stream :text)`、不参与渲染。
  - `rb/stream-next!` 见到它就记进 `(stream :usage)` 并**立刻**累加进工作区 `:usage`
    （`rb/usage-add!`），然后继续取下一块。
- **为什么立刻记、而不是 `@Done` 时记**：一轮工具调用会跨**多次 provider 请求**
  （工具批一次、最终文本一次），等 `@Done` 只能留下最后一笔。
  实测：`add2` 工具轮应为 `calls 2 / 6 / 4 / 10`，晚记就只有 `1 / 5 / 3 / 8`。
- **`calls` 的语义**：**报过账的 provider 请求数**（= 收到的元信息块数），
  不是「一次 `send` 的次数」。不带用量的 provider 不涨 `calls`，也不报错。
- **`tool-loop` 的分支顺序**（踩过的坑）：纯用量块必须 `(and (table? v) (get v :usage)
  (not (get v :tool-calls)))` —— 少了最后一条，带 `:tool-calls` 的批会被当成纯元信息块
  直接返回，**工具根本不执行**。
- **工具批也可能带用量**：执行完工具、把下一批的取块函数换好之后，先把这一批的用量交出去
  （`out = @{:usage …}`，`go = false`），下一轮 `pull` 才拿到文本。
- **`usage` 词读拷贝**，且键是**字符串**：方言没有关键字字面量（REQ-06），
  关键字键在方言里根本读不到（`at "total-tokens"` → nil）。内部 `:usage` 仍是关键字。
- **验收**：`tests/unit/usage.janet`（单轮 / 多轮累加 / 元信息块不进正文 / 工具轮两次 / 读拷贝）。

## D-63 取消与流截止时间（v1.0h 的 REQ-56 / REQ-57）

- **问题**：流跑飞了无法从外部叫停；上游作废后下游还在跑；provider 卡住 = 进程卡住。
- **决定**：
  - `stop`（REQ-36）停一条流时，沿 `->` 的**血缘边**把下游一并停。
    实现：`rb/cancel-cascade!` 看下游 agent 的 `origin` 是否含上游 `label`，递归（状态机防重入）。
    理由：血缘就是「谁的话算数」，与 `onfail` / 广播域同一条边。
  - `cancel`：方言词（0 元，`-- Int`）+ 协议请求（`{"type":"cancel"}` → `result` 带 `stopped`）。
    停**所有还开着的流**（本轮 + 视图流），**不结束会话**。
  - `RB_STREAM_DEADLINE_MS`：从**建流时刻**（`os/clock`）起算，每次取块前检查；
    超时 → 流 `:failed` + `@Fail`，退出码 **60**（编排级）。
- **为什么截止时间用 `os/clock` 而不是 `os/time`**：Janet 1.42 的 `os/time` 只到**秒**，
  毫秒级截止时间永远不触发（实测两次读数相同）；`os/clock` 是带小数的墙钟秒。
- **为什么 `cancel` 在 `--serve` 里通常 `stopped 0`**：求值是**同步**的，一次 `eval` 内的流
  在返回前已经收尾；可停的只剩「视图流正在被推进」与「REPL 里还没 `drain`」的流。
  所以 `cancel` 的主战场是 REPL 与**前端停止按钮**（配合 `RB_STREAM_DEADLINE_MS`），
  而不是"打断正在跑的 provider"——那需要线程/进程级取消，属 §5「明确不做」。
- **验收**：`tests/unit/cancel.janet`（血缘传播 / `cancel` 计数 / `cancel` 词 / 截止时间）、
  `tests/e2e/cli.sh` 四条（协议形状 + 会话存活 + 方言词）。

## D-64 OpenCode Zen / Go：第二个真 provider，SSE 解析收敛到一处

**背景。** 真 provider 只有 NVIDIA 一家时，`cap/nvidia.janet` 里攒了三样东西：
传输（HTTP + SSE）解析、用量累积、工具增量累积。加第二家时若照抄一份，
D-56（非 SSE 一律 60）与 REQ-55（用量立刻记账）这类**已经踩过的坑**就会各有一份实现、
各自漂移。

**决定。**

1. **抽出 `cap/oai.janet`**：`cap/oai-pull lines dec label` 返回取块函数，负责
   `data:` 行、空行/注释/`event:`/`id:` 跳过、`[DONE]`、`content` 增量、`tool_calls`
   按 `index` 累积、收尾 `usage` 帧先吐元信息块、**一切非 SSE 行报 60**。
   provider 文件只剩三样：**密钥、请求体、请求头**。
2. **新 provider `opencode`**（`cap/opencode.janet`，注册键 `:llm/opencode`）：
   - 端点 `https://opencode.ai/zen/go/v1/chat/completions`，`RB_OC_BASE` 换基址
     （给到 `/chat/completions` 也认，不重复拼）。
   - 密钥 `OPENCODE_API_KEY` → `secrets/opencode.key`（照 D-54：密钥不进工作区/快照）。
   - **必须**带 `User-Agent: ravel-breve/<版本>` 与 `x-opencode-session`；后者取自
     `opts :session`（`rb/stream-start` 填 agent 标签），跨轮稳定——路由器与提示缓存要它，
     缺了直接 `MissingSessionID`。所以 `rb/stream-start` 新增一个 `:session` 字段
     （不影响方言、不进快照）。
   - `User-Agent` 用 `rb/version`（干净的 `1.0h`），**不用** `rb/version-string`
     （后者含空格与 `·`，非法 HTTP 头值）。
3. **provider 的选择与缺省跟着 provider 走**：`cap/llm-model` / `cap/llm-endpoint`
   的缺省按当前 provider 决定；`auto` = **nvidia > opencode > mock**（有谁家密钥用谁）。
   `cap/llm-provider` 是 `cap/llm-model` 的前向依赖，故在文件里**定义在它前面**
   （Janet 编译期解析符号，顺序反了就 `unknown symbol`）。
4. **`reasoning_content` 不算正文**：思考过程不进流文本、不进会话、不触发 `@Chunk`。

**为什么 `:session` 放在 `opts` 而不是工作区。** 它是**传输层**的路由提示，
不是工作区状态：不进 `dump`、不进快照、不参与 `deep=` 往返。方言侧看不到它。

**验收。**

- `tests/unit/opencode.janet`（4 例，全离线：把 `:http/post-lines` 换成假行源）：
  端点缺省与 `RB_OC_BASE` 覆盖；`provider=opencode` 时的模型/端点缺省与 `llm-set` 覆盖；
  请求头（Bearer、`ravel-breve/` 前缀、`x-opencode-session` 两次同值、`stream:true`、
  `include_usage`）；SSE 里 `reasoning_content` 不进正文而 `usage` 照收。
- `tests/e2e/opencode.sh`（真 provider，`make test-oc`，无密钥跳过）：一轮对话、
  `drain`、逐块、广播、坏密钥 60、坏模型 60、用量记账、工具调用留下 `role=tool`。15 项全过。
- 回归：`cap/nvidia.janet` 改为调用 `cap/oai-pull`，`make test` 全绿（369 + 103 + 14 + core-only）。
