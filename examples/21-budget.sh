#!/usr/bin/env bash
# 21 输出预算：按 pi 的口径算额度（REQ-71 / D-77）
#
# 离线跑法：./examples/21-budget.sh（`llm-get` 不联网）
#
# v1.0q 及以前，每请求的 `max_tokens` 是写死的 8192（配置里甚至是 1024）。
# 推理型模型的 `reasoning_content` **也算在** completion tokens 里，于是任务一重，
# 预算全被思考吃掉，正文一个字都出不来（20 号例程里那串续写就是这么来的）。
#
# pi agent 不发常数，它发
#   clampMaxTokensToContext(model, context, 想要的额度)
#     = min(想要的额度, max(1, 上下文窗口 - 估算输入 - 4096))
# 对 `deepseek-v4.1-flash` 就是 384000（模型目录里 1e6 上下文 / 384000 输出）。
# v1.0r 照抄这套：显式配置 > 模型目录的上限 > 兜底 16384，再按上下文余量夹紧。
cd "$(dirname "$0")/.." || exit 1
export RB_CONFIG=-
fail=0

echo '-- 1) 模型目录外的模型：兜底 16384（够推理用的大值）'
RB_LLM=mock ./bin/ravel -e 'llm-get "max-tokens"' || fail=1
echo

echo '-- 2) 目录里的模型：直接用它的上限（deepseek-v4.1-flash → 384000）'
RB_LLM=opencode ./bin/ravel -e 'llm-get "max-tokens"' || fail=1
echo

echo '-- 3) 显式配置压过目录（RB_MAX_TOKENS=16000），但仍会按上下文夹紧'
RB_LLM=opencode RB_MAX_TOKENS=16000 ./bin/ravel -e 'llm-get "max-tokens"' || fail=1
echo

echo '-- 4) 额度**真的用完**（out >= max）→ 立刻 60，不再空转三轮（故意取反：期望非零）'
set +e
RB_LLM=mock RB_MAX_TOKENS=1 RB_MOCK_FINISH=length RB_MOCK_REPLY='写完了。' ./bin/ravel -e 'agent "c" { }
send say "写个 README"
drain' 2>&1 | sed 's/^/   /'
rc=${PIPESTATUS[0]}
set -e
echo "   退出码：$rc"
[ "$rc" -eq 60 ] || fail=1

echo
echo '-- 5) 同样的截断，但额度够大（out < max）→ 可恢复，照旧续写'
RB_LLM=mock RB_MAX_TOKENS=100000 RB_MOCK_FINISH=length,stop RB_MOCK_REPLY='写完了。' ./bin/ravel -e 'agent "c" { }
send say "写个 README"
drain' || fail=1

echo
if [ "$fail" -eq 0 ]; then
  echo '例程 21：全部符合预期'
else
  echo '例程 21：有不符合预期的步骤'
fi
exit "$fail"
