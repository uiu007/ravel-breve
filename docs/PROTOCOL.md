# NDJSON over stdio 协议 v1（M5 冻结，CHK-5）

REQ-24：编辑器 = 前端（只渲染与输入），`ravel breve` = 后端（唯一求值者），
以 **NDJSON over stdio** 通信。本文是 v1 的**冻结**说明；后续变更必须升
`protocol` 版本号并改本文件。

实现：`rb/proto.janet`（消息与旁路）、`rb/cli.janet`（`--serve` 循环、请求解析）。
验收：`tests/conformance/req-24-duplex.janet`、`tests/e2e/cli.sh`。

---

## 1. 传输

- 一行一条 JSON 对象，`\n` 结尾，UTF-8。
- 后端的 **stdout 只承载协议消息**（REQ-43）；诊断与方言的 `print`/`show` 输出走 stderr。
- 输入 EOF（stdin 关闭）→ 后端退出码 **0**。
- 空行（只含空白）**忽略**，不产生响应。
- **一个请求 → 一条终结响应**（`result` / `pong` / `hello` / `bye`）；
  求值过程中还可先冒出任意多条 `chunk` / `close`。
- 单次求值失败**不**终止循环：只反映在响应的 `code` 字段（REQ-42）。
- 进程退出码：正常 0；用法错误 2；内部错误 50（`rb/exit-table`，REQ-23）。

## 2. 请求（前端 → 后端）

### 2.1 裸文本 = `eval` 的简写

```
take 2 "abcde"
```

裸文本原样当 ravel 源码求值（等价于不带 `id` 的 `eval` 请求）。
前端可把底栏敲的内容直接转发（REQ-26）。

**判定规则（避免与字面量混淆）**：一行只有在 `{` 之后（跳过空白）紧跟 `"` 时
才按 JSON 请求解析；否则一律当源码。因此 `{ 1 2 }` 是**字面量表达式**，
`{"type":"eval"}` 才是请求。

### 2.2 显式 JSON 请求

| `type` | 字段 | 语义 | 响应 |
|---|---|---|---|
| `eval` | `src`（string，必需）、`id`（任意，可选） | 在当前工作区求值 | `result` |
| `ping` | — | 连通性检查 | `pong` |
| `hello` | — | 握手，取协议/实现版本 | `hello` |
| `reset` | `id`（可选） | 丢弃工作区（字典 + 栈 + agent），换新的 | `result`（`ok:true`，`stack:[]`） |
| `cancel` | `id`（可选） | 停掉还开着的流（含 `->` 血缘传播）；**不结束会话**（REQ-56） | `result`（`ok:true`，`stopped:N`） |
| `quit` | — | 结束服务 | `bye`，然后退出码 0 |

- 缺 `type` 时按 `eval` 处理（`{"src":"1"}` 合法）。
- `eval` 缺 `src` 或 `src` 非字符串 → `result` / `code:2`。
- 未知 `type` → `result` / `code:2`。
- 坏 JSON → `result` / `code:2`，服务继续（REQ-42）。
- `id` 若出现，**原样回显**在对应响应上；前端可用它做请求/响应配对。

```json
{"type":"eval","src":"+ 1 2","id":7}
{"type":"ping"}
{"type":"reset"}
{"type":"quit"}
```

## 3. 响应（后端 → 前端）

### 3.1 `result`

```json
{"ok":true,"stack":["3"],"type":"result"}
{"code":20,"error":"未知的词：nope","ok":false,"type":"result"}
{"id":7,"ok":true,"stack":["3"],"type":"result"}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `type` | string | 恒为 `"result"` |
| `ok` | bool | 是否成功 |
| `stack` | array[string] | 成功时：求值后剩余数据栈，**已渲染文本**（前端只显示，不再解析） |
| `code` | int | 失败时：REQ-23 分级码 |
| `error` | string | 失败时：人类可读消息（中文） |
| `id` | any | 仅当请求带 `id` 时出现 |

### 3.2 `chunk`（REQ-08：块到达即 flush）

```json
{"n":0,"stream":"c","text":"ab","type":"chunk"}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `stream` | string | 流的标签（`send`/`resend`/`bcast` 的目标 agent 标签） |
| `n` | int | 该流的块序号，**从 0 起连续**（前端据此排序/去重） |
| `text` | string | 本块文本（UTF-8，不切坏多字节字符） |

### 3.3 `close`

```json
{"ok":true,"stream":"c","type":"close"}
```

一轮输出结束（对应方言的 `@Close`）。`ok:false` 表示该流失败（前端应显示错误，
但**本轮其他流仍会继续**）。`watch` 出来的视图流**不会**发 `close`（它是常驻观察者）。

### 3.4 `event`（REQ-48 / 附录 F）

```json
{"name":"@Toolcall","stream":"c","text":"add2 {\"a\":40}","type":"event"}
```

后端在流里遇到需要前端/用户介入的钩子事件时立刻推一条。v1 只推 **`@Toolcall`**
（模型发起的工具调用；其余事件已有 `chunk`/`close` 覆盖，重复推只会让前端双计）。

| 字段 | 类型 | 说明 |
|---|---|---|
| `type` | string | 恒为 `"event"` |
| `name` | string | 事件名，v1 恒为 `"@Toolcall"` |
| `stream` | string | 该事件所属流的标签 |
| `text` | string | `<工具名> <参数 JSON 文本>`，人类可读 |

自动执行 = `@Toolcall` 的**默认钩子**：工具跑完、结果以 `role:"tool"` 追加，
**同一条流继续吐文本**。`@off @Toolcall` 之后事件照样推给前端，但工具不跑，
流停在「待外部动作」—— 本轮不触发 `@RoundDone`，前端需自己 `invoke` + `append` + `resend` 接管。

### 3.5 `pong` / `hello` / `bye`

```json
{"protocol":1,"type":"pong"}
{"protocol":1,"type":"hello","version":"ravel breve 1.0e · janet 1.42.1"}
{"protocol":1,"type":"bye"}
```

`protocol` = 协议版本（本文件 = 1）。`hello` 是可选的握手，前端可据此拒绝不兼容后端。

## 4. 语义约定

1. **工作区 = 字典 + 栈**（REQ-30 / REQ-42）：跨请求保留；`reset` 才清空。
2. **一次请求 = 一次求值 = 一轮**：结束时触发 `@RoundDone`，默认钩子把本轮各
   stream 的文本并入对应 agent 会话（REQ-18）。
3. **双向不阻塞**（REQ-24）：后端读完一行就处理，不等待前一条流结束；
   求值过程中产生的 `chunk` 立即写出。
4. **视图推送**（REQ-28）：被 `watch` 的 agent，其会话新增条目在**每次请求处理完后**
   （以及每次求值间隙）以 `chunk` 推出，`stream` 字段 = 该 agent 标签。
   每次推送至多 64 块，宁可下一轮再推，也不让输入饿死。
5. **方言输出不进 stdout**：`print`/`show` 写 stderr；要展示数据请用 `stack`/`watch`。
6. **工具调用**（REQ-48）：模型发起的调用 → `event` 消息（3.4）；默认钩子自动执行并
   让**同一条流**继续，前端仍然只看到一条回复的 `chunk` 序列。
7. **元命令不在协议里**（REQ-25）：`quit`/`exit`/`help`/`clear` 是**前端**的命令表。
   前端把它翻译成协议请求（如 `clear` → `{"type":"reset"}`），后端只认第 2 节的请求。

## 5. 一次会话的样子

请求（stdin）：

```
agent "c" { }
watch
swap
send say "hi"
{"type":"eval","src":"1","id":3}
{"type":"quit"}
```

响应（stdout，已按行略去长栈内容）：

```json
{"ok":true,"stack":["@{:kind :agent :label \"c\" …}"],"type":"result"}
{"ok":true,"stack":["@{:chunks 0 … :watch true}"],"type":"result"}
{"n":0,"stream":"c","text":"ab","type":"chunk"}
{"n":1,"stream":"c","text":"cd","type":"chunk"}
{"ok":true,"stream":"c","type":"close"}
{"ok":true,"stack":["…"],"type":"result"}
{"n":0,"stream":"c","text":"@{:content \"hi\" :role \"user\"}","type":"chunk"}
{"n":1,"stream":"c","text":"@{:content \"…\" :role \"assistant\"}","type":"chunk"}
{"id":3,"ok":true,"stack":["…","…","1"],"type":"result"}
{"protocol":1,"type":"bye"}
```

注意：`{"type":"eval"…}` 是在**流还在推**的时候被处理的——这就是 REQ-24 的验收点。

## 6. 未纳入 v1（明确的「不做」）

| 项 | 原因 | 记录 |
|---|---|---|
| `cancel` 请求 | 语义未定（`unsubscribe` 已占用一个名字，REQ-09；v1.0d 的 `subscribe` 是**词**不是请求） | SF-20 / SF-22 |
| 背压协商 | 视图推送用固定上限（64 块/轮）代替 | SF-22 |
| 错误对象细分（行列号/源码片段） | 现有 `code` + `error` 足够驱动前端提示 | SF-22 |
| 多会话/多工作区并发 | REQ-42 限定单工作区串行 | — |

## 7. 版本

- 协议版本：`1`（本文）。
- 实现版本串：`ravel breve <spec> · janet <ver>`（`ravel -v`，`hello.version`）。
- 变更规则：任何字段增删/语义变更 → 升 `protocol`；只增可选字段且旧客户端可忽略 → 不升版但改本文。
