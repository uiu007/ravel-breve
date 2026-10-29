#!/usr/bin/env python3
"""web/bridge.py —— 把 `ravel --serve`（NDJSON over stdio）桥到浏览器。

一个页面不能直接开子进程，所以这里做一个 200 行的转接：
    HTTP  POST /api/eval  {"src": "…"}   → 写一条 {"type":"eval","src":…,"id":N}
    HTTP  GET  /api/events              → SSE，把 chunk / close / event 原样推给页面
    HTTP  GET  /api/words               → web/words.json（词表，由 gen-catalog.py 生成）

为什么不写 WebSocket：SSE + fetch 已经够用（一进一出，无双向突发），
而且不需要握手代码与第三方依赖——只用标准库。

只用标准库，Python 3.9+。

    python3 web/bridge.py                 # http://127.0.0.1:8787
    python3 web/bridge.py --mock          # 离线：RB_LLM=mock RB_CONFIG=-
    python3 web/bridge.py --port 9000 --llm opencode
"""
import argparse
import json
import os
import queue
import re
import signal
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
STATIC = {"index.html", "app.css", "app.js", "words.json", "favicon.svg"}


class Backend:
    """一个 `ravel --serve` 子进程 + 请求/响应配对。"""

    def __init__(self, argv, env, keep=200):
        self.argv = argv
        self.env = env
        self.lock = threading.Lock()          # 一次只发一个请求
        self.rlock = threading.Lock()         # 重启时独占（别让两个请求同时重启）
        self.wlock = threading.Lock()         # 写 stdin
        self.waiters = {}                     # id -> {"ev": Event, "msg": dict|None}
        # hello / ping / quit 的响应**不回显 id**（协议 §2.2），只能按类型配对
        self.waiters_by_type = {}             # "hello" | "pong" | "bye" -> waiter
        self.subs = []                        # SSE 订阅者（queue.Queue）
        self.sublock = threading.Lock()
        self.log = []                         # stderr 尾巴
        self.keep = keep
        self.seq = 0
        self.dead = None
        self.gen = 0                          # 第几代后端（重启一次 +1）
        self._spawn()

    def _spawn(self):
        self.proc = subprocess.Popen(
            self.argv, cwd=ROOT, env=self.env,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1,
        )
        threading.Thread(target=self._read_stdout, args=(self.proc, self.gen), daemon=True).start()
        threading.Thread(target=self._read_stderr, args=(self.proc, self.gen), daemon=True).start()

    def restart(self, why=""):
        """卡住的唯一解药：方言是单线程的，一句挂住的 shell 或死循环**没法从内部打断**
        （`cancel` 也排在同一个线程后面）。所以桥只能杀掉重开——代价是栈与 agent 全清空，
        这比让页面永远转圈诚实。返回被丢弃的 stderr 尾巴，好让页面知道刚才在干什么。"""
        with self.rlock:
            old = self.proc
            self.gen += 1
            gen = self.gen
            try:
                old.kill()
            except Exception:
                pass
            try:
                old.wait(timeout=5)
            except Exception:
                pass
            tail = list(self.log[-40:])
            self.dead = None
            self.waiters.clear()
            self.waiters_by_type.clear()
            self.seq = 0
            self._spawn()
            self._push({"type": "backend-restart", "gen": gen, "why": why})
            return tail

    # -- 进出 -------------------------------------------------------------
    def _read_stdout(self, proc, gen):
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except ValueError:
                self._push({"type": "noise", "text": line})
                continue
            rid = msg.get("id")
            if rid is not None and rid in self.waiters:
                w = self.waiters[rid]
                w["msg"] = msg
                w["ev"].set()
            elif rid is None:
                w = self.waiters_by_type.get(msg.get("type"))
                if w is not None and w["msg"] is None:
                    w["msg"] = msg
                    w["ev"].set()
            # 除了终结响应，其它（chunk / close / event）也要让页面看到
            if msg.get("type") != "result" or rid is None:
                self._push(msg)
            elif msg.get("type") == "result":
                self._push(msg)
        if gen == self.gen:
            self.dead = proc.poll()
            self._push({"type": "backend-exit", "code": self.dead})

    def _read_stderr(self, proc, gen):
        for line in proc.stderr:
            text = line.rstrip("\n")
            if not text.strip():
                continue
            self.log.append(text)
            if len(self.log) > self.keep:
                self.log.pop(0)
            self._push({"type": "stderr", "text": text})
        if gen == self.gen:
            self._push({"type": "backend-exit", "code": proc.poll()})

    def _push(self, msg):
        with self.sublock:
            for q in list(self.subs):
                try:
                    q.put_nowait(msg)
                except queue.Full:
                    pass

    def subscribe(self):
        q = queue.Queue(maxsize=512)
        with self.sublock:
            self.subs.append(q)
        return q

    def unsubscribe(self, q):
        with self.sublock:
            if q in self.subs:
                self.subs.remove(q)

    # -- 请求 -------------------------------------------------------------
    def request(self, obj, timeout=180.0):
        if self.dead is not None:
            raise RuntimeError(f"后端已退出（code={self.dead}）")
        with self.lock:
            self.seq += 1
            rid = f"q{self.seq}"
            obj = dict(obj)
            obj["id"] = rid
            w = {"ev": threading.Event(), "msg": None}
            typed = obj.get("type") in ("hello", "ping", "quit")
            if typed:
                self.waiters_by_type[{"hello": "hello", "ping": "pong", "quit": "bye"}[obj["type"]]] = w
            else:
                self.waiters[rid] = w
            proc = self.proc
            try:
                line = json.dumps(obj, ensure_ascii=False)
                with self.wlock:
                    proc.stdin.write(line + "\n")
                    proc.stdin.flush()
                if not w["ev"].wait(timeout):
                    raise TimeoutError(
                        f"后端 {timeout:.0f}s 没响应（{obj.get('type')}）——"
                        "多半是卡在一条不返回的命令或死循环上")
                return w["msg"]
            finally:
                self.waiters.pop(rid, None)
                if typed:
                    self.waiters_by_type.pop(
                        {"hello": "hello", "ping": "pong", "quit": "bye"}[obj["type"]], None)

    def close(self):
        try:
            if self.dead is None:
                self.request({"type": "quit"}, timeout=5)
        except Exception:
            pass
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        try:
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()


class Introspect:
    """`ravel --modes` / `ravel --presets` 这两个只读查询开关的 JSON 化（REQ-64 / D-70）。

    为什么走命令行而不是协议：这两个开关本来就是「装载前就能看」的自省，
    方言里 `modes` 只给名字，`mode-of` 只给当前那个——列不出每个模式的工具与设定。
    这里只做**文本搬运与切片**，不做解释：解析失败就把原文原样交给页面。
    结果缓存几秒（改预设文件后不用重启桥，但也不必每次点都起进程）。
    """

    def __init__(self, ravel, env, ttl=5.0):
        self.ravel = ravel
        self.env = env
        self.ttl = ttl
        self.cache = {}
        self.lock = threading.Lock()

    def _run(self, flag):
        p = subprocess.run([self.ravel, flag], cwd=ROOT, env=self.env,
                           capture_output=True, text=True, timeout=30)
        return (p.stdout or "") + (p.stderr or "")

    def _cached(self, key, flag, parse):
        now = time.time()
        with self.lock:
            hit = self.cache.get(key)
            if hit and now - hit[0] < self.ttl:
                return hit[1]
        raw = ""
        err = None
        try:
            raw = self._run(flag)
        except Exception as e:  # 超时 / 找不到可执行文件
            err = str(e)
        data = parse(raw)
        data["raw"] = raw
        if err:
            data["error"] = err
        with self.lock:
            self.cache[key] = (now, data)
        return data

    def modes(self):
        return self._cached("modes", "--modes", parse_modes)

    def presets(self):
        return self._cached("presets", "--presets", parse_presets)


def parse_modes(text):
    """`--modes` 的文本 → {modes:[{name, tools, settings, desc}]}。

    形状：首行是标题；每个模式以「两个空格 + 名字 + 工具：」开始，
    后续更深的缩进行是「设定：…」与一句说明。"""
    modes = []
    cur = None
    for line in (text or "").splitlines():
        if not line.strip():
            continue
        m = re.match(r"^ {2}(\S+)\s+工具：(.*)$", line)
        if m:
            cur = {"name": m.group(1),
                   "tools": m.group(2).split(),
                   "settings": {},
                   "desc": ""}
            modes.append(cur)
            continue
        if cur is None:
            continue
        body = line.strip()
        if body.startswith("设定："):
            for bit in body[len("设定："):].split():
                if "=" in bit:
                    k, v = bit.split("=", 1)
                    cur["settings"][k] = v
            continue
        if line.startswith(" " * 12):
            cur["desc"] = (cur["desc"] + " " + body).strip()
    return {"modes": modes}


def parse_presets(text):
    """`--presets` 的文本 → {presets:[{name, provider, model, note}]}。"""
    out = []
    for line in (text or "").splitlines():
        m = re.match(r"^ {2}(\S+)\s+provider=(\S+)\s+model=(.*)$", line)
        if m:
            out.append({"name": m.group(1), "provider": m.group(2),
                        "model": m.group(3).strip()})
            continue
        m = re.match(r"^ {2}(\S+)\s+(.*)$", line)
        if m and not line.strip().startswith(("用法", "用户配置文件")):
            out.append({"name": m.group(1), "provider": "", "model": "",
                        "note": m.group(2)})
    return {"presets": out}


def make_handler(backend, allow_origin=None, intro=None, eval_timeout=180.0):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        server_version = "ravel-bridge/1.0"

        def log_message(self, fmt, *args):
            if os.environ.get("RB_BRIDGE_QUIET"):
                return
            sys.stderr.write("  %s\n" % (fmt % args))

        # -- helpers ------------------------------------------------------
        def _json(self, obj, code=200):
            body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            if allow_origin:
                self.send_header("Access-Control-Allow-Origin", allow_origin)
            self.end_headers()
            self.wfile.write(body)

        def _text(self, body, ctype="text/plain; charset=utf-8", code=200):
            raw = body.encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(raw)

        def _body(self):
            n = int(self.headers.get("Content-Length") or 0)
            if n <= 0:
                return {}
            raw = self.rfile.read(n)
            try:
                return json.loads(raw.decode("utf-8") or "{}")
            except ValueError:
                return {}

        def _file(self, name):
            path = os.path.join(HERE, name)
            if not os.path.isfile(path):
                self._text("404\n", code=404)
                return
            ctype = {
                ".html": "text/html; charset=utf-8",
                ".css": "text/css; charset=utf-8",
                ".js": "text/javascript; charset=utf-8",
                ".json": "application/json; charset=utf-8",
                ".svg": "image/svg+xml",
            }.get(os.path.splitext(name)[1], "application/octet-stream")
            with open(path, "rb") as f:
                raw = f.read()
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(raw)

        # -- GET ----------------------------------------------------------
        def do_GET(self):
            path = urlparse(self.path).path
            if path in ("/", "/index.html"):
                return self._file("index.html")
            if path == "/api/words":
                return self._file("words.json")
            if path == "/api/log":
                return self._json({"lines": list(backend.log)})
            if path == "/api/modes":
                if intro is None:
                    return self._json({"modes": [], "raw": ""}, 503)
                return self._json(intro.modes())
            if path == "/api/presets":
                if intro is None:
                    return self._json({"presets": [], "raw": ""}, 503)
                return self._json(intro.presets())
            if path == "/api/hello":
                try:
                    return self._json(backend.request({"type": "hello"}, timeout=20))
                except Exception as e:
                    return self._json({"ok": False, "error": str(e)}, 503)
            if path == "/api/events":
                return self._events()
            name = path.lstrip("/")
            if name in STATIC:
                return self._file(name)
            return self._text("404\n", code=404)

        def _events(self):
            q = backend.subscribe()
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "keep-alive")
            self.send_header("X-Accel-Buffering", "no")
            self.end_headers()
            try:
                self.wfile.write(b": hello\n\n")
                self.wfile.flush()
                last = time.time()
                while True:
                    try:
                        msg = q.get(timeout=1.0)
                        data = json.dumps(msg, ensure_ascii=False)
                        self.wfile.write(("data: %s\n\n" % data).encode("utf-8"))
                        self.wfile.flush()
                    except queue.Empty:
                        if time.time() - last > 10:
                            self.wfile.write(b": ping\n\n")
                            self.wfile.flush()
                            last = time.time()
            except (BrokenPipeError, ConnectionResetError):
                pass
            finally:
                backend.unsubscribe(q)

        # -- POST ---------------------------------------------------------
        def do_POST(self):
            path = urlparse(self.path).path
            body = self._body()
            try:
                if path == "/api/eval":
                    src = body.get("src")
                    if not isinstance(src, str):
                        return self._json({"ok": False, "code": 2,
                                           "error": "src 必须是字符串", "type": "result"}, 400)
                    msg = backend.request({"type": "eval", "src": src},
                                          timeout=eval_timeout)
                    return self._json(msg)
                if path in ("/api/reset", "/api/cancel", "/api/ping", "/api/hello"):
                    kind = path.split("/")[-1]
                    msg = backend.request({"type": kind}, timeout=30)
                    return self._json(msg)
                if path == "/api/restart":
                    tail = backend.restart("页面点的重启")
                    return self._json({"ok": True, "type": "restart", "gen": backend.gen,
                                       "stderr": tail})
                return self._json({"ok": False, "error": "未知的接口"}, 404)
            except TimeoutError as e:
                # 卡住的后端叫不醒（单线程）：杀掉重开，把「栈清空、agent 要重建」说清楚。
                tail = backend.restart(str(e))
                return self._json({"ok": False, "code": 60, "type": "result",
                                   "restarted": True, "gen": backend.gen,
                                   "error": str(e) + "；后端已重启（栈与 agent 都清空了）",
                                   "stderr": tail[-12:]}, 504)
            except Exception as e:  # 后端挂了 / 管道断了
                return self._json({"ok": False, "code": 50, "error": str(e), "type": "result"}, 503)

        def do_OPTIONS(self):
            self.send_response(204)
            if allow_origin:
                self.send_header("Access-Control-Allow-Origin", allow_origin)
                self.send_header("Access-Control-Allow-Headers", "content-type")
                self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
            self.send_header("Content-Length", "0")
            self.end_headers()

    return Handler


def main(argv=None):
    ap = argparse.ArgumentParser(description="ravel breve 的网页桥")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--ravel", default=os.path.join(ROOT, "bin", "ravel"),
                    help="ravel 可执行文件（缺省 bin/ravel）")
    ap.add_argument("--mock", action="store_true",
                    help="离线模式：RB_LLM=mock RB_CONFIG=-")
    ap.add_argument("--allow-shell", default=None, help="透传 RB_ALLOW_SHELL")
    ap.add_argument("--sandbox", default=None, help="透传 RB_SANDBOX")
    ap.add_argument("--llm", default=None, help="透传 RB_LLM（opencode / nvidia / mock）")
    ap.add_argument("--no-config", action="store_true", help="RB_CONFIG=-（不读用户配置）")
    ap.add_argument("--eval-timeout", type=float, default=180.0,
                    help="一次求值最多等多少秒（超时就重启后端），缺省 180")
    ap.add_argument("--shell-timeout", default=None,
                    help="透传 RB_SHELL_TIMEOUT（shell 工具的超时秒数，缺省 60）")
    args = ap.parse_args(argv)

    env = dict(os.environ)
    if args.mock:
        env["RB_LLM"] = "mock"
        env["RB_CONFIG"] = "-"
    if args.llm:
        env["RB_LLM"] = args.llm
    if args.no_config:
        env["RB_CONFIG"] = "-"
    if args.allow_shell:
        env["RB_ALLOW_SHELL"] = args.allow_shell
    if args.sandbox:
        env["RB_SANDBOX"] = args.sandbox
    if args.shell_timeout:
        env["RB_SHELL_TIMEOUT"] = args.shell_timeout

    if not os.path.isfile(args.ravel):
        raise SystemExit(f"找不到 {args.ravel}（先跑 make all）")
    backend = Backend([args.ravel, "--serve"], env)
    intro = Introspect(args.ravel, env)
    handler = make_handler(backend, intro=intro, eval_timeout=args.eval_timeout)
    try:
        httpd = ThreadingHTTPServer((args.host, args.port), handler)
    except OSError as exc:
        backend.close()
        if getattr(exc, "errno", None) == 98:
            raise SystemExit(
                f"端口 {args.port} 已被占用（可能是上次的桥还活着）。\n"
                f"  换一个：python3 web/bridge.py --port {args.port + 1}"
            )
        raise
    httpd.daemon_threads = True
    url = f"http://{args.host}:{args.port}/"
    print(f"ravel breve 网页桥：{url}")
    print(f"  后端：{' '.join([args.ravel, '--serve'])}"
          f"（RB_LLM={env.get('RB_LLM', '（继承）')}）")
    print("  Ctrl-C 结束（会先给后端发 quit）")

    def bye(*_):
        threading.Thread(target=httpd.shutdown, daemon=True).start()
    signal.signal(signal.SIGINT, bye)
    signal.signal(signal.SIGTERM, bye)
    try:
        httpd.serve_forever()
    finally:
        backend.close()
        httpd.server_close()
        print("\n桥已关闭")
    return 0


if __name__ == "__main__":
    sys.exit(main())
