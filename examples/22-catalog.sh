#!/usr/bin/env bash
# 22 模型目录：兜底、估算、自动更新（REQ-72 / D-78）
#
# 离线跑法：./examples/22-catalog.sh（全部走 mock provider，不联网）
#
# v1.0r 把额度交给「模型目录」，但目录里没有的模型怎么办？v1.0r 是兜底 32768。
# v1.0s 改成照抄 pi 的两个 `??`：
#   contextWindow ?? 128000
#   maxTokens     ?? 16384
# 有窗口，`clampMaxTokensToContext` 才对**所有**模型一个口径（不再"未知 = 不夹紧"）。
#
# 自动更新呢？pi 从 provider 的模型表读 mx；`GET /models` 只给名字、不给窗口与额度，
# 所以这里把"要不要自动更新"写成**一条钩子的启停**：
#   缺省不装；`@on @Start [ catalog-refresh ]` 才每轮开始刷一次；`@off @Start` 即关。
# 刷新只登记名字（`/models` 不报额度），额度仍按兜底走。
cd "$(dirname "$0")/.." || exit 1
export RB_CONFIG=-
fail=0

echo '-- 1) 目录外的模型：窗口 128000 / 额度 16384（pi 的两个 `??` 缺省）'
RB_LLM=mock ./bin/ravel -e 'llm-get "max-tokens"' || fail=1
RB_LLM=mock ./bin/ravel -e 'at "deepseek-v4.1-flash" catalog' || fail=1
echo

echo '-- 2) est 两种算法取大者：同样 8 个字，ASCII 值 2 个 token、汉字值 8 个（差 6）'
RB_LLM=mock RB_DEBUG_BUDGET=1 ./bin/ravel -e 'agent "c" { }
send say "abcdefgh"
drain' 2>&1 | grep 'BUDGET|' | sed 's/^/   /'
RB_LLM=mock RB_DEBUG_BUDGET=1 ./bin/ravel -e 'agent "c" { }
send say "你好世界你好世界"
drain' 2>&1 | grep 'BUDGET|' | sed 's/^/   /'
echo

echo '-- 3) 缺省不装钩子：跑一轮，目录不长'
RB_LLM=mock ./bin/ravel -e 'agent "c" { }
send say "hi"
drain
len catalog' || fail=1
echo

echo '-- 4) @on @Start [ catalog-refresh ]：每轮开始刷一次 → 多出 mock 这一条'
RB_LLM=mock ./bin/ravel -e '@on @Start [ catalog-refresh ]
agent "c" { }
send say "hi"
drain
len catalog' || fail=1
echo

echo '-- 5) @off @Start 之后再跑：又回到 3 条（自动与否是钩子的启停，不是缺省偏好）'
RB_LLM=mock ./bin/ravel -e '@on @Start [ catalog-refresh ]
@off @Start
agent "c" { }
send say "hi"
drain
len catalog' || fail=1
echo

if [ "$fail" -eq 0 ]; then echo '22 号例程：全部通过'; else echo '22 号例程：有失败'; fi
exit "$fail"
