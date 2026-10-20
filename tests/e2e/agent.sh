#!/usr/bin/env bash
# tests/e2e/agent.sh —— 真 provider 端到端（NVIDIA）
#
# 没有密钥就跳过（返回 0），保证离线环境也能跑 `make test`。
# 密钥查找顺序与 cap/config.janet 一致：
#   $NVIDIA_API_KEY → secrets/nvidia.key → .nvidia.key → ~/.config/ravel/nvidia.key
set -uo pipefail

RAVEL=./bin/ravel
pass=0
fail=0

have_key() {
  [ -n "${NVIDIA_API_KEY:-}" ] && return 0
  for f in secrets/nvidia.key .nvidia.key "$HOME/.config/ravel/nvidia.key"; do
    [ -s "$f" ] && return 0
  done
  return 1
}

if ! have_key; then
  echo "端到端（真 provider）：无 NVIDIA 密钥，跳过"
  exit 0
fi

check() { # check <说明> <期望> <实际>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf '  ✗ %s\n     期望: %s\n     实际: %s\n' "$1" "$2" "$3"
  fi
}

check_rc() { # check_rc <说明> <期望码> <命令...>
  local desc="$1" want="$2"; shift 2
  "$@" >/tmp/rb-agent-out 2>/tmp/rb-agent-err
  local got=$?
  check "$desc（退出码）" "$want" "$got"
}

check_nonempty() { # check_nonempty <说明>
  if [ -s /tmp/rb-agent-out ] && [ "$(cat /tmp/rb-agent-out)" != '""' ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf '  ✗ %s\n     输出为空或空串\n' "$1"
  fi
}

export RB_LLM=nvidia
export RB_MODEL="${RB_MODEL:-meta/llama-3.2-11b-vision-instruct}"

echo "== 真 provider 端到端（$RB_MODEL）=="

# ① 一次完整回合：send → 收尾钩子 → 会话里有 assistant 消息
check_rc "真机：一轮对话" 0 bash -c "printf 'agent \"c\" { }\ndup\nsend say \"用一句话说你好\"\npop\nsession\n' | $RAVEL --serve"
check "真机：会话含 assistant 消息" "yes" \
      "$(grep -q 'assistant' /tmp/rb-agent-out && echo yes || echo no)"
check "真机：--serve 返回 ok" "yes" \
      "$(grep -q '"ok":true' /tmp/rb-agent-out && echo yes || echo no)"

# ② drain 得到非空字符串
check_rc "真机：drain" 0 $RAVEL -e 'agent "c" { }
@off @RoundDone
send say "只回答一个数字：42"
drain'
check_nonempty "真机：drain 有内容"

# ③ 逐块取流（REQ-08/REQ-36）：至少一块非空
check_rc "真机：逐块取流" 0 $RAVEL -e 'agent "c" { }
@off @RoundDone
send say "数到三，用空格分隔"
dup
next
show
drain'
check_nonempty "真机：首块有内容"

# ④ 广播：两个 agent 各拿到一个流
check_rc "真机：广播两个 agent" 0 bash -c "printf 'agent \"a\" { }\nagent \"b\" { }\nbcast say \"说一个字\" { }\nlen\n' | $RAVEL --serve"
check "真机：广播产出流数量" "yes" \
      "$(grep -q '"ok":true' /tmp/rb-agent-out && echo yes || echo no)"

# ⑤ provider 报错（坏密钥）应转成编排层退出码 60（D-27）
check_rc "真机：坏密钥 → 60（编排层）" 60 env NVIDIA_API_KEY=sk-bad RB_LLM=nvidia \
        $RAVEL -e 'agent "c" { }
send say "hi"
drain'

echo "端到端（真 provider）：通过 $pass，失败 $fail"
[ "$fail" -eq 0 ]
