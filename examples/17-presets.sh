#!/usr/bin/env bash
# examples/17-presets.sh —— provider 配置预设（REQ-62 / REQ-63）
#
# 预设 = 一份 JSON，键就是工作区配置的键。三类用法：
#   ① 启动时：`--preset <名字>` / `RB_PRESET` / 用户配置文件（~/.config/ravel/config.json）
#   ② 运行中：`llm-import` / `llm-export`
#   ③ 一次性配好：tools/oc-setup.sh（存密钥 + 存配置）
#   ④ 先看有什么：`ravel --presets`（REQ-64）
#
# 本脚本 hermetic（不联网、不写用户家目录）：配置文件一律落在 build/tmp/。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
export RB_LLM=mock
export RB_CONFIG=-            # 先关掉用户配置文件，保证下面是可复现的
export RB_MOCK_REPLY=abcdefgh
R=./bin/ravel
T=build/tmp/ex17
mkdir -p "$T"
fail=0

step() { printf '\n-- %s --\n' "$1"; }
show() { "$@"; }

step "① 启动时一键导入：--preset opencode-go（只是读配置，不联网）"
show $R --preset opencode-go -e 'llm-get "provider"
show
llm-get "model"
show'

step "② 环境变量写法：RB_PRESET（逗号分隔，按序叠加）"
RB_PRESET=opencode-go show $R -e 'llm-get "max-tokens"
show'

step "③ 用户配置文件：存在就装，stderr 通报一行（REQ-63）"
printf '{"provider": "nvidia", "model": "meta/llama-3.2-11b-vision-instruct"}\n' > "$T/user.json"
RB_CONFIG="$T/user.json" show $R -e 'llm-get "provider"
show'

step "④ --no-config：这台机器上有用户配置，但这次不想用它"
RB_CONFIG="$T/user.json" show $R --no-config -e 'llm-get "provider"
show'

step "⑤ 运行中导入 / 导出：预设就是个可存可取的小文件"
show $R -e "llm-import \"opencode-go\"
llm-set 2048 \"max-tokens\"
llm-export \"$T/mine.json\"
show"
printf '   导出的文件：%s\n' "$T/mine.json"
cat "$T/mine.json"

step "⑥ 再导回来（往返一致）——换机器就靠这一步"
show $R --preset "$T/mine.json" -e 'llm-get "max-tokens"
show'

step "⑦ 密钥不进预设：导出时 headers 里有 Authorization 就拒绝（D-54）"
show $R -e "llm-set H{ \"Authorization\" \"Bearer sk-demo\" } \"headers\"
llm-export \"$T/leak.json\""
if [ -e "$T/leak.json" ]; then
  echo "  ✗ 不该留下文件：$T/leak.json"
  fail=$((fail + 1))
else
  echo "  ✓ 拒绝写盘，没留下文件"
fi

step "⑧ 拼错的配置项不会静默无效（31）"
show $R -e 'llm-import "opencode-go"
llm-set 1 "max-tokenss"'
echo "  退出码：$?（期望 31）"

step "⑨ 有哪些预设？—— ravel --presets（v1.0l / REQ-64）"
$R --presets
echo "  退出码：$?（期望 0）"

step "⑩ 名字打错也会告诉你有哪几份（不用翻仓库）"
$R --preset provier -e '1'
echo "  退出码：$?（期望 40）"

step "⑪ 有哪些处理流程模式？—— ravel --modes"
$R --modes
echo "  退出码：$?（期望 0）"

printf '\n例程：失败 %s 个\n' "$fail"
[ "$fail" -eq 0 ]
