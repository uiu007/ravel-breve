# CHK-6 · M6 验收（v1.0d「agent 的基本能力」）

规格：`ravel-breve-spec-v1.0d.md`（v1.0c → v1.0d 的差异见其**附录 H**）。
本检查点**只补能力**，不改语法 / 执行模型 / 状态模型 / 协议骨架（§0）。

## 1. 交付了什么

| REQ | 能力 | 实现落点 |
|---|---|---|
| REQ-47 | 角色只是 `Utter` 的字段；`saysys` 糖 | `rb/words/l2.janet`（`saysys` / `Utter`），会话无新类型 |
| REQ-48 | 工具调用 `deftool` / `invoke` / `@Toolcall` / 同一条流继续 | `rb/tools.janet`、`rb/agent.janet`、`rb/words/l8.janet`、`cap/nvidia.janet`、`cap/mock.janet` |
| REQ-49 | 重试在钩子层；`resend` 接受 Agent 或 Stream | `rb/words/l3.janet`、`rb/round.janet` |
| REQ-50 | 上下文压缩在钩子层（核心不内置算法） | 无新代码：`take` + `saysys` + `agent` 组合（D-49） |
| REQ-51 | 编排边 `->` / `onfail` / `subscribe` | `rb/words/l4.janet`、`rb/round.janet` |

新增方言词 6 个：`saysys` `subscribe` `->` `onfail` `deftool` `invoke`（另 `resend` 扩为接受 Stream）。

## 2. 验收

```
make test        → 326 单元/符合性 + 94 端到端 + 11 例程 + core-only 全绿
make test-agent  → 真 NVIDIA 14 / 0
```

- 符合性：`tests/conformance/req-47-51-capabilities.janet`（五条 REQ 逐条）
- 协议：`event` 消息（附录 F / `docs/PROTOCOL.md` 3.4）由 `e2e/cli.sh` 断言
- 附录 D：`--core-only` 不依赖任何 `cap/`（工具调用在核心内，provider 能力在能力层）

## 3. 需要你追认的判断（都有明文与关闭手段）

1. **工具调用不开新流**（D-45）：会话四段 `user / assistant(tool_calls) / tool / assistant`，
   前端只看到一条回复的 `chunk` 序列。
2. **工具中断 = 状态 `:tool`**（D-46）：流冻结不 close；`drain` 报 60，本轮不触发 `@RoundDone`；
   接管方式 = `invoke` + `append` + `resend`。
3. **重试只靠钩子**（D-48）：没装 `@Fail` 钩子 → 失败就是失败，**不静默重试**。
4. **压缩策略在用户侧**（D-49）：核心只给零件，不内置算法。
5. **`subscribe` 推翻 D-44**：与 `unsubscribe` 是一对反义动词，符合 REQ-09。

打磨项已收（D-50）：`at` 的下标类型、能力调用失败的分级码、`rb/render` 的定值输出。

## 4. 仍未定（等你裁决，不阻塞）

| 项 | 记录 |
|---|---|
| `seq` / `par` 的栈效应、结果、`par` 的并发语义 | SF-25（当前报 20「未知的词」） |
| `agent` 的第三个引号 `behavior` 仍无定义 | SF-26（接受并存储，但不执行） |
| `session` 的实参：spec 写 `Workspace -- Session`，实现为 `Agent -- Session` | SF-27（建议改 spec） |
| `Json` 只有类型名、没有词义 | SF-28（当前报 20，测试显式断言） |

