# ravel breve —— 构建（REQ-38：janet 1.42.x amalgamated 静态嵌入）

SHELL      := /bin/bash
CC         ?= cc
CFLAGS     ?= -O2 -std=c99 -Wall -Wextra -Wno-unused-parameter

JANET_DIR  := vendor/janet
JANET_C    := $(JANET_DIR)/janet.c
SHELL_C    := $(JANET_DIR)/shell.c
BUILD      := build
BIN        := bin

RB_MANIFEST := rb/MANIFEST
RB_SRCS     := $(shell grep -v '^\s*#' $(RB_MANIFEST) | grep -v '^\s*$$')

.PHONY: all test test-unit test-e2e test-agent test-core-only test-examples clean check-vendor bundle core-only

all: $(BIN)/ravel

# 开发用宿主（也是 embed/tests 的运行器）
$(BUILD)/janet: $(JANET_C) $(SHELL_C)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -I$(JANET_DIR) -o $@ $(JANET_C) $(SHELL_C) -lm -ldl -lpthread

# 内核 bundle（.janet 供测试，.c/.h 供静态嵌入）
$(BUILD)/rb-bundle.janet $(BUILD)/rb_bundle.c $(BUILD)/rb_bundle.h: tools/embed.janet $(RB_SRCS) $(RB_MANIFEST) | $(BUILD)/janet
	$(BUILD)/janet tools/embed.janet $(RB_MANIFEST) $(BUILD)

$(BIN)/ravel: src/main.c $(BUILD)/rb_bundle.c $(BUILD)/rb_bundle.h
	@mkdir -p $(BIN)
	$(CC) $(CFLAGS) -I$(JANET_DIR) -I$(BUILD) -o $@ src/main.c $(BUILD)/rb_bundle.c $(JANET_C) -lm -ldl -lpthread

# 仅核心（剔除 cap/，REQ-37 验收）
core-only: | $(BUILD)/janet
	$(BUILD)/janet tools/embed.janet $(RB_MANIFEST) $(BUILD) --core-only

bundle: $(BUILD)/rb-bundle.janet
	@echo "已生成 $<"

test: all test-unit test-e2e test-examples test-core-only

# 测试一律走离线 provider（RB_LLM=mock），确定性、不联网（M3）
test-unit: $(BUILD)/rb-bundle.janet
	RB_LLM=mock $(BUILD)/janet tests/run.janet

test-e2e: $(BIN)/ravel
	RB_LLM=mock bash tests/e2e/cli.sh

# 使用手册里的例程（mock，hermetic）：examples/run-all.sh
test-examples: $(BIN)/ravel
	RB_LLM=mock bash examples/run-all.sh

# 真 provider（NVIDIA）：需要密钥；没有则脚本自行跳过（不进 make test）
test-agent: $(BIN)/ravel
	bash tests/e2e/agent.sh

# 附录 D 验收：剔除 cap/ 后核心仍可独立装载并完成主脊
test-core-only: | $(BUILD)/janet
	@mkdir -p $(BUILD)/core-only
	$(BUILD)/janet tools/embed.janet $(RB_MANIFEST) $(BUILD)/core-only --core-only
	$(BUILD)/janet tools/core-only-check.janet $(BUILD)/core-only/rb-bundle.janet

check-vendor:
	@cd $(JANET_DIR) && for f in janet.c janet.h shell.c; do \
	  want=$$(sed -n "s/^sha256\.$$f = //p" VERSION); \
	  got=$$(sha256sum $$f | cut -d' ' -f1); \
	  if [ "$$want" = "$$got" ]; then echo "ok   $$f"; else echo "FAIL $$f"; exit 1; fi; \
	done

clean:
	rm -rf $(BUILD) $(BIN)/ravel
