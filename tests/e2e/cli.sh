#!/usr/bin/env bash
# tests/e2e/cli.sh —— CLI 端到端验收（REQ-22 / REQ-23 / REQ-24 / REQ-31）
set -uo pipefail

RAVEL=./bin/ravel
export RB_LLM="${RB_LLM:-mock}"          # 端到端测试一律离线（M3）
export RB_MOCK_REPLY="${RB_MOCK_REPLY:-abcdefgh}"
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

check_has() { # check_has <说明> <期望子串> <文件>
  if grep -qF -- "$2" "$3"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf '  ✗ %s\n     期望包含: %s\n     实际: %s\n' "$1" "$2" "$(cat "$3")"
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

# M3：agent / 流 / 钩子（离线 provider）
check_rc "agent：建 agent 并压栈" 0 $RAVEL -e 'agent "c" { }'
check "agent：渲染形态" \
      '@{:kind :agent :label "c" :live true :origin () :session @[] :turn 0}' \
      "$(cat /tmp/rb-e2e-out)"
# 一轮结束时默认钩子才把回复并回会话（REQ-18）→ 用 --serve 跨两行观察
check_rc "agent：send + 收尾钩子自动合并" 0 bash -c "printf 'agent \"c\" { }\ndup\nsend say \"hi\"\npop\nsession\n' | $RAVEL --serve"
check_has "agent：会话含用户消息与回复" \
      '@[@{:content \"hi\" :role \"user\"} @{:content \"abcdefgh\" :role \"assistant\"}]' \
      /tmp/rb-e2e-out
check_rc "agent：@off @RoundDone 关闭自动合并" 0 $RAVEL -e 'agent "c" { }
@off @RoundDone
dup
send say "hi"
utter
append
session'
check "agent：手动路径也能合并（REQ-19/46）" \
      '@[@{:content "hi" :role "user"} @{:content "abcdefgh" :role "assistant"}]' \
      "$(cat /tmp/rb-e2e-out)"
check_rc "流：drain 得到全文" 0 $RAVEL -e 'agent "c" { }
@off @RoundDone
send say "问"
drain'
check "流：drain 输出" '"abcdefgh"' "$(cat /tmp/rb-e2e-out)"
check_rc "钩子：@on @Chunk 逐块观察" 0 $RAVEL -e 'agent "c" { }
@on @Chunk [ show ]
send say "问"
drain'
check "钩子：四块都观察到了" 'ab cd ef gh' \
      "$(grep -v '"abcdefgh"' /tmp/rb-e2e-out | tr -d '\n' | sed 's/"//g' | sed 's/\(..\)/\1 /g; s/ $//')"
check_rc "渲染：中文不转义" 0 $RAVEL -e '"你好"'
check "渲染：保留 UTF-8（D-32）" '"你好"' "$(cat /tmp/rb-e2e-out)"
check_rc "流：未知事件名 → 20" 20 $RAVEL -e '@on @Nope [ 1 ]'

echo "端到端：通过 $pass，失败 $fail"
[ "$fail" -eq 0 ]
