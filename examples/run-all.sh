#!/usr/bin/env bash
# 跑一遍文档里的全部例程（hermetic：mock provider，不联网）
# 用法：./examples/run-all.sh        失败数 = 退出码
cd "$(dirname "$0")/.." || exit 1
export RB_LLM=mock
fail=0
for f in examples/[0-9]*.breve; do
  if timeout 120 ./bin/ravel "$f" >/tmp/rb-example.out 2>/tmp/rb-example.err; then
    printf '  ✓ %s\n' "$f"
  else
    printf '  ✗ %s（退出码 %s）\n' "$f" "$?"
    sed 's/^/      /' /tmp/rb-example.err
    fail=$((fail + 1))
  fi
done
for f in examples/[0-9]*.sh; do
  if timeout 120 "./$f" >/tmp/rb-example.out 2>/tmp/rb-example.err; then
    printf '  ✓ %s\n' "$f"
  else
    printf '  ✗ %s（退出码 %s）\n' "$f" "$?"
    sed 's/^/      /' /tmp/rb-example.err
    fail=$((fail + 1))
  fi
done
printf '例程：失败 %s 个\n' "$fail"
exit "$fail"
