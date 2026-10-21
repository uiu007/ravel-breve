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

# --serve 协议 v1（REQ-24 / REQ-43 / 附录 F）
sr() { printf '%s\n' "$@" | $RAVEL --serve; }

check "协议：ping → pong" \
      '{"protocol":1,"type":"pong"}' \
      "$(sr '{"type":"ping"}' | head -1)"
check_has "协议：hello 报版本" '"version":"ravel breve' \
      <(sr '{"type":"hello"}')
check "协议：eval 回显 id" \
      '"id":7' \
      "$(sr '{"type":"eval","src":"1","id":7}' | head -1 | grep -o '"id":7')"
check "协议：reset 清栈清字典（REQ-42）" \
      '{"code":20,"error":"未知的词：f","ok":false,"type":"result"}' \
      "$(sr 'f : [ * 2 ]' '{"type":"reset"}' '{"type":"eval","src":"f 21"}' | tail -1)"
check "协议：方言 print/show 不污染 stdout（REQ-43）" \
      '{"ok":true,"stack":[],"type":"result"}' \
      "$(sr 'show { 1 2 }' 2>/dev/null | head -1)"
check "协议：方言 show 的输出走 stderr（逐元素）" \
      "$(printf '1\n2')" \
      "$(sr 'show { 1 2 }' 2>&1 >/dev/null)"
check "--serve：{ 1 2 } 是字面量源码不是 JSON 请求" \
      '{"ok":true,"stack":["(1 2)"],"type":"result"}' \
      "$(sr '{ 1 2 }' | head -1)"
check "协议：坏 JSON → 一条 code 2，服务不断（REQ-42）" \
      '{"ok":true,"stack":["1"],"type":"result"}' \
      "$(sr '{"type":' '1' | tail -1)"
check "协议：坏 JSON 只回一条错" \
      '{"code":2,"error":"请求不是合法 JSON：JSON 解析失败：意外的结束","ok":false,"type":"result"}' \
      "$(sr '{"type":' '1' | head -1)"
check "协议：未知请求类型 → code 2" \
      '"code":2' \
      "$(sr '{"type":"nope"}' | head -1 | grep -o '"code":2')"
check_rc "协议：quit 正常退出" 0 bash -c "printf '{"type":"quit"}\n{"type":"ping"}\n' | $RAVEL --serve"
check "协议：quit 之后不再处理（bye 是最后一行）" \
      '{"protocol":1,"type":"bye"}' \
      "$(sr '{"type":"quit"}' '1' | tail -1)"

# REQ-24 双向：推 stream 与收 eval 互不阻塞（同进程交织）
printf '%s\n' 'watch dup agent "c" { }' 'swap' 'send say "hi"' \
  '{"type":"eval","src":"1","id":3}' '{"type":"quit"}' > /tmp/rb-e2e-duplex
check_rc "REQ-24：watch + send + 再来一条请求" 0 $RAVEL --serve < /tmp/rb-e2e-duplex
check_has "REQ-24：求值过程中就有 chunk 推出" '{"n":0,"stream":"c","text":"ab","type":"chunk"}' /tmp/rb-e2e-out
check_has "REQ-24：close 带 stream 名与 ok" '{"ok":true,"stream":"c","type":"close"}' /tmp/rb-e2e-out
check_has "REQ-24：watch 视图把新会话条目推成 chunk" \
      '{"n":0,"stream":"c","text":"@{:content \"hi\" :role \"user\"}","type":"chunk"}' /tmp/rb-e2e-out
check "REQ-24：推流之后仍继续收请求（id 3 有结果）" \
      '3' \
      "$(grep -o '"id":3' /tmp/rb-e2e-out | head -1 | grep -o '3')"

# --json（REQ-22「输出 JSON」）
check_rc "--json 成功" 0 $RAVEL --json -e '+ 1 2'
check "--json 输出一条协议消息" \
      '{"ok":true,"stack":["3"],"type":"result"}' \
      "$(cat /tmp/rb-e2e-out)"
check_rc "--json 失败给分级码（REQ-23：失败不返回 0）" 20 $RAVEL --json -e 'nope'
check "--json 失败消息形状" \
      '{"code":20,"error":"未知的词：nope","ok":false,"type":"result"}' \
      "$(cat /tmp/rb-e2e-out)"

# REPL 元命令（REQ-25）与跨行栈（REQ-22）
check "REPL：栈跨行保留" \
      '2' \
      "$(printf '1\n2\ndepth\n' | $RAVEL 2>/dev/null | sed 's/ravel> //g' | grep -v '^$' | tail -1)"
check "REPL：clear 清栈（清完 depth 为 0）" \
      '0' \
      "$(printf '1\n2\nclear\ndepth\nquit\n' | $RAVEL 2>/dev/null | sed 's/ravel> //g' | grep -v '^$' | tail -1)"
check_rc "REPL：quit 退出 0" 0 bash -c "printf 'quit\n' | $RAVEL"
check_has "REPL：help 不退出" 'ravel> ' <(printf 'help\nquit\n' | $RAVEL 2>/dev/null)

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

echo "-- M4：持久化与工作区（REQ-20 / REQ-21）"
W=/tmp/rb-e2e-ws.json
rm -f "$W" "$W.log"
check_rc "工作区：跨进程保存" 0 $RAVEL -e "x : [ * 2 ]
save current \"$W\""
check "工作区：快照含 kind" "yes" \
      "$(grep -q 'ravel-workspace' "$W" && echo yes || echo no)"
check_rc "工作区：跨进程载入后字典可用" 0 bash -c "printf 'load \"%s\"\npop\nx 21\n' "$W" | $RAVEL --serve"
check "工作区：载入后确实算出 42" "yes" \
      "$(grep -q '42' /tmp/rb-e2e-out && echo yes || echo no)"
check "工作区：句柄渲染不递归" "yes" \
      "$(grep -q '#<workspace>' /tmp/rb-e2e-out && echo yes || echo no)"
check_rc "工作区：compact 显式调用" 0 $RAVEL -e "x : [ * 2 ]
save current \"$W\"
y : [ + 1 ]
compact current"
check "工作区：compact 后日志清空" "0" "$(wc -c < "$W.log" | tr -d ' ')"
check_rc "IO：write 写文件" 0 $RAVEL -e "write \"hi\" \"/tmp/rb-e2e.txt\""
check "IO：write 后内容就位" "hi" "$(cat /tmp/rb-e2e.txt)"
check_rc "IO：read 读回" 0 $RAVEL -e "read \"/tmp/rb-e2e.txt\""
check "IO：read 渲染" '"hi"' "$(cat /tmp/rb-e2e-out)"
check_rc "IO：读不存在 → 40" 40 $RAVEL -e "read \"/tmp/rb-e2e-nope.txt\""
check_rc "IO：载入不存在 → 40" 40 $RAVEL -e "load \"/tmp/rb-e2e-nope.json\""
check_rc "IO：写不进去 → 41" 41 $RAVEL -e "write \"x\" \"/proc/1/__nope/x\""
# 编排级 60 需要「核心无能力层」的构建：用只含核心的 bundle 跑同一条源码
check_rc "编排级：无能力层时 send → 60" 60 \
      build/janet -e '(each f (parse-all (slurp "build/core-only/rb-bundle.janet")) (eval f (curenv)))
                      (def r (rb/run-source "send say \"hi\" agent \"c\" { }" "t"))
                      (os/exit (if (r :ok) 0 (rb/error-code (r :error))))'
check_rc "工作区：save 非工作区 → 31" 31 $RAVEL -e "save H{ } \"/tmp/rb-e2e-x.json\""

echo "端到端：通过 $pass，失败 $fail"
[ "$fail" -eq 0 ]
