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
import os
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

SOURCE = os.environ.get("PLAINSPECTRUM_SOURCE", "auto")
PORT = int(os.environ.get("PLAINSPECTRUM_PORT", "8788"))
BARS = int(os.environ.get("PLAINSPECTRUM_BARS", "256"))
FPS = int(os.environ.get("PLAINSPECTRUM_FPS", "30"))
NOISE = int(os.environ.get("PLAINSPECTRUM_NOISE", "60"))
LOW_HZ = int(os.environ.get("PLAINSPECTRUM_LOW_HZ", "40"))
HIGH_HZ = int(os.environ.get("PLAINSPECTRUM_HIGH_HZ", "16000"))
RANGE = 1000            # ascii_max_range: 1000 steps, or the bars visibly step

state = {"raw": [0] * BARS, "frames": 0}


def cava_config():
    # `source` is left out when set to auto: cava then follows the default output.
    source = f"source={SOURCE}\n" if SOURCE and SOURCE != "auto" else ""
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
    """Feed cava its config on stdin and keep the latest frame."""
    proc = subprocess.Popen(["cava", "-p", "/dev/stdin"],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    proc.stdin.write(cava_config())
    proc.stdin.close()
    for line in proc.stdout:
        parts = line.strip().split(";")
        values = [int(p) for p in parts if p != ""]
        if len(values) < BARS:
            continue
        state["raw"] = values[:BARS]
        state["frames"] += 1
    print("cava exited", file=sys.stderr, flush=True)


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
        query = parse_qs(urlparse(self.path).query)
        want = int(query.get("bars", [BARS])[0])
        body = ",".join(str(v) for v in resample(state["raw"], want)).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
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
