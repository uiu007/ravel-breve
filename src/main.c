/*
 * ravel breve —— 宿主入口（REQ-22 CLI / REQ-38 静态嵌入）
 *
 * 方言层（rb/ + cap/）以 amalgamated 方式嵌入：bundle 由 tools/embed.janet
 * 生成 C 字节数组，这里交给 janet_dobytes 装载，然后调用 (rb/cli-main ...)。
 * 退出码由方言层决定（REQ-23 分级）。
 */
#include <janet.h>
#include <stdio.h>
#include "rb_bundle.h"

int main(int argc, const char **argv) {
    janet_init();
    JanetTable *env = janet_core_env(NULL);

    /* 把命令行实参交给方言层（REQ-22） */
    JanetArray *args = janet_array(argc > 1 ? argc - 1 : 0);
    for (int i = 1; i < argc; i++) {
        janet_array_push(args, janet_cstringv(argv[i]));
    }
    janet_table_put(env, janet_ckeywordv("rb-argv"), janet_wrap_array(args));

    Janet out;
    int status = janet_dobytes(env, rb_bundle, (int32_t) rb_bundle_len,
                               "rb/bundle.janet", &out);
    if (status != 0) {
        janet_eprintf("ravel: 内核装载失败：%V\n", out);
        janet_deinit();
        return 50;
    }

    status = janet_dostring(env, "(rb/cli-main (dyn :rb-argv))", "rb/cli", &out);
    int code = 0;
    if (status != 0) {
        janet_eprintf("ravel: 内部错误：%V\n", out);
        code = 50;
    } else if (janet_checktype(out, JANET_NUMBER)) {
        code = (int) janet_unwrap_number(out);
    }
    janet_deinit();
    return code;
}
