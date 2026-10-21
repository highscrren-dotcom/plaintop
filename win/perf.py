#!/usr/bin/env python3
"""The desk's own meter: the whole plaintop family's CPU and memory, as Task Manager shows
it, without a person reading Task Manager.

    python win\\perf.py [--seconds 60] [--interval 1] [--all]

It finds every process of the port — the service (`plaintop.exe`, or a Python running
`win/plaintop.py` / `win/service/server.py`) and every `qml.exe` host, one engine per
widget before the one-process change, fewer after — and prints, once a second, the summed
CPU share (of one core, so five processes at 0.1% each read 0.5%) and the summed working
set, exactly the two figures the Windows budget is stated in. The last line is the summary
to paste into STATE.md.

`--all` widens the match to every process whose name starts with "plaintop" or "qml" (a
stray shell left from another run), which is what a person chasing a leak wants.

Needs psutil (pip install psutil); no network, no admin.
"""
import argparse
import sys
import time

try:
    import psutil
except ImportError:
    sys.exit("perf.py needs psutil: python -m pip install psutil")

MIB = 1048576
# The service and the hosts, by image name; the service may also be a bare Python running
# one of our entry points, which the name alone would not catch.
SERVICE_NAMES = ("plaintop.exe", "plaintop")
HOST_NAMES = ("qml.exe", "qml")
SERVICE_ARGS = ("plaintop.py", "service/server.py", "service\\server.py")


def family(all_names=False):
    """The processes of the port: [(pid, name)]."""
    out = []
    for p in psutil.process_iter(["name", "cmdline"]):
        try:
            name = (p.info.get("name") or "")
        except Exception:
            continue
        low = name.lower()
        if low in SERVICE_NAMES or low in HOST_NAMES:
            out.append((p.pid, name))
            continue
        if all_names and (low.startswith("plaintop") or low.startswith("qml")):
            out.append((p.pid, name))
            continue
        cmd = " ".join(p.info.get("cmdline") or ())
        if low.startswith("python") and any(a in cmd for a in SERVICE_ARGS):
            out.append((p.pid, name))
    return out


def measure(pids):
    """(cpu %, working set bytes) summed over the pids that still exist."""
    cpu = 0.0
    rss = 0
    alive = []
    for pid in pids:
        try:
            p = psutil.Process(pid)
            cpu += p.cpu_percent(interval=None)
            rss += p.memory_info().rss
            alive.append(pid)
        except psutil.Error:
            continue
    return cpu, rss, alive


def main(argv):
    ap = argparse.ArgumentParser(description="the plaintop family's CPU and working set")
    ap.add_argument("--seconds", type=float, default=60.0, help="how long to watch (default 60)")
    ap.add_argument("--interval", type=float, default=1.0, help="seconds between readings (default 1)")
    ap.add_argument("--all", action="store_true", help="match every plaintop*/qml* process by name")
    args = ap.parse_args(argv)

    found = family(args.all)
    if not found:
        print("no plaintop or qml process found — is the port running?", file=sys.stderr)
        return 1
    print("watching:", ", ".join(f"{name} ({pid})" for pid, name in found))
    pids = [pid for pid, _ in found]

    for pid in pids:                       # prime the per-process CPU counters: the first
        try:                               # call always reads 0.0
            psutil.Process(pid).cpu_percent(interval=None)
        except psutil.Error:
            pass
    time.sleep(args.interval)

    cpus, rsses = [], []
    deadline = time.monotonic() + args.seconds
    while time.monotonic() < deadline:
        cpu, rss, pids = measure(pids)
        cpus.append(cpu)
        rsses.append(rss)
        print(f"  cpu {cpu:5.2f}%   working set {rss / MIB:7.1f} MiB   ({len(pids)} procs)")
        if not pids:
            break
        time.sleep(args.interval)

    if not cpus:
        return 1
    avg_cpu = sum(cpus) / len(cpus)
    max_cpu = max(cpus)
    avg_rss = sum(rsses) / len(rsses)
    print(f"summary over {len(cpus)} readings: cpu avg {avg_cpu:.2f}% / max {max_cpu:.2f}% "
          f"(of one core), working set avg {avg_rss / MIB:.1f} MiB / max {max(rsses) / MIB:.1f} MiB, "
          f"{len(pids)} processes at the end")
    print("budget: cpu <= 0.50% (all five shown, no music), working set <= 250 MiB")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
