/*
 * ravel breve —— 宿主入口（REQ-22 CLI / REQ-38 静态嵌入）
 *
 * 方言层（rb/ + cap/）以 amalgamated 方式嵌入：bundle 由 tools/embed.janet
 * 生成 C 字节数组，这里交给 janet_dobytes 装载，然后调用 (rb/cli-main ...)。
 * 退出码由方言层决定（REQ-23 分级）。
 *
 * 另外提供一组**终端原语**（`rb-term` 表，D-57）：REPL 的行编辑器要用
 * 「原始模式 + 单字节读 + ESC 序列解析」，这几件事在 Janet 里做不了。
 * 方言层通过 `(dyn :rb-term)` 取用（间接层 D-29），因此在**没有**这张表的
 * 环境里（单元测试用的裸 janet）rb/line.janet 仍能装载，只是退回行模式。
 */
#include <janet.h>
#include <stdio.h>
#include <string.h>
#include "rb_bundle.h"

#if defined(__unix__) || defined(__APPLE__)
#include <termios.h>
#include <unistd.h>
#include <poll.h>
#define RB_HAVE_TERM 1
#else
#define RB_HAVE_TERM 0
#endif

/* 键码约定（与 rb/line.janet 的 docstring 一致） */
#define RB_KEY_EOF   -1   /* stdin 关闭 */
#define RB_KEY_BARE_ESC -2 /* 单独的 ESC（后面没字节了）*/
#define RB_KEY_UNKNOWN -3 /* 认不出的序列：忽略 */
#define RB_KEY_UP    -101
#define RB_KEY_DOWN  -102
#define RB_KEY_RIGHT -103
#define RB_KEY_LEFT  -104
#define RB_KEY_HOME  -105
#define RB_KEY_END   -106
#define RB_KEY_DEL   -107
#define RB_KEY_WORD_RIGHT -108
#define RB_KEY_WORD_LEFT  -109

#define RB_ESC_WAIT_MS 40   /* ESC 之后等这么久；超时 = 用户按了 Esc（D-57） */

#if RB_HAVE_TERM
static struct termios rb_tio_saved;
static int rb_tio_raw = 0;

static void rb_tio_restore(void) {
    if (rb_tio_raw) {
        tcsetattr(STDIN_FILENO, TCSADRAIN, &rb_tio_saved);
        rb_tio_raw = 0;
    }
}

static Janet rb_cf_tty(int32_t argc, Janet *argv) {
    (void) argc; (void) argv;
    return janet_wrap_boolean(isatty(STDIN_FILENO) && isatty(STDOUT_FILENO));
}

static Janet rb_cf_raw_on(int32_t argc, Janet *argv) {
    (void) argc; (void) argv;
    if (!isatty(STDIN_FILENO)) return janet_wrap_boolean(0);
    if (rb_tio_raw) return janet_wrap_boolean(1);
    if (tcgetattr(STDIN_FILENO, &rb_tio_saved) != 0) return janet_wrap_boolean(0);
    struct termios t = rb_tio_saved;
    /* 关掉行缓冲 / 回显 / 信号键：C-c 要作为字节交上来（= 取消本行） */
    t.c_iflag &= ~(IXON | ICRNL | INLCR | IGNCR | BRKINT | INPCK | ISTRIP);
    t.c_lflag &= ~(ICANON | ECHO | ECHONL | ISIG | IEXTEN);
    t.c_cc[VMIN] = 1;
    t.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSADRAIN, &t) != 0) return janet_wrap_boolean(0);
    rb_tio_raw = 1;
    return janet_wrap_boolean(1);
}

static Janet rb_cf_raw_off(int32_t argc, Janet *argv) {
    (void) argc; (void) argv;
    rb_tio_restore();
    return janet_wrap_nil();
}

/* 读一个字节；timeout_ms < 0 = 一直等。返回 0..255，或 -1（超时/EOF） */
static int rb_get_byte(int timeout_ms) {
    if (timeout_ms >= 0) {
        struct pollfd p;
        p.fd = STDIN_FILENO;
        p.events = POLLIN;
        p.revents = 0;
        int r = poll(&p, 1, timeout_ms);
        if (r <= 0) return -1;
    }
    unsigned char c;
    ssize_t n = read(STDIN_FILENO, &c, 1);
    if (n <= 0) return -1;
    return (int) c;
}

/* ESC [ ... <final>（或 ESC O <final>）→ 键码 */
static int rb_read_csi(void) {
    char params[16];
    int nparams = 0;
    int c;
    while ((c = rb_get_byte(RB_ESC_WAIT_MS)) >= 0) {
        if (c >= 0x40 && c <= 0x7e) {           /* final byte */
            params[nparams] = '\0';
            int word = (strstr(params, ";5") || strstr(params, ";3"));
            switch (c) {
                case 'A': return RB_KEY_UP;
                case 'B': return RB_KEY_DOWN;
                case 'C': return word ? RB_KEY_WORD_RIGHT : RB_KEY_RIGHT;
                case 'D': return word ? RB_KEY_WORD_LEFT : RB_KEY_LEFT;
                case 'H': return RB_KEY_HOME;
                case 'F': return RB_KEY_END;
                case '~':
                    if (params[0] == '1' || params[0] == '7') return RB_KEY_HOME;
                    if (params[0] == '4' || params[0] == '8') return RB_KEY_END;
                    if (params[0] == '3') return RB_KEY_DEL;
                    return RB_KEY_UNKNOWN;
                default: return RB_KEY_UNKNOWN;
            }
        }
        if (nparams < (int) sizeof(params) - 1) params[nparams++] = (char) c;
    }
    return RB_KEY_BARE_ESC;
}

/* 一个逻辑键（含 UTF-8 组装与 ESC 消歧）→ 键码 */
static int rb_read_key(void) {
    int b = rb_get_byte(-1);
    if (b < 0) return RB_KEY_EOF;
    if (b == 27) {                                   /* ESC */
        int c = rb_get_byte(RB_ESC_WAIT_MS);
        if (c < 0) return RB_KEY_BARE_ESC;            /* 单独按了 Esc */
        if (c == '[' || c == 'O') return rb_read_csi();
        if (c == 'b') return RB_KEY_WORD_LEFT;        /* Alt-b / Alt-Left */
        if (c == 'f') return RB_KEY_WORD_RIGHT;       /* Alt-f / Alt-Right */
        return RB_KEY_UNKNOWN;
    }
    if (b < 0x80) return b;
    /* UTF-8：按 lead 字节取后续字节 */
    int extra;
    if ((b & 0xe0) == 0xc0) { extra = 1; b &= 0x1f; }
    else if ((b & 0xf0) == 0xe0) { extra = 2; b &= 0x0f; }
    else if ((b & 0xf8) == 0xf0) { extra = 3; b &= 0x07; }
    else return RB_KEY_UNKNOWN;
    for (int i = 0; i < extra; i++) {
        int c = rb_get_byte(RB_ESC_WAIT_MS);
        if (c < 0) return RB_KEY_UNKNOWN;
        b = (b << 6) | (c & 0x3f);
    }
    return b;
}

static Janet rb_cf_read_key(int32_t argc, Janet *argv) {
    (void) argc; (void) argv;
    return janet_wrap_integer(rb_read_key());
}
#else  /* 非 unix：没有终端原语，方言层自动退回行模式 */
static Janet rb_cf_tty(int32_t argc, Janet *argv) {
    (void) argc; (void) argv;
    return janet_wrap_boolean(0);
}
static Janet rb_cf_raw_on(int32_t argc, Janet *argv) {
    (void) argc; (void) argv;
    return janet_wrap_boolean(0);
}
static Janet rb_cf_raw_off(int32_t argc, Janet *argv) {
    (void) argc; (void) argv;
    return janet_wrap_nil();
}
static Janet rb_cf_read_key(int32_t argc, Janet *argv) {
    (void) argc; (void) argv;
    return janet_wrap_integer(RB_KEY_EOF);
}
#endif

int main(int argc, const char **argv) {
    janet_init();
#if RB_HAVE_TERM
    atexit(rb_tio_restore);   /* 任何退出路径都要把终端还回熟模式 */
#endif
    JanetTable *env = janet_core_env(NULL);

    /* 把命令行实参交给方言层（REQ-22） */
    JanetArray *args = janet_array(argc > 1 ? argc - 1 : 0);
    for (int i = 1; i < argc; i++) {
        janet_array_push(args, janet_cstringv(argv[i]));
    }
    janet_table_put(env, janet_ckeywordv("rb-argv"), janet_wrap_array(args));

    /* 终端原语表（D-57）：方言层用 (dyn :rb-term) 取，取不到就退行模式 */
    JanetTable *term = janet_table(8);
    janet_table_put(term, janet_ckeywordv("tty"),
                    janet_wrap_cfunction(rb_cf_tty));
    janet_table_put(term, janet_ckeywordv("raw-on"),
                    janet_wrap_cfunction(rb_cf_raw_on));
    janet_table_put(term, janet_ckeywordv("raw-off"),
                    janet_wrap_cfunction(rb_cf_raw_off));
    janet_table_put(term, janet_ckeywordv("read-key"),
                    janet_wrap_cfunction(rb_cf_read_key));
    janet_table_put(env, janet_ckeywordv("rb-term"), janet_wrap_table(term));

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
