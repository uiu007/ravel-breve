#!/usr/bin/env bash
# examples/18-modes.sh —— 处理流程模式（REQ-65 / REQ-66，v1.0m）
#
# 五个预制模式里，四个是 DeepSeek harness 预置的复刻（dsh 的
# packages/bundle/web-app/presets/*.patch.yml）：
#
#   default   六个默认工具，没有系统提示（本仓缺省，v1.0f 行为不变）
#   standard  编码 agent 的人格 + 完整文件工具
#   ptc       wire 上只有 eval（模型提交程序），程序里 invoke 任何工具
#   minimal   只有 shell，人格就一句（不带运行时上下文）
#   cordis    standard + plugin（改自己）
#
# 两个要点：
#   ① **注册 ≠ 公示**：`:wire` 决定模型在请求里看得见谁；不在 wire 里的工具仍能 `invoke`。
#   ② **plan 正交**：enter-plan / exit-plan 只加提示与一个工具，不换模式。
#
# 本脚本 hermetic（mock provider，不联网）。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
export RB_LLM=mock
export RB_CONFIG=-
export RB_MOCK_REPLY=abcdefgh
R=./bin/ravel
T=build/tmp/ex18
mkdir -p "$T"
fail=0

step() { printf '\n-- %s --\n' "$1"; }
show() { "$@"; }

step "① 有哪些模式（CLI 只读查询，REQ-64）"
show $R --modes

step "② 五个名字（升序）"
show $R -e 'modes'

step "③ default：六个默认工具"
show $R -e 'mode-of
mode-tools'

step "④ minimal：只有 shell，提示就一句"
show $R -e 'mode "minimal"
mode-of
mode-tools'
show $R -e 'mode "minimal"
mode-of
mode-prompt
show'

step "⑤ minimal 下调 write → 60（它没装这个工具）"
show $R -e 'mode "minimal"
invoke "write" H{ "path" "build/tmp/ex18/nope.txt" "content" "x" }'
printf '   （退出码 %s，期望 60）\n' "$?"

step "⑥ ptc：七个工具注册着（含 eval）"
show $R -e 'mode "ptc"
mode-of
mode-tools'

step "⑦ 注册 ≠ 公示：ptc 的程序里 invoke glob 得到真实结果"
show $R -e 'mode "ptc"
invoke "eval" H{ "src" "invoke \"glob\" H{ \"pattern\" \"rb/MANIFEST\" }" }'

step "⑧ standard 的人格：mode-prompt 给的是**模板原文**（{{model}} / {{cwd}} 在 send 时现拼）"
show $R -e 'mode "standard"
mode-of
mode-prompt
show'
printf '   （真发出去的是替换过的版本；换模型/换目录立刻生效）\n'

step "⑨ cordis：standard + plugin（改自己）"
show $R -e 'mode "cordis"
mode-of
mode-tools'

step "⑩ plan 是正交开关：进 plan 不换模式"
show $R -e 'mode "standard"
enter-plan
mode-of
mode-name
show
flag "plan"
show'

step "⑪ exit_plan_mode：交计划并关掉开关"
show $R -e 'enter-plan
invoke "exit_plan_mode" H{ "plan" "# 计划\n\n1. 读 README" }
flag "plan"'

step "⑫ 手动出口 exit-plan（同 dsh 的 /plan off）"
show $R -e 'enter-plan
exit-plan
flag "plan"'

step "⑬ 不在 plan 时调 exit_plan_mode → 60"
show $R -e 'invoke "exit_plan_mode" H{ "plan" "# 计划" }'
printf '   （退出码 %s，期望 60）\n' "$?"

step "⑭ 两个新文件工具：read（带行号）与 write（原子替换）"
show $R -e 'invoke "write" H{ "path" "build/tmp/ex18/note.txt" "content" "alpha\nbeta\n" }'
show $R -e 'invoke "read" H{ "path" "build/tmp/ex18/note.txt" }'
show $R -e 'invoke "read" H{ "path" "build/tmp/ex18/note.txt" "offset" 2 }'

step "⑮ 模式的工具与设定自洽（REQ-67）：装好就能跑 shell，不用设环境变量"
show $R -e 'invoke "shell" H{ "cmd" "echo 开箱即用" }'

step "⑯ 关掉前置设定：wire 上少一个，invoke 报点名的 60（两行关掉法之二）"
show $R -e 'flag-set false "allow-shell"
invoke "shell" H{ "cmd" "echo hi" }'
printf '   （退出码 %s，期望 60）\n' "$?"
show env RB_ALLOW_SHELL=0 $R -e 'invoke "shell" H{ "cmd" "echo hi" }'
printf '   （退出码 %s，期望 60——环境变量压过模式设定）\n' "$?"

step "⑰ 模式往返：mode-of 的产物装回去，逐项相等"
show $R -e 'mode "cordis"
mode-of
mode
mode-of
mode-name
show'

printf '\n'
[ "$fail" -eq 0 ] || exit 1
