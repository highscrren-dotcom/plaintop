#!/usr/bin/env python3
"""The Windows service: one local HTTP process behind every host (win/PROTOCOL.md).

Why one server for everything: the QML hosts can reach `http://127.0.0.1` with
XMLHttpRequest and nothing else — no files, no processes, no D-Bus — so every reading,
every command and every setting goes through here. `spectrum/relay.py` is the model:
ThreadingHTTPServer, HTTP/1.1 keep-alive (a host polls several endpoints once a second,
and a new connection per poll was measurable there), a quiet log, and the `/bands`
protocol imported from the relay itself so the spectrum needs no change.

The endpoints other than `/monitor` and `/exec` live in modules beside this file and are
imported on first use, guardedly: a module that is missing or fails to import answers
503 for its paths while the rest of the service goes on. A Windows machine without an
audio stack, or a Linux stand without any of them, still gets a server.
"""
import importlib
import importlib.util
import json
import os
import secrets
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
WINDOWS = sys.platform == "win32"
PORT = int(os.environ.get("PLAINTOP_PORT", "8788"))
BODY_LIMIT = 1 << 20                 # a note travels base64 in a POST; nothing else is large


def load_relay():
    """fold_mono and resample from spectrum/relay.py, loaded by path: it is a script, not a
    package, and the two functions are the protocol — copying them would fork it."""
    spec = importlib.util.spec_from_file_location("relay", ROOT / "spectrum" / "relay.py")
    relay = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(relay)
    return relay


class Missing(Exception):
    """A module the request needs is not available: the handler answers 503."""


class Service:
    """What the handlers reach through `server.service`: the token, the sampler, the
    capture and the lazily imported modules. The stand builds one from fakes."""

    def __init__(self, token, sampler=None, capture=None, modules=None):
        self.token, self.sampler, self.capture = token, sampler, capture
        self.modules = dict(modules or {})           # name → module, or None for "missing"
        self.instances = {}
        self.lock = threading.RLock()                # instance() imports under the same lock
        self.notes_lock = threading.Lock()           # notes.py runs one at a time, by contract
        self.relay = None
        self.on_quit = lambda: threading.Timer(0.5, os._exit, [0]).start()

    def module(self, name):
        """The module by name; a failed import is remembered and reported once, since the
        hosts would otherwise retry it every second."""
        with self.lock:
            if name not in self.modules:
                try:
                    self.modules[name] = importlib.import_module(name)
                except Exception as e:
                    print(f"{name}: not available ({e!r})", file=sys.stderr, flush=True)
                    self.modules[name] = None
            return self.modules[name]

    def need(self, name):
        m = self.module(name)
        if m is None:
            raise Missing(name)
        return m

    def instance(self, name, cls, *args, **kwargs):
        """One object of a module's class for the life of the service (the settings store,
        the process manager); built on first use so a missing module costs nothing."""
        with self.lock:
            if name not in self.instances:
                self.instances[name] = getattr(self.need(name), cls)(*args, **kwargs)
            return self.instances[name]


# ── The endpoints: (status, body, content type) from the service, the query, the body ──

def json_reply(status, obj):
    return status, json.dumps(obj).encode("utf-8"), "application/json; charset=utf-8"


def error(status, text):
    return json_reply(status, {"error": text})


def get_bands(svc, query, body, path):
    bands = svc.module("bands")
    # Without a capture the frame is silence of the capture's own size: BARS per channel.
    raw = svc.capture.frame() if svc.capture else [0] * (2 * getattr(bands, "BARS", 256))
    want = int(query.get("bars", [len(raw)])[0] or len(raw))
    if query.get("mono", ["0"])[0] in ("1", "true"):
        raw = svc.relay.fold_mono(raw)
    text = ",".join(str(v) for v in svc.relay.resample(raw, want))
    return 200, text.encode(), "text/plain"


def get_state(svc, query, body, path):
    if svc.capture:
        return json_reply(200, svc.capture.state())
    bands = svc.module("bands")
    return json_reply(200, {"frames": 0, "restarts": 0, "source": "", "age": -1,
                            "bars": getattr(bands, "BARS", 256), "fps": getattr(bands, "FPS", 30),
                            "backend": "none"})


def get_monitor(svc, query, body, path):
    if svc.sampler is None:
        raise Missing("monitor_win")
    return json_reply(200, svc.sampler.snapshot())


def post_exec(svc, query, body, path):
    command = body.get("command") if isinstance(body, dict) else None
    if not isinstance(command, str) or not command.strip():
        return error(400, "command missing")
    return json_reply(200, svc.need("exec_win").run(command))


def get_player(svc, query, body, path):
    return json_reply(200, svc.need("player_win").snapshot())


def post_player(svc, query, body, path):
    if not isinstance(body, dict) or not isinstance(body.get("id"), str) or not isinstance(body.get("command"), str):
        return error(400, "id and command expected")
    return json_reply(200, {"ok": bool(svc.need("player_win").command(body["id"], body["command"]))})


def post_notes(svc, query, body, path):
    args = body.get("args") if isinstance(body, dict) else None
    if not isinstance(args, list) or not all(isinstance(a, str) for a in args):
        return error(400, "args must be a list of strings")
    bridge = svc.need("notes_bridge")
    with svc.notes_lock:
        stdout, code = bridge.run(args)
    return json_reply(200, {"stdout": stdout, "exit code": code})


def get_holidays(svc, query, body, path):
    try:
        regions = [r for r in query.get("regions", [""])[0].split(",") if r]
        year, month = int(query.get("year", [""])[0]), int(query.get("month", [""])[0])
    except ValueError:
        return error(400, "year and month expected")
    lang = query.get("lang", ["en"])[0]
    return json_reply(200, svc.need("holidays_win").month(regions, year, month, lang))


def get_regions(svc, query, body, path):
    return json_reply(200, svc.need("holidays_win").regions(query.get("lang", ["en"])[0]))


def get_time(svc, query, body, path):
    return json_reply(200, svc.need("timezones").info(query.get("zone", ["Local"])[0]))


def store(svc):
    return svc.instance("settings_store", "Store")


def get_settings(svc, query, body, path):
    widget = path.split("/", 2)[2]
    try:
        stamp, values = store(svc).get(widget)
    except (KeyError, ValueError):
        return error(404, "no such widget")
    # A host asks every second; while nothing changed the answer is a header and no body.
    if query.get("since", [None])[0] == str(stamp):
        return 304, b"", "application/json; charset=utf-8"
    return json_reply(200, {"stamp": stamp, "values": values})


def post_settings(svc, query, body, path):
    widget = path.split("/", 2)[2]
    if not isinstance(body, dict):
        return error(400, "a JSON object of keys expected")
    try:
        stamp = store(svc).update(widget, body)
    except (KeyError, ValueError) as e:
        return error(400, str(e) or "rejected")
    return json_reply(200, {"stamp": stamp})


def post_notify(svc, query, body, path):
    # The calendar's reminder aside the sheet: a toast and a sound (notify_win.py).
    if not isinstance(body, dict):
        return error(400, "a JSON object expected")
    return json_reply(200, svc.need("notify_win").notify(body))


def manager(svc):
    return svc.instance("ui", "Manager")


def get_ui(svc, query, body, path):
    return json_reply(200, manager(svc).status())


def post_ui(svc, query, body, path):
    if not isinstance(body, dict):
        return error(400, "a JSON object expected")
    answer = manager(svc).handle(body)
    # "quit" stops the hosts in the manager; the service itself goes too, since the tray
    # that could ask again is one of them — after the answer has left.
    if body.get("quit") is True and not answer.get("error"):
        svc.on_quit()
    return json_reply(200, answer)


ROUTES = {
    ("GET", "/bands"): get_bands, ("GET", "/state"): get_state, ("GET", "/monitor"): get_monitor,
    ("POST", "/exec"): post_exec,
    ("GET", "/player"): get_player, ("POST", "/player"): post_player,
    ("POST", "/notes"): post_notes, ("POST", "/notify"): post_notify,
    ("GET", "/holidays"): get_holidays, ("GET", "/holidays/regions"): get_regions,
    ("GET", "/time"): get_time,
    ("GET", "/ui"): get_ui, ("POST", "/ui"): post_ui,
}


def route(method, path):
    if path.startswith("/settings/") and len(path) > len("/settings/") and "/" not in path[10:]:
        return get_settings if method == "GET" else post_settings
    return ROUTES.get((method, path))


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"   # keep-alive: without it every poll is a new connection

    def do_GET(self):
        self.handle_request("GET")

    def do_POST(self):
        self.handle_request("POST")

    def handle_request(self, method):
        svc = self.server.service
        url = urlparse(self.path)
        query = parse_qs(url.query)
        try:
            body = self.read_body()
            # A browser always sends Origin; the hosts never do. Whatever the request asks,
            # a page in a browser is not a host, and the token is not meant to leak to one.
            if self.headers.get("Origin") is not None:
                return self.reply(*error(403, "browser requests are refused"))
            if method == "POST" and self.headers.get("X-Plaintop-Token") != svc.token:
                return self.reply(*error(401, "token missing or wrong"))
            if body is not None:
                try:
                    body = json.loads(body.decode("utf-8")) if body else {}
                except (ValueError, UnicodeDecodeError):
                    return self.reply(*error(400, "the body is not JSON"))
            handler = route(method, url.path)
            if handler is None:
                return self.reply(*error(404, "no such path"))
            self.reply(*handler(svc, query, body, url.path))
        except Missing:
            self.reply(*error(503, "module not available"))
        except Exception as e:
            print(f"{method} {self.path}: {e!r}", file=sys.stderr, flush=True)
            self.reply(*error(500, repr(e)))

    def read_body(self):
        """The POST body, read whole even when the answer will be a refusal: on a kept-alive
        connection an unread body becomes the next request's first line."""
        if self.command != "POST":
            return None
        length = int(self.headers.get("Content-Length") or 0)
        if length > BODY_LIMIT:
            self.close_connection = True
            return b""
        return self.rfile.read(length) if length else b""

    def reply(self, status, body, content_type):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def log_message(self, *args):
        pass


def make_server(port, service):
    service.relay = service.relay or load_relay()
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.daemon_threads = True
    server.service = service
    return server


# ── The token ───────────────────────────────────────────────────────────────────────

def token_path():
    if WINDOWS:
        base = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    else:
        base = os.environ.get("XDG_RUNTIME_DIR") or str(Path.home() / ".cache")
    return Path(base) / "plaintop" / "token"


def write_token(path, token):
    """Readable by this user only: mode 600 where modes mean something; on Windows the
    directory under %LOCALAPPDATA% already carries the user's own ACL."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(token)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def main():
    # The port as the first argument or PLAINTOP_PORT; the token made here unless the
    # stand (tests/win_hosts.py) hands one in through PLAINTOP_TOKEN, since it must know
    # it before the service runs.
    port = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else PORT
    token = os.environ.get("PLAINTOP_TOKEN") or secrets.token_urlsafe(32)
    path = token_path()
    write_token(path, token)
    svc = Service(token)
    mw = svc.module("monitor_win")
    if mw is not None:
        svc.sampler = mw.Sampler(lhm=mw.LHM().start()).start()
    bands = svc.module("bands")
    if bands is not None:
        try:
            svc.capture = bands.Capture()
            svc.capture.start()
        except Exception as e:                        # no audio device, no loopback: /bands serves zeros
            print(f"capture not started: {e!r}", file=sys.stderr, flush=True)
            svc.capture = None
    # The process manager hands every host the token, so it is built now rather than on
    # the first /ui request, and it starts the widgets whose `shown` is on — unless a stand
    # runs the service alone (PLAINTOP_NO_HOSTS).
    try:
        store = svc.instance("settings_store", "Store")
        manager = svc.instance("ui", "Manager", ROOT / "win" / "host", port, token, store=store)
        if not os.environ.get("PLAINTOP_NO_HOSTS"):
            manager.start_shown()
    except Missing as e:
        print(f"{e}: not available, no hosts started", file=sys.stderr, flush=True)
    except Exception as e:
        print(f"hosts not started: {e!r}", file=sys.stderr, flush=True)
    print(f"plaintop service: http://127.0.0.1:{port}/monitor  (token in {path})", flush=True)
    make_server(port, svc).serve_forever()


if __name__ == "__main__":
    main()
