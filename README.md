# ravel breve

自右向左（RTL）求值的栈式 **agent 会话编排方言**，宿主为 Janet 1.42.x（amalgamated，静态嵌入）。

- 命令：`ravel`，脚本扩展名 `.breve`，提示符 `ravel> `
- 规格：`ravel-breve-spec-v1.0b.md`（**只读**；修订提案写 `docs/SPEC-FEEDBACK.md`）
- 开发计划与检查点：`PLAN.md`

## 构建与验收

```sh
make                 # 构建 bin/ravel（vendor/janet 静态嵌入）
make test            # 单元 + 符合性 + 端到端 + 附录 D（core-only）
make check-vendor    # 校验 vendor/janet 的 sha256
```

M0 验收（CHK-0）：

```sh
make clean && make
./bin/ravel -v                        # ravel breve 1.0b · janet 1.42.1
./bin/ravel --dump -e 'take 2 "abcde"' # (do (rb/push "abcde") (rb/push 2) (rb/take))
./bin/ravel -e 'take 2 "abcde"'        # "ab"
```

## 用法

```sh
ravel                       # REPL（栈跨行保留）
ravel -e '<一行>'            # 求值一行并打印剩余栈
ravel script.breve          # 执行脚本
ravel --serve               # NDJSON over stdio（前后端分离，REQ-24）
ravel --dump ...            # 打印转译产物（REQ-31）
ravel -v | -h
```

## 方言要点

```breve
take 2 "abcde"        # ≡ "abcde" 2 take  →  "ab"
- 5 3                 # ≡ 5 - 3          →  2
= 3 3                 # →  true
double : [ * 2 ]      # 定义行（元层，不参与镜像）
double 5              # →  10
apply [ * 2 ] 21      # 引号压栈即数据，由组合子触发 → 42
```

规则：**写下的顺序 = 求值的顺序**（左 = 先消费 = 栈顶）。实现走**镜像原理**：
`切词 → 递归反转 → 换名 → 宿主求值`，无字节码、无自研 VM（REQ-02）。

## 目录

```
vendor/janet/     janet 1.42.1 amalgam（VERSION 记录 sha256）
src/main.c        宿主入口：嵌入 bundle、启动 CLI、返回退出码
rb/               方言核心（随宿主静态嵌入；rb/MANIFEST 决定装载顺序）
cap/              能力层（可整目录剔除；核心不静态依赖，REQ-37）
tools/embed.janet 由 MANIFEST 生成 build/rb-bundle.janet 与 build/rb_bundle.c
tests/            unit / conformance / e2e（+ 附录 D 的 core-only 验收）
docs/             符合性矩阵、决策记录、协议草案、规格反馈
```

## 文档

| 文件 | 内容 |
|---|---|
| `docs/CONFORMANCE.md` | REQ ↔ 测试矩阵（每条 REQ 的可执行验收） |
| `docs/DECISIONS.md` | 规格未冻结处的实现决策（D-xx） |
| `docs/PROTOCOL.md` | NDJSON over stdio 协议草案（CHK-5 冻结） |
| `docs/SPEC-FEEDBACK.md` | 规格缺陷与待裁决项（CHK-1…CHK-6） |
