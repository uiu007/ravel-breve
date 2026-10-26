#!/usr/bin/env bash
# 20 截断与空转：同一轮里续写（REQ-70 / D-76）
#
# 离线跑法：RB_LLM=mock ./examples/20-continue.sh
#
# 病根：推理型模型把 `max_tokens` 全花在 `reasoning_content` 上，正文一个字没有，
# `finish_reason = "length"`。v1.0p 及以前，本仓把它当"说完了"——一轮静默结束
# （用户看到的是"跑了几分钟什么都没写"）。
#
# v1.0q 起，能力层每次响应收尾时交一块 `@{:finish reason :chars n :calls n}`，
# 编排层据此在**同一轮**里续写。mock 用两个环境变量把这件事做成确定序列：
#   RB_MOCK_FINISH=length,stop  → 第 1 次响应报截断，第 2 次正常
#   RB_MOCK_EMPTY=1,0           → 第 1 次响应正文为空
cd "$(dirname "$0")/.." || exit 1
export RB_LLM=mock
export RB_CONFIG=-
fail=0

echo '-- 1) 正常收尾：一次说完，不续写'
RB_MOCK_REPLY='写完了。' ./bin/ravel -e 'agent "c" { }
send say "写个 README"
drain' || fail=1
echo

echo '-- 2) 第一次被截断 → 自动续写一次（两段正文接在一起）'
RB_MOCK_FINISH=length,stop RB_MOCK_REPLY='写完了。' ./bin/ravel -e 'agent "c" { }
send say "写个 README"
drain' || fail=1
echo

echo '-- 3) 空转（正文 0 字）→ 也续写'
RB_MOCK_EMPTY=1,0 RB_MOCK_REPLY='写完了。' ./bin/ravel -e 'agent "c" { }
send say "写个 README"
drain' || fail=1
echo

echo '-- 4) 一直空转：续到上限就 60，并点名退路（故意取反：这里期望非零）'
set +e
RB_MOCK_EMPTY=1 RB_MOCK_REPLY='写完了。' ./bin/ravel -e 'agent "c" { }
send say "写个 README"
drain' 2>&1 | sed 's/^/   /'
rc=${PIPESTATUS[0]}
set -e
echo "   退出码：$rc"
[ "$rc" -eq 60 ] || fail=1

echo
echo '-- 5) RB_CONTINUE_MAX=0 关掉自动续写（回到 v1.0p 的行为）'
RB_CONTINUE_MAX=0 RB_MOCK_FINISH=length RB_MOCK_REPLY='写完了。' ./bin/ravel -e 'agent "c" { }
send say "写个 README"
drain' || fail=1

echo
if [ "$fail" -eq 0 ]; then
  echo '例程 20：全部符合预期'
else
  echo '例程 20：有不符合预期的步骤'
fi
exit "$fail"
