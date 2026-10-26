#!/usr/bin/env bash
# tests/e2e/cli.sh —— CLI 端到端验收（REQ-22 / REQ-23 / REQ-24 / REQ-31）
set -uo pipefail

RAVEL=./bin/ravel
export RB_LLM="${RB_LLM:-mock}"          # 端到端测试一律离线（M3）
export RB_MOCK_REPLY="${RB_MOCK_REPLY:-abcdefgh}"
pass=0
fail=0
mkdir -p build/tmp                       # D-60：沙箱根 = 当前目录，写到仓库内才放行

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
      '{"n":0,"stream":"c","text":"@{:content \"hi\" :from \"c\" :mode \"default\" :role \"user\" :turn 1}","type":"chunk"}' /tmp/rb-e2e-out
check "REQ-24：推流之后仍继续收请求（id 3 有结果）" \
      '3' \
      "$(grep -o '"id":3' /tmp/rb-e2e-out | head -1 | grep -o '3')"

# REQ-48：工具调用全链路 + 附录 F 的 event 消息
export RB_MOCK_TOOL='add2:{"a":40}'
printf '%s\n' \
  '{"type":"eval","src":"deftool \"add2\" \"加二\" [ at \"a\"\n+ 2 ]"}' \
  '{"type":"eval","src":"agent \"c\" { }\nsend say \"加二\"\ndrain\npop"}' \
  '{"type":"quit"}' > /tmp/rb-e2e-tool
check_rc "REQ-48：deftool + send + 工具循环跑完" 0 $RAVEL --serve < /tmp/rb-e2e-tool
check_has "REQ-48：@Toolcall 变成协议 event 消息（附录 F）" \
  '{"name":"@Toolcall","stream":"c","text":"add2 {\"a\":40}","type":"event"}' /tmp/rb-e2e-out
check_has "REQ-48：工具结果之后同一条流继续吐文本（不开新流）" \
  '{"n":0,"stream":"c","text":"ab","type":"chunk"}' /tmp/rb-e2e-out
check "REQ-48：event 只发一次（不随事件风暴翻倍）" \
  '1' \
  "$(grep -cF '"type":"event"' /tmp/rb-e2e-out)"
unset RB_MOCK_TOOL

# REQ-68：参数模式 / 别名 / 手误回给模型（用户实测的 `command` vs `cmd`）
printf '%s\n' \
  '{"type":"eval","src":"agent \"c\" { }\ndup\nsend say \"跑\"\ndrain\npop\nsession"}' \
  '{"type":"quit"}' > /tmp/rb-e2e-args

RB_MOCK_TOOL='shell:{"command": "echo hi"}' \
  check_rc "REQ-68：模型把 cmd 写成 command，别名认下 → 成功" 0 $RAVEL --serve < /tmp/rb-e2e-args
RB_MOCK_TOOL='shell:{"command": "echo hi"}' \
  check_has "REQ-68：命令真的跑了（结果进了会话的 tool 消息）" \
  'hi' /tmp/rb-e2e-out

RB_MOCK_TOOL='read:{"pth": "README.md"}' \
  check_rc "REQ-68：参数名彻底写错也不再报废整轮（旧行为 60）" 0 $RAVEL --serve < /tmp/rb-e2e-args
RB_MOCK_TOOL='read:{"pth": "README.md"}' \
  check_has "REQ-68：错误作为 role=tool 的结果回给模型" \
  '缺少参数 path（接受：path / file_path' /tmp/rb-e2e-out

check_rc "REQ-68：脚本里的 invoke 仍是 60（没人替程序员改参数）" 60 \
  $RAVEL -e 'invoke "read" H{ "pth" "README.md" }'
check_has "REQ-68：invoke 的报错写清可接受的键" \
  '接受：path / file_path' /tmp/rb-e2e-err
check_rc "REQ-68：环境侧失败照样 60" 60 \
  $RAVEL -e 'invoke "read" H{ "path" "/etc/shadow" }'

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
      '@[@{:content \"hi\" :from \"c\" :mode \"default\" :role \"user\" :turn 1} @{:content \"abcdefgh\" :from \"c\" :mode \"default\" :role \"assistant\" :turn 2}]' \
      /tmp/rb-e2e-out
check_rc "agent：@off @RoundDone 关闭自动合并" 0 $RAVEL -e 'agent "c" { }
@off @RoundDone
dup
send say "hi"
utter
append
session'
check "agent：手动路径也能合并（REQ-19/46）" \
      '@[@{:content "hi" :from "c" :mode "default" :role "user" :turn 1} @{:content "abcdefgh" :from "c" :mode "default" :role "assistant" :turn 2}]' \
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
W=build/tmp/e2e-ws.json
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
check_rc "IO：write 写文件" 0 $RAVEL -e "write \"hi\" \"build/tmp/e2e-io.txt\""
check "IO：write 后内容就位" "hi" "$(cat build/tmp/e2e-io.txt)"
check_rc "IO：read 读回" 0 $RAVEL -e "read \"build/tmp/e2e-io.txt\""
check "IO：read 渲染" '"hi"' "$(cat /tmp/rb-e2e-out)"
check_rc "IO：读不存在 → 40" 40 $RAVEL -e "read \"build/tmp/e2e-nope.txt\""
check_rc "IO：载入不存在 → 40" 40 $RAVEL -e "load \"build/tmp/e2e-nope.json\""
check_rc "IO：写不进去 → 41" 41 $RAVEL -e "write \"x\" \"/proc/1/__nope/x\""
# 编排级 60 需要「核心无能力层」的构建：用只含核心的 bundle 跑同一条源码
check_rc "编排级：无能力层时 send → 60" 60 \
      build/janet -e '(each f (parse-all (slurp "build/core-only/rb-bundle.janet")) (eval f (curenv)))
                      (def r (rb/run-source "send say \"hi\" agent \"c\" { }" "t"))
                      (os/exit (if (r :ok) 0 (rb/error-code (r :error))))'
check_rc "工作区：save 非工作区 → 31" 31 $RAVEL -e "save H{ } \"build/tmp/e2e-x.json\""
# D-60：能力层文件沙箱（根 = 当前目录；RB_SANDBOX=none 才放开）
check_rc "沙箱：根外写 → 41" 41 $RAVEL -e 'write "x" "/tmp/rb-e2e-denied.txt"'
check_rc "沙箱：根外读 → 40" 40 $RAVEL -e 'read "/etc/hostname"'
check_rc "沙箱：关卡后仍能写根内" 0 $RAVEL -e 'write "x" "build/tmp/e2e-sandbox.txt"' 

# D-55：失败的一轮没有栈效果——报错后能继续，且栈上没有半截操作数
check_rc "REPL：栈下溢后仍能继续（D-55）" 0 bash -c "printf '+ 1\ndepth\nquit\n' | $RAVEL"
check "REPL：报错不退出、后续语句照跑" "yes" \
      "$(grep -q '栈下溢' /tmp/rb-e2e-err && echo yes || echo no)"
check "REPL：下溢没留下半截操作数（深度回到 0）" "0" \
      "$(tr -d 'ravel> \n' < /tmp/rb-e2e-out)"
# --serve 里同样：报错请求不影响下一个请求的栈
check_rc "--serve：坏请求后继续（D-55）" 0 bash -c "printf '+ 1\ndepth\n' | $RAVEL --serve"
check "--serve：下一个请求看到干净栈" "yes" \
      "$(tail -1 /tmp/rb-e2e-out | grep -q '\"stack\":\[\"0\"\]' && echo yes || echo no)"

# D-54：provider 配置在方言里可读可写，运行中可切换
check_rc "配置：llm-get 生效值" 0 $RAVEL -e 'llm-get "provider"'
check "配置：缺省 provider（RB_LLM=mock）" '"mock"' "$(cat /tmp/rb-e2e-out)"
check_rc "配置：llm-set 后立即生效" 0 $RAVEL -e 'llm-set "nvidia" "provider"
llm-get "provider"'
check "配置：工作区覆盖环境变量" '"nvidia"' "$(cat /tmp/rb-e2e-out)"
check_rc "配置：拼错配置项 → 31" 31 $RAVEL -e 'llm-set "x" "provier"'
check_rc "配置：密钥不是配置项 → 60" 60 $RAVEL -e 'llm-set "sk-x" "key"'
# 配置随快照走：同一份 .rbx 换进程仍然有效
CFGW=build/tmp/e2e-cfg.json
check_rc "配置：随快照保存" 0 $RAVEL -e "llm-set \"nvidia\" \"provider\"
save current \"$CFGW\""
check_rc "配置：换进程载入仍生效" 0 $RAVEL -e "load \"$CFGW\"
llm-get \"provider\""
check "配置：载入后 provider 仍是 nvidia" '"nvidia"' "$(tail -1 /tmp/rb-e2e-out)"

# P3：协议 cancel —— 停掉还开着的流，会话继续可用
check_rc "cancel：协议请求得到 result" 0 bash -c "printf '{\"type\":\"cancel\"}\n' | $RAVEL --serve"
check "cancel：带 stopped 计数且不结束会话" "yes" \
      "$(tail -1 /tmp/rb-e2e-out | grep -q '\"stopped\":0' && grep -q '\"ok\":true' /tmp/rb-e2e-out && echo yes || echo no)"
check_rc "cancel：之后照常求值" 0 bash -c "printf '{\"type\":\"cancel\"}\n{\"type\":\"eval\",\"src\":\"+ 1 2\"}\n' | $RAVEL --serve"
check "cancel：栈上是 3" "yes" \
      "$(tail -1 /tmp/rb-e2e-out | grep -q '\"stack\":\["3"\]' && echo yes || echo no)"
# P3：方言 cancel 词（空工作区 = 0）
check_rc "cancel 词：空工作区返回 0" 0 $RAVEL -e 'cancel'
check "cancel 词：栈顶 0" "0" "$(cat /tmp/rb-e2e-out)"

# REQ-62 / REQ-63：provider 配置预设 —— 一键导入、导出、启动装载
check_rc "预设：--preset 一键导入（provider）" 0 $RAVEL --preset opencode-go -e 'llm-get "provider"'
check "预设：--preset 真的换了 provider" '"opencode"' "$(cat /tmp/rb-e2e-out)"
check "预设：装的是仓库自带那份（model=deepseek-v4.1-flash）" '"deepseek-v4.1-flash"' \
      "$($RAVEL --preset opencode-go -e 'llm-get "model"' 2>/dev/null | tail -1)"
check_rc "预设：RB_PRESET 环境变量等价" 0 env RB_PRESET=nvidia $RAVEL -e 'llm-get "provider"'
check "预设：RB_PRESET 生效" '"nvidia"' "$(cat /tmp/rb-e2e-out)"
check_rc "预设：名字不存在 → 40" 40 $RAVEL --preset nope -e '1'
check_rc "预设：--preset 缺参数 → 2" 2 $RAVEL --preset
# 用户配置文件：存在就装（stderr 一行通报），--no-config 关掉
PUSER=build/tmp/e2e-user-config.json
printf '{"provider":"mock","model":"from-user-file"}\n' > "$PUSER"
check_rc "预设：RB_CONFIG 指定的用户配置被装载" 0 env RB_CONFIG="$PUSER" $RAVEL -e 'llm-get "model"'
check "预设：用户配置生效" '"from-user-file"' "$(cat /tmp/rb-e2e-out)"
check "预设：装载动作在诊断通道可见（REQ-43）" "yes" \
      "$(grep -q '已装载配置' /tmp/rb-e2e-err && echo yes || echo no)"
check_rc "预设：--no-config 关掉用户配置" 0 env RB_CONFIG="$PUSER" $RAVEL --no-config -e 'llm-get "model"'
check "预设：--no-config 后回到内置缺省" "yes" \
      "$(grep -qv 'from-user-file' /tmp/rb-e2e-out && echo yes || echo no)"
# 方言里的导入 / 导出（沙箱内）
PEXP=build/tmp/e2e-export.json
check_rc "预设：llm-import 名字" 0 $RAVEL -e 'llm-import "opencode-go"
llm-get "provider"'
check "预设：llm-import 生效" '"opencode"' "$(tail -1 /tmp/rb-e2e-out)"
check_rc "预设：llm-export 写文件" 0 $RAVEL -e "llm-import \"opencode-go\"
llm-export \"$PEXP\""
check "预设：导出的文件能再导入（往返）" '"opencode"' \
      "$($RAVEL --preset "$PEXP" -e 'llm-get "provider"' 2>/dev/null | tail -1)"
check_rc "预设：带 Authorization 的 headers 不许导出（60）" 60 $RAVEL -e \
  "llm-set H{ \"Authorization\" \"Bearer sk-x\" } \"headers\"
llm-export \"build/tmp/e2e-leak.json\""
check "预设：拒绝导出后没留下文件" "yes" \
      "$([ -e build/tmp/e2e-leak.json ] && echo no || echo yes)"

# REQ-64：预制的可发现（--presets / --modes）+ 报错带可用名字（v1.0l）
check_rc "预设：--presets 列出可用预设" 0 $RAVEL --presets
check "预设：--presets 有仓库自带三份" "yes" \
      "$(grep -q 'opencode-go' /tmp/rb-e2e-out && grep -q 'nvidia' /tmp/rb-e2e-out \
         && grep -q 'mock' /tmp/rb-e2e-out && echo yes || echo no)"
check "预设：--presets 给出绝对目录（不靠猜）" "yes" \
      "$(grep -q "^配置预设（/" /tmp/rb-e2e-out && echo yes || echo no)"
check "预设：--presets 报用户配置文件状态" "yes" \
      "$(grep -q '用户配置文件：' /tmp/rb-e2e-out && echo yes || echo no)"
check_rc "预设：--presets 在 RB_CONFIG=- 下也不炸" 0 env RB_CONFIG=- $RAVEL --presets
$RAVEL --preset nope -e '1' >/dev/null 2>/tmp/rb-e2e-err || true
check "预设：名字写错时报错列出可用名字" "yes" \
      "$(grep -q '可用：' /tmp/rb-e2e-err && echo yes || echo no)"
mkdir -p /tmp/rb-e2e-empty
check_rc "预设：没有 presets/ 的目录里也不炸（0，并说明找的是哪个目录）" 0 \
      bash -c "cd /tmp/rb-e2e-empty && RB_CONFIG=- $PWD/bin/ravel --presets"
check "预设：空目录明说「这个目录里没有」" "yes" \
      "$(grep -q '这个目录里没有' /tmp/rb-e2e-out && echo yes || echo no)"
check "预设：打印的绝对是实际目录（/tmp/rb-e2e-empty/presets）" "yes" \
      "$(grep -q '/tmp/rb-e2e-empty/presets' /tmp/rb-e2e-out && echo yes || echo no)"
# 坏预设不挡列表：build/tmp/presets/ 里有单测留下的坏夹具（bad / key / unknown / array）
RABS="$PWD/bin/ravel"
check_rc "预设：目录里有坏文件时，列表照常（0）" 0 \
      bash -c "cd build/tmp && RB_CONFIG=- $RABS --presets"
check "预设：坏文件只影响它那一行" "yes" \
      "$(grep -q '<读不出来' /tmp/rb-e2e-out && grep -q 'provider=opencode' /tmp/rb-e2e-out \
         && echo yes || echo no)"
check_rc "模式：--modes 列出预制模式" 0 $RAVEL --modes
check "模式：--modes 有 default 与 ptc" "yes" \
      "$(grep -q 'default' /tmp/rb-e2e-out && grep -q 'ptc' /tmp/rb-e2e-out && echo yes || echo no)"
check "模式：--modes 有 dsh 复刻的四个（standard / minimal / cordis）" "yes" \
      "$(grep -q 'standard' /tmp/rb-e2e-out && grep -q 'minimal' /tmp/rb-e2e-out \
         && grep -q 'cordis' /tmp/rb-e2e-out && echo yes || echo no)"
check "模式：--modes 带说明与工具" "yes" \
      "$(grep -q '工具：' /tmp/rb-e2e-out && echo yes || echo no)"
check_rc "模式：不存在的模式 → 20（mode 词）" 20 $RAVEL -e 'mode "nope"'
# REQ-65 / D-72：PTC 的 wire 只公示 eval，但程序里 invoke 得到真实工具
check_rc "模式：ptc 程序里 invoke glob（wire 藏起来 ≠ 不能调）" 0 $RAVEL -e \
  'mode "ptc"
invoke "eval" H{ "src" "invoke \"glob\" H{ \"pattern\" \"rb/MANIFEST\" }" }'
check "模式：invoke 的结果回得来" '"rb/MANIFEST"' "$(tail -1 /tmp/rb-e2e-out)"
# REQ-65：plan 是正交开关，不换模式
check "模式：enter-plan 打开 plan 开关" 'true' \
      "$($RAVEL -e 'enter-plan
flag "plan"' 2>/dev/null | tail -1)"
check "模式：exit_plan_mode 交出计划并关掉开关" 'false' \
      "$($RAVEL -e 'enter-plan
invoke "exit_plan_mode" H{ "plan" "# 计划" }
flag "plan"' 2>/dev/null | tail -1)"
check "模式：exit-plan 手动退出（同 dsh 的 /plan off）" 'false' \
      "$($RAVEL -e 'enter-plan
exit-plan
flag "plan"' 2>/dev/null | tail -1)"
check_rc "模式：minimal 只有 shell（调 write → 60）" 60 $RAVEL -e \
  'mode "minimal"
invoke "write" H{ "path" "build/tmp/nope.txt" "content" "x" }'
# REQ-67：模式的工具与设定自洽——装好就能用，不设任何环境变量
check "模式：default 的 shell 开箱即用（不需要 RB_ALLOW_SHELL）" '"hi\n"' \
      "$($RAVEL -e 'invoke "shell" H{ "cmd" "echo hi" }' 2>/dev/null | tail -1)"
check "模式：--modes 把前置设定印出来" "yes" \
      "$($RAVEL --modes 2>/dev/null | grep -q 'allow-shell=on' && echo yes || echo no)"
check_rc "模式：关掉 allow-shell 后 shell → 60" 60 $RAVEL -e \
  'flag-set false "allow-shell"
invoke "shell" H{ "cmd" "echo hi" }'
$RAVEL -e 'flag-set false "allow-shell"
invoke "shell" H{ "cmd" "echo hi" }' >/tmp/rb-e2e-out 2>&1
check "模式：关掉后的报错点名是哪个设定" "yes" \
      "$(grep -q 'allow-shell' /tmp/rb-e2e-out && echo yes || echo no)"
check_rc "模式：RB_ALLOW_SHELL=0 压过工作区设定 → 60" 60 \
      env RB_ALLOW_SHELL=0 $RAVEL -e 'invoke "shell" H{ "cmd" "echo hi" }'

# REQ-69：临时授权与审批
echo hi > /tmp/rb-e2e-approve.txt
check "审批：grant 之后越界读照常成功" '"hi\n"' \
      "$($RAVEL -e 'grant "fs" "/tmp"
read "/tmp/rb-e2e-approve.txt"' 2>/dev/null | tail -1)"
check_rc "审批：没授权 + 模型发起 + 非交互 → 60" 60 \
      env RB_MOCK_TOOL='read:{"path":"/tmp/rb-e2e-approve.txt"}' $RAVEL -e \
      'agent "c" { }
dup
send say "读"
drain'
env RB_MOCK_TOOL='read:{"path":"/tmp/rb-e2e-approve.txt"}' $RAVEL -e \
  'agent "c" { }
dup
send say "读"
drain' >/tmp/rb-e2e-out 2>&1
check "审批：非交互的报错给出 grant 这条退路" "yes" \
      "$(grep -q 'grant' /tmp/rb-e2e-out && echo yes || echo no)"
check "审批：@off @Approve + accept-dir → 自动批准，本轮成功" "yes" \
      "$(env RB_MOCK_TOOL='read:{"path":"/tmp/rb-e2e-approve.txt"}' $RAVEL -e \
           '@off @Approve
@on @Approve [ accept-dir ]
agent "c" { }
dup
send say "读"
drain
pop
session' 2>/dev/null | grep -q '1  hi' && echo yes || echo no)"
check_rc "审批：脚本里的 invoke 不走审批（仍 60）" 60 $RAVEL -e \
  'invoke "read" H{ "path" "/tmp/rb-e2e-approve.txt" }'
check_rc "审批：RB_SANDBOX=none 仍然是最直接的一条退路" 0 \
      env RB_SANDBOX=none $RAVEL -e 'read "/tmp/rb-e2e-approve.txt"'
rm -f /tmp/rb-e2e-approve.txt

check_rc "core-only：--presets 缺能力 → 60" 60 \
      build/janet -e '(each f (parse-all (slurp "build/core-only/rb-bundle.janet")) (eval f (curenv)))
                      (os/exit (rb/cli-main @["--presets"]))' 

echo "端到端：通过 $pass，失败 $fail"
[ "$fail" -eq 0 ]
