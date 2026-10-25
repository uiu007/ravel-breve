#!/usr/bin/env bash
# tools/oc-setup.sh —— 一条命令配好 OpenCode Go（REQ-62 / REQ-63）
#
# 干三件事，任何一步失败都停：
#   ① 存密钥：Secrets/opencode.key（chmod 600，已在 .gitignore；不进工作区、不进快照）
#   ② 存配置：一份预设 JSON（缺省写用户级 ~/.config/ravel/config.json，下次启动自动生效）
#   ③ 可选自检：拉一次模型列表
#
# 用法：
#   tools/oc-setup.sh <KEY>                    # 用户级配置（推荐）
#   tools/oc-setup.sh                          # 密钥从 OPENCODE_API_KEY 或 stdin 取
#   tools/oc-setup.sh --preset nvidia <KEY>    # 别的预设
#   tools/oc-setup.sh --local [路径] <KEY>     # 写仓库内（或指定）的预设文件
#   tools/oc-setup.sh --verify <KEY>           # 顺手拉一次模型列表验证
#   tools/oc-setup.sh --print                  # 只打印会做的事，不写盘
#   tools/oc-setup.sh --secrets <路径> <KEY>   # 密钥文件换个位置（测试用）
#
# 已存在的密钥**不覆盖**（要换就用 --force，换之前自动留一份 .bak）。
#
# 为什么密钥单独一个文件：预设里**永远不写密钥**（D-54 / REQ-62），
# 于是配置文件可以随便复制、提交、贴给别人，密钥不会跟着跑。

set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

PRESET="opencode-go"
MODE="user"        # user | local
LOCAL_PATH=""
KEY_PATH="secrets/opencode.key"
VERIFY=0
PRINT_ONLY=0
FORCE=0
KEY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --preset) PRESET="${2:-}"; shift 2 ;;
    --local)  MODE="local"; LOCAL_PATH="${2:-}"; shift 2 ;;
    --verify) VERIFY=1; shift ;;
    --secrets) KEY_PATH="${2:-}"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    --print)  PRINT_ONLY=1; shift ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "未知选项：$1" >&2; exit 2 ;;
    *)  KEY="$1"; shift ;;
  esac
done

[ -f "presets/$PRESET.json" ] || { echo "没有预设 presets/$PRESET.json" >&2; exit 2; }

# ---- ① 密钥 -------------------------------------------------------------
if [ -z "$KEY" ]; then
  if [ -n "${OPENCODE_API_KEY:-}" ]; then
    KEY="$OPENCODE_API_KEY"
  elif [ -t 0 ]; then
    printf 'OpenCode API key: ' >&2
    read -r -s KEY
    printf '\n' >&2
  else
    read -r KEY || true
  fi
fi
[ -n "$KEY" ] || { echo "没有密钥：给参数、设 OPENCODE_API_KEY、或用管道喂进来" >&2; exit 2; }

# ---- ② 配置去向 ---------------------------------------------------------
if [ "$MODE" = "local" ]; then
  TARGET="${LOCAL_PATH:-.ravel.json}"
else
  TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/ravel/config.json"
fi

echo "预设：    presets/$PRESET.json"
echo "密钥：    $KEY_PATH（chmod 600）"
echo "配置：    $TARGET"
if [ "$PRINT_ONLY" = "1" ]; then
  echo "（--print：什么都没写）"
  exit 0
fi

# 已有密钥就不动它：覆盖等于把别人手里的钥匙换掉，必须显式 --force
if [ -s "$KEY_PATH" ] && [ "$FORCE" != "1" ]; then
  echo "密钥已存在：$KEY_PATH（要换请加 --force，会先留一份 .bak）" >&2
else
  mkdir -p "$(dirname "$KEY_PATH")"
  if [ -s "$KEY_PATH" ]; then
    cp -p "$KEY_PATH" "$KEY_PATH.$(date +%Y%m%d%H%M%S).bak"
    echo "旧密钥已备份：$KEY_PATH.*.bak" >&2
  fi
  printf '%s\n' "$KEY" > "$KEY_PATH"
  chmod 600 "$KEY_PATH"
fi

mkdir -p "$(dirname "$TARGET")"
cp "presets/$PRESET.json" "$TARGET"
chmod 600 "$TARGET"

# ---- ③ 自检 -------------------------------------------------------------
if [ "$VERIFY" = "1" ]; then
  [ -x ./bin/ravel ] || make all >/dev/null
  echo "-- 拉一次模型列表 --"
  ./bin/ravel --preset "$PRESET" -e 'llm-models
show'
fi

cat <<EOF

好了。接下来：
  ./bin/ravel                                   # 直接 REPL（自动装载 $TARGET）
  ./bin/ravel -e 'agent "c" { }
send say "只说两个字：好的"
drain
show'
EOF
if [ "$MODE" = "local" ]; then
  echo "  本地预设要显式指路径：RB_CONFIG=$TARGET ./bin/ravel"
fi
