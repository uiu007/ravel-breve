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
        self.lock = threading.Lock()          # 一次只发一个请求
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
        self.proc = subprocess.Popen(
            argv, cwd=ROOT, env=env,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1,
        )
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()

    # -- 进出 -------------------------------------------------------------
    def _read_stdout(self):
        for line in self.proc.stdout:
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
        self.dead = self.proc.poll()
        self._push({"type": "backend-exit", "code": self.dead})

    def _read_stderr(self):
        for line in self.proc.stderr:
            text = line.rstrip("\n")
            if not text.strip():
                continue
            self.log.append(text)
            if len(self.log) > self.keep:
                self.log.pop(0)
            self._push({"type": "stderr", "text": text})
        self._push({"type": "backend-exit", "code": self.proc.poll()})

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
            try:
                line = json.dumps(obj, ensure_ascii=False)
                with self.wlock:
                    self.proc.stdin.write(line + "\n")
                    self.proc.stdin.flush()
                if not w["ev"].wait(timeout):
                    raise TimeoutError(f"后端 {timeout:.0f}s 未响应（{obj.get('type')}）")
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


def make_handler(backend, allow_origin=None):
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
                    msg = backend.request({"type": "eval", "src": src})
                    return self._json(msg)
                if path in ("/api/reset", "/api/cancel", "/api/ping", "/api/hello"):
                    kind = path.split("/")[-1]
                    msg = backend.request({"type": kind}, timeout=30)
                    return self._json(msg)
                return self._json({"ok": False, "error": "未知的接口"}, 404)
            except TimeoutError as e:
                return self._json({"ok": False, "code": 60, "error": str(e), "type": "result"}, 504)
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

    if not os.path.isfile(args.ravel):
        raise SystemExit(f"找不到 {args.ravel}（先跑 make all）")
    backend = Backend([args.ravel, "--serve"], env)
    handler = make_handler(backend)
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
