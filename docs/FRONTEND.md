# 前端契约（M7）：编辑器 ↔ `ravel --serve`

> 本文件**不实现前端**，只把 REQ-26 / REQ-27 / REQ-29 翻译成协议 v1 的动作表，
> 好让前端（Emacs 优先）与后端能并行开发、互不猜测。协议本身见 `docs/PROTOCOL.md`（已冻结 v1）。

前置：后端 = 一个 `ravel --serve` 子进程；前端 = 唯一的人机界面。
前端**不做**任何方言解析、求值、栈维护——那是后端的事。

---

## 1. 三个界面元素

| 元素 | 规格 | 数据来源 | 前端要做的事 |
|---|---|---|---|
| 底栏（REQ-26） | 显示**当前 token 序列**，字符串以占位 `"…"` 显示、**不显示内容** | 用户正在敲的那一行（本地） | 只做分词占位显示；不理解语义 |
| 主 buffer（REQ-27） | agent 的**会话视图** | `result.stack` + `chunk`/`close`/`event` | 顺序渲染，不解析栈文本 |
| 来源树 | 切换 agent 时显示血缘 | `origin` 词的结果（`result.stack`） | 树形渲染 |

## 2. 协议动作表

| 用户动作 | 前端发出的请求 | 后端回什么 | 前端怎么显示 |
|---|---|---|---|
| 底栏敲一行并回车 | 裸文本行（= `eval`） | `result`（可能先有若干 `chunk`/`close`/`event`） | 追加到主 buffer；失败显示 `error` + `code` |
| 需要请求/响应配对时 | `{"type":"eval","src":"…","id":N}` | 带同样 `id` 的 `result` | 按 `id` 归位（并发/迟到响应不乱序） |
| 清空主 buffer（REQ-29 `c`） | `{"type":"reset"}` | `result`（`ok:true`、`stack:[]`） | 清屏；**后端工作区也被丢弃** |
| 元命令 `quit`/`exit` | `{"type":"quit"}` | `bye` → 退出码 0 | 关闭 buffer / 退出 |
| 元命令 `help` | ——（**纯前端**） | —— | 显示词表/按键帮助；**不发请求** |
| 元命令 `clear` | `{"type":"reset"}` | 同上 | 同 `reset` |
| 启动握手 | `{"type":"hello"}` | `hello`（含 `protocol` / `version`） | `protocol` ≠ 1 → 报错并拒绝启动 |
| 心跳/存活检查 | `{"type":"ping"}` | `pong` | 不做显示 |
| 停止按钮（`C-c C-k`） | `{"type":"cancel"}` | `result`（`ok:true`、`stopped:N`） | 把本轮流按「已中止」收尾；**不清屏、不丢工作区** |

**要点**

- **元命令是前端的命令表**（REQ-25 / 协议 §4.7）：后端只认 §2 的请求类型。
  `help` 完全不用发请求；`quit`/`exit`/`clear` 分别映射到 `quit`/`quit`/`reset`。
- **底栏原始内容一律直发**：不要在前端「补全成 JSON」——协议 §2.1 的判定规则
  （`{` 后紧跟 `"` 才是 JSON 请求）保证 `{ 1 2 }` 这类字面量能原样求值。
- **停止 = `cancel`，不是 `reset`**（REQ-56）：`reset` 会丢掉整个工作区；`cancel` 只停还开着的流
  （`stopped:0` 也是正常结果），之后的 `eval` 照常可用。真 provider 卡住的场景还要配后端
  `RB_STREAM_DEADLINE_MS`（超时 = `code:60`，不是「空回复 + 0」）。
- **`stack` 是渲染好的文本**（协议 §3.1）：前端只显示，不解析、不做深色语法高亮推断。
  一条 `result` 的 `stack` 长这样：`["@{:kind :agent …}"]`。

## 3. 把流渲染进主 buffer

顺序（同一个 `stream` 标签内）：

1. `event`（若有）→ 在会话里插一行「工具调用：`text`」，样式可灰。
   v1 只有 `@Toolcall`；`@off @Toolcall` 之后**仍然**会收到 event，但工具不会被自动执行
   （此时该轮不会 `close`，见协议 §3.4——前端可提示「待接管」）。
2. `chunk` → 按 `n` 从 0 递增**追加**文本（`n` 有缺口说明丢块，可提示）。
   `send` 与 `resend` 的流**共用同一个 `stream` 标签且块序号连续**（D-45/D-48）：
   工具调用中断再续、失败重发，看到的都是同一条回复。
3. `close`（`ok:true`）→ 本轮结束，收尾钩子已把文本并入会话。
   `close`（`ok:false`）→ 显示错误，**但其他流仍会继续**，不要冻结整个 buffer。
   `watch` 视图流**没有** `close`（常驻观察者），不要等它。

`chunk.stream` 是 agent 的 `Label`：多 agent（`bcast`）时用它分流到各自 buffer/区块。

## 4. 三类常驻推送

| 推送 | 何时 | 前端语义 |
|---|---|---|
| 视图推送（REQ-28 / 协议 §4.4） | 每轮处理完 | `watch` 过的 agent 的**会话新增条目**，文本形如 `@{:content "…" :role "…"}`；按 `stream` 归位，与 `chunk` 同法追加 |
| `chunk` 块推送（REQ-08） | 流到达即 flush | 只追加，不改历史 |
| `event`（REQ-48） | 模型发起工具调用 | 插「工具调用」行；不影响后续 `chunk` 追加位置 |

## 5. 按键（REQ-29，should）

| 键 | 动作 | 实现方式 |
|---|---|---|
| `t` | 插入 `take` | 纯前端：底栏插入文本 |
| `s` | `say` + 进入字符串编辑模式 | 纯前端：插入 `say "` 并把光标放进引号，等用户敲内容与收尾 `"` |
| `c` | 清空主 buffer | 发 `{"type":"reset"}`（后端工作区一并清空；只想清屏可以纯前端清，但那会让屏幕与后端不一致——**默认走 `reset`**） |

字符只在**底栏**生效，主 buffer 只读。

## 5.1 终端里的 REPL 键位（`bin/ravel` 自带，不属 Emacs 前端）

`bin/ravel` 的 REPL 自身有一个行编辑器（D-57），**只影响交互终端**；
`--serve`、`-e`、脚本执行完全不受它影响（管道里行为仍是行模式）。

| 层 | 内容 | 是否为「前端」 |
|---|---|---|
| 方言核心 | 词表、转译、协议 | 否 |
| `ravel` 自带 REPL | Emacs 键位（缺省）+ Vim 模式（`Esc` 切换） | 是（终端前端） |
| Emacs 前端 | `--serve` 上的 NDJSON 客户端 | 是 |

因为键位属前端，它与 Emacs 前端**没有**必须一致的关系：两边各按各的习惯来。
可复用的只是「扩展点」这一形状（数据表 + 单一入口）：

| `ravel` REPL | 对应概念 |
|---|---|
| `rb/line-reader`（读一行的唯一入口） | 协议里 `eval` 请求是唯一的求值入口 |
| 三张键位表（`rb/line-*-keys`） | Emacs 侧的 `ravel-mode-map` |
| `rb/line-on-error`（出错后如何降级） | 前端「后端异常退出」时的提示路径 |

要换掉 REPL 的编辑器（补全、语法高亮、多行缓冲）只需
`(set rb/line-reader (fn [prompt hist] ...))`，其余代码不用改。

**别把 REPL 的折行当成前端的规范**（D-70）：REPL 是单行编辑器，长行靠「折行 +
按显示宽度重绘」和括号粘贴（`ESC[200~ … ESC[201~`）撑着；两件事都是
`bin/ravel` 的实现细节，协议里没有任何对应物。Emacs 前端该用多行 buffer，
不必模仿这里的「换行折成空格」。
顺带一条**边界**：括号粘贴的开/关序列只在 `isatty(stdout)` 时发——
stdout 承载协议（REQ-43），`--serve` 与重定向时一个字节也不多写。

## 6. 错误与退出

- 求值失败 = `result.ok:false`，**不杀进程**（协议 §4 / REQ-42）。前端显示 `error` + `code`
  （码表见 `docs/DECISIONS.md` D-05 或 `rb/exit.janet`）。
- 前端自己产生的协议错误（坏 JSON、未知 `type`）后端报 `code:2`。
- 后端 stderr 是**诊断**（`print`/`show`/日志），可进 `*ravel-log*` buffer；不要混进主 buffer。
- 后端异常退出（非 0，或 `50`）→ 提示并给出 stderr 末尾。

## 7. 前端的「不做」清单

| 不做 | 理由 |
|---|---|
| 解析/求值方言 | 唯一求值者是后端（REQ-24） |
| 维护栈或字典 | 工作区在后端（REQ-30 / REQ-42） |
| 解释 `stack` 文本 | 协议 §3.1：已渲染 |
| 解析 `chunk` 里的会话 JSON 做「智能」渲染 | v1 只当文本；`watch` 推送同理（它是 `show` 的输出） |
| 自己实现 `take`/`say` 语义 | 按键只插文本，执行仍由后端完成 |
| 背压协商 | 后端每轮最多推 64 块（SF-22） |

## 8. 最小可跑通的样子（Emacs 侧伪代码）

```elisp
;; 启动
(unless (eq 1 (ravel-hello-protocol)) (error "协议版本不兼容"))

;; 底栏回车
(ravel-send (concat (buffer-substring-no-properties (line-beginning-position)
                                                    (line-end-position))
                    "\n"))

;; 收到一行 JSON
(pcase (alist-get 'type msg)
  ("chunk" (ravel-append-chunk (alist-get 'stream msg) (alist-get 'n msg)
                               (alist-get 'text msg)))
  ("event" (ravel-insert-toolcall (alist-get 'stream msg) (alist-get 'text msg)))
  ("close" (ravel-close-stream (alist-get 'stream msg) (alist-get 'ok msg)))
  ("result" (if (alist-get 'ok msg)
                (ravel-show-stack (alist-get 'stack msg))
              (ravel-show-error (alist-get 'code msg) (alist-get 'error msg))))
  ("hello" (setq ravel-version (alist-get 'version msg)))
  ("pong" nil)
  ("bye" (ravel-shutdown)))
```

---

## 9. 需要后端配合时的排查顺序

1. `ravel -v` → 版本串是否本仓库的；
2. `printf '{"type":"hello"}\n' | ravel --serve` → `protocol:1`；
3. `printf '1\n' | ravel --serve` → `result.stack = ["1"]`；
4. 有 `chunk` 没 `close` → 该流失败或停在 `:tool`（D-46）；
5. 完全没有响应 → 检查是否把裸文本包成了 JSON（协议 §2.1）。

---

## 附录：网页原型（`web/`，M20 后新加）

Emacs 仍是第一目标（§1 的结论没变），但同一份协议可以先拿浏览器验证交互：
`web/bridge.py` 把 `ravel --serve` 的 JSON 行翻成 HTTP + SSE，`web/index.html` / `app.css` / `app.js`
是**没有构建步骤**的前端。它把本文的三条约束落成了代码：

1. **不解析**：栈项的文本只是字符串，拖动改序、编辑、分割、包引号都是本地字符串操作；
   「程序」框里的源就是从本地栈逆序拼出来的行，勾「手改」才停止推导。
2. **不维护求值状态**：「后端栈」只显示 `result.stack` 的文本，只能拖回（复制），不能改序。
3. **协议按 §7 的配对规则**：`result` 回显 `id`，`hello`/`pong`/`bye` 按 `type` 配对。

它额外回答了 §6 里「`help` 是纯前端」之外的另一个纯前端问题：**词表从哪来**。
答案是 `web/gen-catalog.py` 从规格附录 A 机械抽取（不手写），产物 `words.json` 带每层的
`name` / `effect` / `desc` / `arity`（`arity` 由栈效应 `--` 左侧推出）。

跑法、手势表、皮肤怎么加、以及「后端栈是 REPL 语义、会跨次累积」这一条边界，见 `web/README.md`。
