#!/usr/bin/env bash
# 10 前端协议：NDJSON over stdio（协议 v1，见 docs/PROTOCOL.md）
# 用法：./examples/10-serve.sh
cd "$(dirname "$0")/.." || exit 1
cat <<'EOF' | RB_LLM=mock "${RAVEL:-./bin/ravel}" --serve 2>/dev/null
{"type":"hello"}
{"type":"eval","src":"agent \"c\" { }"}
{"type":"eval","src":"dup\nsend say \"你好\"\ndrain"}
{"type":"eval","src":"pop\nmap [ Content ] session"}
{"type":"eval","src":"w : \"工作区常量\" [ 42 ]"}
{"type":"eval","src":"w"}
{"type":"eval","src":"1 2"}
{"type":"reset"}
{"type":"eval","src":"w"}
{"type":"ping"}
{"type":"quit"}
EOF
