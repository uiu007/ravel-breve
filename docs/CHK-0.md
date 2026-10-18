# CHK-0 评审材料（M0 · 环境与构建骨架）

**结论**：M0 达成。构建可复现、版本已钉死、退出码分级已落地、主脊（M1 内容）已一并打通并全绿。
本检查点是**硬闸门**：请裁决下方「待裁决」后再进入 M1 收尾/M2。

---

## 1. 一键验收（实测输出）

```sh
make clean && make
make test
./bin/ravel -v
./bin/ravel --dump -e 'take 2 "abcde"'
./bin/ravel -e 'take 2 "abcde"'
```

实测：

```
ravel breve 1.0b · janet 1.42.1
(do (rb/push "abcde") (rb/push 2) (rb/take))     ← 与 REQ-31 示例逐字一致
"ab"
```

```
测试：60  通过：60  失败：0
端到端：通过 21，失败 0
core-only: 通过（核心可独立装载并完成主脊）
```

| 层 | 数量 | 命令 |
|---|---|---|
| 单元（词法/转译） | 17 | `make test-unit` |
| 符合性（REQ-01/03/04/05/23/30/31/37） | 43 | 同上 |
| 端到端（真二进制、真退出码、REPL/--serve 管道） | 21 | `make test-e2e` |
| 附录 D（剔除 `cap/` 后核心独立可用） | 1 | `make test-core-only` |
| vendor 校验 | — | `make check-vendor` |

## 2. 交付物

| 项 | 位置 |
|---|---|
| 宿主 vendor（钉版本 + sha256） | `vendor/janet/{janet.c,janet.h,shell.c,VERSION}`（1.42.1，commit `e1963cd`） |
| 宿主入口 | `src/main.c`（`janet_init` → 嵌入 bundle → CLI → 退出码） |
| 方言核心 | `rb/`：`lexer` `translate` `runtime` `cap` `dict` `words/l0,l1,l1b,l5b` `eval` `cli` `init` |
| 能力层 | `cap/json.janet`（可整目录剔除） |
| 装载顺序契约 | `rb/MANIFEST`（`cap/` 前缀行 = 可剔除能力层） |
| 构建 | `Makefile`、`tools/embed.janet`（MANIFEST → `rb-bundle.janet` + `rb_bundle.c`） |
| 测试 | `tests/{harness,run,runner}.janet`、`tests/unit`、`tests/conformance`、`tests/e2e` |
| 文档 | `README.md`、`docs/{CONFORMANCE,DECISIONS,PROTOCOL,SPEC-FEEDBACK}.md` |
| 版本控制 | `RavelBreve/` 内独立 git，提交 `9e61fb5`，tag `m0` |

## 3. 本轮修复：`--serve` 挂起（根因）

用户观察到 `printf '…' | ./bin/ravel --serve` **长时间不返回**。根因两条，均已修复并加回归：

1. **EOF 判断错**：Janet `getline` 在 EOF 返回**空 buffer**（不是 `nil`），原 `while` 等 `nil` → 空转不退出。
   现以「空输入 = EOF」退出（`rb/cli.janet`，REPL 与 `--serve` 同一处理）。
2. **环境条目形态误判**：Janet 1.42 的环境条目是**绑定表**（`janet_def` → `@{:value v}`），
   原动态查词拿到的总是表而非值，能力层查拔因此静默失效（`(nil x)` 在 Janet 里是「查表」不是「调用报错」，把 bug 掩盖了）。
   现统一用 `rb/env-get` 解包，并引入显式能力注册表 `rb/cap`。

回归：`tests/e2e/cli.sh` 的 REPL/`--serve` 管道用例（EOF 必须退出）+ `req-30` 栈隔离 + `req-37` 能力层。
实测 `--serve` 现为 5ms 内退出、逐行一响应：

```
$ printf '\ntake 2 "abcde"\nf : [ * 2 ]\nf 21\n\nnope\n' | ./bin/ravel --serve
{"ok":true,"stack":["\"ab\""],"type":"result"}
{"ok":true,"stack":[],"type":"result"}
{"ok":true,"stack":["42"],"type":"result"}
{"code":20,"error":"未知的词：nope","ok":false,"type":"result"}
```

---

## 4. 待裁决（CHK-0）

### 4.1 原计划的四问（**已按默认执行，请追认或改判**）

| # | 问题 | 默认（已执行） |
|---|---|---|
| 1 | 是否允许 vendor Janet 源码进仓库（~1.5MB）？ | **vendor 进仓库**，`make check-vendor` 校验 sha256 |
| 2 | 是否在 `RavelBreve/` 内独立 `git init` + 按阶段打 tag？ | **是**（未触碰父目录 `/home/uiu` 的 git），tag `m0` |
| 3 | Janet 钉 `1.42.0` 还是 `1.42.x` 最新补丁？ | **1.42.1**（`vendor/janet/VERSION` 记 commit + sha256） |
| 4 | 文档与提交信息用中文？ | **中文** |

### 4.2 顺带需要裁决的实现决策（详见 `docs/DECISIONS.md`）

| 编号 | 议题 | 本实现 | 影响 |
|---|---|---|---|
| SF-01 | REQ-05 验收写 `3 3 =` 得 `true`，与 REQ-01 镜像规则**矛盾**（按镜像必栈下溢） | 按镜像执行：`= 3 3` → `true`；`3 3 =` → 30 | **建议修订规格**（改 REQ-05 验收为 `= 3 3`） |
| D-02 | 注释语法未规定 | `#` 至行末 | 小 |
| D-03 | **多行块内换行的语义**未规定 | 块内换行 = 语句分隔，逐语句反转、语句间保持书写序 | 中（影响所有多行块） |
| D-04 | 比较/取用的实参次序未规定 | 统一「最左实参 = 栈顶 = 先消费」：`< 5 3` → `false` | 中 |
| D-05 | REQ-23 只给区间，未给具体码 | 已给满（10/11/12/20/21/22/23/30/31/32/33/40/41/50/51/60/70+） | 小 |
| D-12 | `{ }` / `H{ }` 字面量 | **延后到 M2**（M0 只有引号块 `[ ]`） | 小（已记入 CONFORMANCE） |
| D-06 | `--serve` 下「栈逐请求隔离、字典全局」 | 是 | 待 CHK-5 与协议一起冻结 |

### 4.3 请确认的下一步

1. CHK-0 四问（4.1）是否照默认执行？
2. SF-01 是否同意修订 REQ-05 验收标准（`3 3 =` → `= 3 3`）？
3. D-03 / D-04 两条语义（多行块、实参次序）是否照本实现冻结？
4. 是否直接进入 **M2（词表 L0–L5：REQ-06…REQ-11、REQ-25、REQ-32）**？
   （M1 的验收测试已随 M0 落地，剩余只是上述裁决确认。）
