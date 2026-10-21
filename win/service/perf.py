#!/usr/bin/env python3
"""The service's own meters, and what `GET /perf` answers.

Why this exists: the point of the Windows work is consumption — five widgets in idle must
stay under half a core and a quarter of a gigabyte — and a budget argued with numbers has
to have numbers. A person reading Task Manager over a screen share is not one. So the few
counters that matter live here, kept by the thing being measured: the service's own CPU
share and working set, the open connections, the requests by route, the milliseconds each
sampler tick costs (and, inside it, the process walk alone), the GPU counter tick, the
LibreHardwareMonitor fetch and the capture's real frame rate. `GET /perf` hands them out.

Everything on the reading side is cheap — a process handle and a few dicts — so the meter
is always on; no setting turns it off, and the readers that would slow the service down are
left out rather than asked for. psutil is optional: without it the own-process figures are
simply absent and the rest still answers, which keeps the stand on a bare machine working.

`perf` is a module name of this project only — win/service is the first entry on the
service's `sys.path` (win/plaintop.py), so `import perf` finds this file and not some
package of the same name.
"""
import threading
import time

try:
    import psutil
except ImportError:                     # the service still runs; the meters that need it are absent
    psutil = None


class Perf:
    """The counters. One instance per service; every method is safe from any thread."""

    def __init__(self, window=5.0, ps=psutil, clock=time.monotonic):
        self.window = float(window)
        self.ps = ps
        self.clock = clock
        self.lock = threading.Lock()
        self.started = clock()
        self.counts = {}                # route → requests
        self.timings = {}               # name → {"count", "total" (ms), "max" (ms)}
        self.connections = 0
        self._own = None                # the psutil.Process of this very process
        self._own_gone = False
        self._cpu = []                  # [(clock, cpu seconds)] for the own-CPU window

    # ── what the code being measured calls ────────────────────────────────────────
    def count(self, route):
        with self.lock:
            self.counts[route] = self.counts.get(route, 0) + 1

    def record(self, name, ms):
        """One duration in milliseconds: the average and the worst are reported."""
        ms = float(ms)
        with self.lock:
            row = self.timings.get(name)
            if row is None:
                self.timings[name] = {"count": 1, "total": ms, "max": ms}
            else:
                row["count"] += 1
                row["total"] += ms
                if ms > row["max"]:
                    row["max"] = ms

    def opened(self):
        with self.lock:
            self.connections += 1

    def closed(self):
        with self.lock:
            self.connections = max(0, self.connections - 1)

    # ── the own-process figures ───────────────────────────────────────────────────
    def _process(self):
        """This process, once; None where psutil is missing or the handle cannot be taken
        (a stripped environment). A failure is remembered, not retried on every read."""
        if self._own is not None or self._own_gone or self.ps is None:
            return self._own
        try:
            self._own = self.ps.Process()
        except Exception:
            self._own_gone = True
        return self._own

    def _own_cpu_percent(self, now):
        """The share of one core this process used over the last `window` seconds, from its
        CPU time and the wall clock between two reads — psutil's own interval= would block
        the thread for that long, and `/perf` must never wait."""
        proc = self._process()
        if proc is None:
            return None
        try:
            times = proc.cpu_times()
            cpu = float(times.user) + float(times.system)
        except Exception:
            return None
        self._cpu.append((now, cpu))
        horizon = max(self.window, 1.0)
        while len(self._cpu) > 2 and now - self._cpu[0][0] > horizon:
            self._cpu.pop(0)
        if len(self._cpu) < 2:
            return 0.0
        t0, c0 = self._cpu[0]
        span = now - t0
        if span <= 0:
            return 0.0
        return round(max(0.0, cpu - c0) / span * 100.0, 2)

    def _own_footprint(self):
        proc = self._process()
        rss = threads = None
        if proc is not None:
            try:
                rss = int(proc.memory_info().rss)
                threads = int(proc.num_threads())
            except Exception:
                rss = threads = None
        return rss, threads

    # ── the answer ────────────────────────────────────────────────────────────────
    def snapshot(self, service=None):
        now = self.clock()
        with self.lock:
            requests = dict(self.counts)
            timings = {name: {"count": r["count"], "avg": round(r["total"] / r["count"], 3),
                              "max": round(r["max"], 3)}
                       for name, r in self.timings.items() if r["count"]}
            connections = self.connections
            cpu = self._own_cpu_percent(now)
            rss, threads = self._own_footprint()
        out = {"uptime_s": round(now - self.started, 1),
               "cpu_percent": cpu, "rss": rss, "threads": threads,
               "connections": connections,
               "requests": requests, "timings_ms": timings}
        capture = getattr(service, "capture", None) if service is not None else None
        if capture is not None:
            try:
                state = capture.state()
                out["capture_fps"] = state.get("rate")
                out["capture_frames"] = state.get("frames")
                out["capture_backend"] = state.get("backend")
            except Exception:
                pass
        return out


if __name__ == "__main__":
    # A look at the meters without the server: read /perf twice, a second apart.
    import json
    p = Perf()
    p.count("GET /monitor")
    p.record("sample", 1.23)
    p.record("sample", 4.5)
    p.opened()
    print(json.dumps(p.snapshot(), indent=1))
    time.sleep(1.0)
    print(json.dumps(p.snapshot(), indent=1))
