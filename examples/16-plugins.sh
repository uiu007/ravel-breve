#!/usr/bin/env bash
# examples/16-plugins.sh —— 插件：装 / 用 / 卸（REQ-60 / v1.0j）
#
# 一个文件 = 一轮 = 一份源，而转译在求值前就做完了，所以**同一份源里**
# 用不到刚装的词。REPL 里一行 = 一轮，于是「装了再用」天然是两步——
# 这正是插件词的正确用法（和用户手打的定义一样）。
#
# 跑法（hermetic）：RB_LLM=mock ./bin/ravel "$(cat …)" 或直接跑本脚本。
set -u
cd "$(dirname "$0")/.." || exit 1
export RB_LLM=mock

# 一行 = 一轮；REPL 会把该轮栈里的值回显出来，不必再 `show`
printf '%s\n' \
  'plug "skills/ravel-breve-plugin/plugin.breve"' \
  'pop' \
  'plugins' \
  'pop' \
  'sum2 40 2' \
  'pop' \
  'invoke "sum" H{ "a" 40 "b" 2 }' \
  'pop' \
  'unplug "plugin"' \
  'pop' \
  'plugins' \
  | ./bin/ravel || exit 1
