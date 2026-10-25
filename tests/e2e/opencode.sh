#!/usr/bin/env bash
# tests/e2e/opencode.sh —— 真 provider 端到端（OpenCode Zen / Go，D-64）
#
# 没有密钥就跳过（返回 0），保证离线环境也能跑 `make test`。
# 密钥查找顺序与 cap/config.janet 一致：
#   $OPENCODE_API_KEY → secrets/opencode.key → .opencode.key → ~/.config/ravel/opencode.key
#
# 注意：OpenCode 要求客户端**自带 User-Agent** 且带 `x-opencode-session`
# （一次会话一个稳定值），两者都在 cap/opencode.janet 里设好。
set -uo pipefail

RAVEL=./bin/ravel
pass=0
fail=0

have_key() {
  [ -n "${OPENCODE_API_KEY:-}" ] && return 0
  for f in secrets/opencode.key .opencode.key "$HOME/.config/ravel/opencode.key"; do
    [ -s "$f" ] && return 0
  done
  return 1
}

if ! have_key; then
  echo "端到端（OpenCode）：无密钥，跳过"
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

export RB_LLM=opencode
export RB_MODEL="${RB_MODEL:-deepseek-v4.1-flash}"

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
check_rc "真机：坏密钥 → 60（编排层）" 60 env OPENCODE_API_KEY=oc_sk_bad RB_LLM=opencode \
        $RAVEL -e 'agent "c" { }
send say "hi"
drain'

# ⑤b 上游的错误体是 JSON（`{"type":"error","error":{...}}`），必须报 60（D-56）
check_rc "真机：坏模型名 → 60（错误体）" 60 env RB_MODEL=不存在的模型 RB_LLM=opencode \
        $RAVEL -e 'agent "c" { }
send say "hi"
drain'

# ⑤c 用量记账（REQ-55）：一轮对话 calls 至少 1、total-tokens > 0
$RAVEL -e 'agent "c" { }
send say "只回答两个字：收到"
drain
usage' >/tmp/rb-oc-usage 2>&1
check "真机：usage 记账（退出码）" 0 "$?"
check "真机：calls >= 1 且 total-tokens > 0" "yes" \
      "$(grep -Eq '"calls\" [1-9]' /tmp/rb-oc-usage \
         && grep -Eq '"total-tokens\" [1-9]' /tmp/rb-oc-usage && echo yes || echo no)"

# ⑥ 工具调用（REQ-48）：真模型自己决定调 → 默认钩子执行 → 会话留下 tool 消息，
#    且工具跑完后同一条流继续吐出 assistant 文本。一次调用里同时验两件事。
deftool_src='deftool "add2" "把参数 a（整数）加 2" [ at "a"
to-int
+ 2 ]'
ask_src='请用 add2 工具计算 40 加 2，然后告诉我结果'
check_rc "真机：工具调用跑通" 0 $RAVEL -e "$deftool_src
agent \"c\" { }
dup
send say \"$ask_src\"
drain
pop
session
to-json"
check "真机：会话里留下 role=tool 的消息（REQ-48 ③）" "yes" \
      "$(grep -q '\\\"role\\\":\\\"tool\\\"' /tmp/rb-agent-out && echo yes || echo no)"
# 工具之后「同一条流继续吐文本」在 mock 里是确定性的（conformance/req-47-51）；
# 真模型偶发返回空 content，这里只提示、不计入失败。
grep -q '\\\"role\\\":\\\"assistant\\\"' /tmp/rb-agent-out \
  || printf '  · 提示：真模型本轮未给出工具后的文本（空 content），不影响工具链路\n'

# ⑦ 模型列表与自动配置（REQ-59）：真请求 /models，且能写回 model
check_rc "真机：llm-models" 0 bash -c "$RAVEL -e 'llm-models
len
show
llm-models
show' > /tmp/rb-oc-models 2>&1"
check "真机：列表非空（>= 1）" "yes" \
      "$(grep -Eq '^[1-9][0-9]*$' /tmp/rb-oc-models && echo yes || echo no)"
check "真机：列表里含当前模型" "yes" \
      "$(grep -qxF "\"$RB_MODEL\"" /tmp/rb-oc-models && echo yes || echo no)"
check_rc "真机：llm-auto 写回 model" 0 bash -c "$RAVEL -e 'llm-auto
show
llm-get \"model\"
show' > /tmp/rb-oc-auto 2>&1"
check "真机：llm-auto 与 llm-get 一致（已写回）" "yes" \
      "$([ "$(sed -n 1p /tmp/rb-oc-auto)" = "$(sed -n 2p /tmp/rb-oc-auto)" ] && echo yes || echo no)"

# ⑧ 自定义请求头（REQ-58）：能换内置头（请求照样通），也能覆盖 Authorization（于是被拒）
check_rc "真机：自定义 User-Agent 覆盖后仍能对话" 0 bash -c "$RAVEL -e 'llm-set H{ \"User-Agent\" \"my-agent/1\" } \"headers\"
agent \"c\" { }
send say \"只回答一个字：好\"
drain'"
check_nonempty "真机：覆盖 User-Agent 后仍有正文"
check_rc "真机：自定义会话头对拉模型列表也生效" 0 bash -c "$RAVEL -e 'llm-set H{ \"x-opencode-session\" \"rb-custom\" } \"headers\"
llm-models
len
show' > /tmp/rb-oc-hdr2 2>&1"
check "真机：列表仍非空" "yes" \
      "$(grep -Eq '^[1-9][0-9]*$' /tmp/rb-oc-hdr2 && echo yes || echo no)"
check_rc "真机：自定义 Authorization 真的进了请求（坏密钥 → 60）" 60 bash -c "$RAVEL -e 'llm-set H{ \"Authorization\" \"Bearer nope\" } \"headers\"
llm-models
pop' > /tmp/rb-oc-badauth 2>&1"


echo "端到端（真 provider）：通过 $pass，失败 $fail"
[ "$fail" -eq 0 ]
