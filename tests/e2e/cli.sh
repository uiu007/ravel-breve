#!/usr/bin/env bash
# tests/e2e/cli.sh —— CLI 端到端验收（REQ-22 / REQ-23 / REQ-24 / REQ-31）
set -uo pipefail

RAVEL=./bin/ravel
pass=0
fail=0

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
  "$@" >/tmp/rb-e2e-out 2>/tmp/rb-e2e-err
  local got=$?
  check "$desc（退出码）" "$want" "$got"
}

echo "== CLI 端到端 =="

check_rc "版本" 0 $RAVEL -v
check "版本输出含方言名" "yes" "$(grep -q 'ravel breve' /tmp/rb-e2e-out && echo yes || echo no)"

check_rc "求值一行" 0 $RAVEL -e 'take 2 "abcde"'
check "-e 打印剩余栈" '"ab"' "$(cat /tmp/rb-e2e-out)"

check_rc "dump 转译产物" 0 $RAVEL --dump -e 'take 2 "abcde"'
check "--dump 首行是宿主序（REQ-31）" \
      '(do (rb/push "abcde") (rb/push 2) (rb/take))' "$(head -1 /tmp/rb-e2e-out)"

check_rc "脚本文件" 0 $RAVEL tests/e2e/hello.breve
check "脚本输出" '"hello"' "$(cat /tmp/rb-e2e-out)"

check_rc "未知词 → 20" 20 $RAVEL -e 'nope'
check_rc "栈下溢 → 30" 30 $RAVEL -e 'pop'
check_rc "未闭合块 → 11" 11 $RAVEL tests/e2e/unclosed.breve
check_rc "文件不存在 → 40" 40 $RAVEL /tmp/__no_such_file__.breve
check_rc "未知选项 → 2" 2 $RAVEL -x
check_rc "帮助" 0 $RAVEL -h

# REPL：管道输入，EOF 后退出
check_rc "REPL 管道" 0 bash -c "printf 'take 2 \"abcde\"\n' | $RAVEL"
check "REPL 输出栈" '"ab"' \
      "$(printf 'take 2 "abcde"\n' | $RAVEL | sed 's/^ravel> //; s/^     > //' | grep -v '^$' | head -1)"

# --serve：NDJSON 一行请求一行响应，EOF 退出
check_rc "--serve" 0 bash -c "printf 'take 2 \"abcde\"\n' | $RAVEL --serve"
check "--serve 返回 JSON" \
      '{"ok":true,"stack":["\"ab\""],"type":"result"}' \
      "$(printf 'take 2 "abcde"\n' | $RAVEL --serve | head -1)"
check "--serve 首行栈" \
      '{"ok":true,"stack":["1"],"type":"result"}' \
      "$(printf '1\n2\n' | $RAVEL --serve | head -1)"
check "--serve 次行栈累积（REQ-42：栈是变量，跨请求保留）" \
      '{"ok":true,"stack":["1","2"],"type":"result"}' \
      "$(printf '1\n2\n' | $RAVEL --serve | tail -1)"
check "--serve 字典跨请求保留（REQ-42）" \
      '{"ok":true,"stack":["42"],"type":"result"}' \
      "$(printf 'f : [ * 2 ]\nf 21\n' | $RAVEL --serve | tail -1)"
check "--serve 错误带退出码" \
      '{"code":20,"error":"未知的词：nope","ok":false,"type":"result"}' \
      "$(printf 'nope\n' | $RAVEL --serve | head -1)"

echo "端到端：通过 $pass，失败 $fail"
[ "$fail" -eq 0 ]
