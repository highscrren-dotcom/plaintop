#!/usr/bin/env python3
"""Serve cava's spectrum bands over local HTTP.

Why a relay at all: cava streams and never exits, while Plasma's `executable`
data engine only reports a command's output once it has finished, and QML cannot
read a local file — `XMLHttpRequest` to `file://` is refused inside plasmashell.
A request to `http://127.0.0.1` is allowed (verified), so that is the path.

The response is a plain comma-separated line of integers, not JSON: parsing it in
QML is cheaper, and at 30 requests a second that difference is measurable.

cava runs with a fixed, generous band count; the widget asks for the number it
draws via `?bars=N` and the downsampling happens here, in Python, rather than in
the widget's JavaScript.
"""
import json
import os
import subprocess
import time
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

SOURCE = os.environ.get("PLAINSPECTRUM_SOURCE", "auto")
PORT = int(os.environ.get("PLAINSPECTRUM_PORT", "8788"))
BARS = int(os.environ.get("PLAINSPECTRUM_BARS", "256"))
FPS = int(os.environ.get("PLAINSPECTRUM_FPS", "30"))
NOISE = int(os.environ.get("PLAINSPECTRUM_NOISE", "60"))
LOW_HZ = int(os.environ.get("PLAINSPECTRUM_LOW_HZ", "40"))
HIGH_HZ = int(os.environ.get("PLAINSPECTRUM_HIGH_HZ", "16000"))
RANGE = 1000            # ascii_max_range: 1000 steps, or the bars visibly step

state = {"raw": [0] * BARS, "frames": 0, "stamp": 0.0, "restarts": 0, "source": ""}

# The relay owns the settings files of both widgets. QML cannot write files, so every
# editor talks to this one owner over HTTP instead of racing over the file.
#
# ⚠️ The unit is still called plainspectrum-relay: renaming a running service for the sake
# of a tidier name would cost the user their setup. What it is, is the local service for
# the widgets — spectrum data plus settings storage.
CONF_BASE = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
HERE = Path(__file__).resolve().parent
CONFIGS = {
    "ring": (CONF_BASE / "plainspectrum" / "ring.json", "ring.default.json"),
    "monitor": (CONF_BASE / "plaintop" / "monitor.json", "monitor.default.json"),
}
config_lock = threading.Lock()


def config_paths(widget):
    path, defaults = CONFIGS.get(widget, CONFIGS["ring"])
    return path, HERE / defaults


def load_defaults(defaults_path):
    if defaults_path.exists():
        return json.loads(defaults_path.read_text(encoding="utf-8"))
    return {}


def read_config(widget="ring"):
    path, defaults_path = config_paths(widget)
    with config_lock:
        if path.exists():
            try:
                return json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as e:
                print(f"{path.name} does not parse ({e}), falling back to defaults",
                      file=sys.stderr, flush=True)
        cfg = load_defaults(defaults_path)
        if cfg:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n",
                            encoding="utf-8")
        return cfg


def write_config(patch, widget="ring"):
    """Merge a patch into a settings file, atomically."""
    path, defaults_path = config_paths(widget)
    with config_lock:
        cfg = {}
        if path.exists():
            try:
                cfg = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                cfg = load_defaults(defaults_path)
        else:
            cfg = load_defaults(defaults_path)
        cfg.update(patch)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        tmp.replace(path)
        return cfg


def default_monitor():
    """The monitor of the current default sink, or "" if pactl cannot say.

    ⚠️ Resolved at every cava start rather than once: PipeWire renumbers nodes and the
    user switches outputs, and cava binds to whatever it was given at launch.
    """
    try:
        out = subprocess.run(["pactl", "get-default-sink"], capture_output=True,
                             text=True, timeout=3)
        name = out.stdout.strip()
        return f"{name}.monitor" if name else ""
    except Exception:
        return ""


def cava_config(source_name):
    source = f"source={source_name}\n" if source_name else ""
    return (
        "[general]\n"
        f"framerate={FPS}\n"
        f"bars={BARS}\n"
        "autosens=1\n"
        f"lower_cutoff_freq={LOW_HZ}\n"
        f"higher_cutoff_freq={HIGH_HZ}\n"
        f"noise_reduction={NOISE}\n"
        "[input]\n"
        "method=pipewire\n"
        f"{source}"
        "[output]\n"
        "method=raw\n"
        "raw_target=/dev/stdout\n"
        "data_format=ascii\n"
        f"ascii_max_range={RANGE}\n"
    )


def pump():
    """Keep a cava running and its latest frame in `state`.

    ⚠️ cava does exit — a device change or a PipeWire restart is enough. The first version
    of this relay let the reading thread end there and went on serving zeros forever, with
    the widget looking merely silent. So it is supervised: respawned, and restarted when
    the default output changes under it.

    ⚠️ Nothing inside the loop may end the thread. At boot the relay can start before
    PipeWire is up; cava then fails and writes a terminal-title escape (`\x1b]0;…`) to
    stdout, which once reached int() and killed this thread for good — the relay kept
    answering, with no cava and no restarts, until the next reboot.
    """
    delay = 1
    while True:
        source_name = default_monitor() if SOURCE == "auto" else SOURCE
        state["source"] = source_name or "(default)"
        try:
            proc = subprocess.Popen(["cava", "-p", "/dev/stdin"],
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        except FileNotFoundError:
            print("cava not found", file=sys.stderr, flush=True)
            return
        got_frames = False
        try:
            proc.stdin.write(cava_config(source_name))
            proc.stdin.close()
            threading.Thread(target=watch_device, args=(proc, source_name), daemon=True).start()

            for line in proc.stdout:
                try:
                    values = [int(p) for p in line.strip().split(";") if p != ""]
                except ValueError:
                    continue            # a message or an escape sequence, not a frame
                if len(values) < BARS:
                    continue
                state["raw"] = values[:BARS]
                state["stamp"] = time.monotonic()
                state["frames"] += 1
                got_frames = True
        except Exception as e:          # never let the supervisor die with its child
            print(f"reading cava failed: {e!r}", file=sys.stderr, flush=True)
            proc.kill()

        proc.wait()
        state["restarts"] += 1
        # Back off while cava cannot even start (no sound server yet), so a missing
        # PipeWire costs a respawn every 10 s rather than every second.
        delay = 1 if got_frames else min(delay * 2, 10)
        print(f"cava exited (code {proc.returncode}), restarting in {delay} s",
              file=sys.stderr, flush=True)
        time.sleep(delay)


def watch_device(proc, source_name):
    """Kill cava when the default output changes, so pump() rebinds it to the new one."""
    if SOURCE != "auto":
        return
    while proc.poll() is None:
        time.sleep(3)
        current = default_monitor()
        if current and current != source_name:
            print(f"default output changed to {current}, restarting cava",
                  file=sys.stderr, flush=True)
            proc.terminate()
            return


def resample(values, want):
    """Average the fixed cava bands down to the count the widget draws."""
    if want <= 0 or want == len(values):
        return values
    out = []
    step = len(values) / want
    for i in range(want):
        lo = int(i * step)
        hi = max(lo + 1, int((i + 1) * step))
        chunk = values[lo:hi]
        out.append(sum(chunk) // len(chunk))
    return out


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"   # keep-alive: without it every poll is a new connection

    def do_GET(self):
        if urlparse(self.path).path == "/state":
            # Readable state, so "all zeros" never has to be guessed at again.
            age = time.monotonic() - state["stamp"] if state["stamp"] else -1
            body = json.dumps({"frames": state["frames"], "restarts": state["restarts"],
                               "source": state["source"], "age": round(age, 2),
                               "bars": BARS, "fps": FPS}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        parsed = urlparse(self.path)
        if parsed.path == "/config":
            widget = parse_qs(parsed.query).get("widget", ["ring"])[0]
            self.send_json(read_config(widget))
            return

        query = parse_qs(urlparse(self.path).query)
        want = int(query.get("bars", [BARS])[0])
        # cava falls asleep on silence (sleep_timer) and simply stops writing. Serving
        # its last frame would leave the widget frozen mid-note, so silence is served
        # as zeros once no frame has arrived for a second.
        raw = state["raw"] if time.monotonic() - state["stamp"] < 1.0 else [0] * BARS
        body = ",".join(str(v) for v in resample(raw, want)).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        parsed = urlparse(self.path)
        widget = parse_qs(parsed.query).get("widget", ["ring"])[0]
        if parsed.path != "/config":
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8") if length else "{}"
        try:
            patch = json.loads(raw)
            if not isinstance(patch, dict):
                raise ValueError("expected an object")
        except (json.JSONDecodeError, ValueError) as e:
            body = json.dumps({"error": str(e)}).encode()
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_json(write_config(patch, widget))

    def send_json(self, payload):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def main():
    threading.Thread(target=pump, daemon=True).start()
    print(f"plainspectrum relay: http://127.0.0.1:{PORT}/bands "
          f"({BARS} bands from cava at {FPS} fps, source {SOURCE})", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
