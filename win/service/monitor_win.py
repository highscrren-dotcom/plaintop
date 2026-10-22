#!/usr/bin/env python3
"""The `/monitor` producer: ksystemstats' sensor ids from Windows sources.

The shared QML of the monitor asks for ids like `cpu/all/usage` and never learns where
they come from, so this module publishes the same ids with the same units (the table in
PROTOCOL.md) from psutil, `platform`, a few Windows commands and LibreHardwareMonitor's
web server. Everything is sampled on the service's own clock, once a second, into one
dict that `/monitor` hands out as it is: a request never waits for a reading.

Two threads, not one. The per-second tick is psutil only and takes milliseconds. The
Windows-only probes — `route print`, `netsh wlan`, PowerShell for WMI — take seconds
each, so they run in a slow loop of their own and leave their results for the tick to
merge; without them the tick would stall and `/monitor` would stutter visibly.

Nothing here is Windows-only at import time: on Linux the module runs in a degraded mode
(what psutil can read here, the rest absent), which is how the stand in
`tests/win_service.py` exercises it.
"""
import json
import platform
import re
import socket
import subprocess
import sys
import threading
import time
import urllib.request
import ctypes

try:
    import psutil
except ImportError:                     # the stand still imports; the service needs it
    psutil = None

WINDOWS = sys.platform == "win32"
# A console window would flash for every subprocess otherwise: the service has no console.
HIDDEN = {"creationflags": subprocess.CREATE_NO_WINDOW} if WINDOWS else {}

# Adapters that are not the user's link: loopback, Hyper-V/WSL switches, VM host adapters,
# Bluetooth PAN, VPN taps. Matched on the name because psutil has no "virtual" flag.
VIRTUAL = re.compile(r"loopback|vethernet|virtualbox|vmware|bluetooth|\btap\b|wsl|hyper-v"
                     r"|docker|veth|virbr|^br-|^lo$", re.IGNORECASE)
MIB = 1048576


def run_hidden(args, timeout=15):
    """A command's stdout, or "" when it is missing, fails or hangs: a probe that cannot
    answer is a sensor that does not exist, never an exception in the sampler."""
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                              encoding="utf-8", errors="replace", **HIDDEN).stdout
    except Exception:
        return ""


def powershell(script, timeout=20):
    """One PowerShell call, shared with exec_win. -NoProfile: a user's profile can print,
    prompt or take seconds, and every probe here is parsed."""
    if not WINDOWS:
        return ""
    return run_hidden(["powershell", "-NoProfile", "-NonInteractive", "-Command", script], timeout)


def _rate(old, new, dt):
    """Bytes a second between two counter readings; 0.0 without a previous one."""
    return max(0.0, (new - old) / dt) if old is not None else 0.0


_processors = None


def processor_count():
    """Physical processors (sockets), asked of WMI once; 1 wherever WMI is not around."""
    global _processors
    if _processors is None:
        out = powershell("(Get-CimInstance Win32_Processor | Measure-Object).Count").strip()
        _processors = int(out) if out.isdigit() and int(out) > 0 else 1
    return _processors


# ── Pure parsers: text in, numbers out, so the stand can feed them fixtures ──────────

def parse_value(text):
    """LHM's Value strings — "54,0 °C", "1.234 RPM", "2.048,0 MB", "12.0 %" — as a float,
    None when there is no number. LHM formats with the machine's locale, so the decimal
    mark may be either; with both present the last one is the decimal mark. A lone mark
    followed by exactly three digits reads as a thousands group ("1.234 RPM"): LHM
    prints three decimals only for voltages, which nothing here publishes."""
    m = re.match(r"\s*(-?[\d.,]+)", str(text or ""))
    if not m:
        return None
    s = m.group(1)
    if "," in s and "." in s:
        dec = "," if s.rfind(",") > s.rfind(".") else "."
        s = s.replace("." if dec == "," else ",", "").replace(",", ".")
    elif "," in s or "." in s:
        mark = "," if "," in s else "."
        head, _, tail = s.rpartition(mark)
        s = head + tail if len(tail) == 3 and head.lstrip("-") not in ("", "0") else head + "." + tail
    try:
        return float(s)
    except ValueError:
        return None


def slug(text):
    """A hardware name as an lmsensors-style chip id: "Nuvoton NCT6798D" → "nuvoton-nct6798d"."""
    return re.sub(r"[^a-z0-9]+", "-", str(text).lower()).strip("-") or "chip"


def _sensor_type(node):
    """Older LHM builds omit "Type"; the SensorId path still names it (/lpc/x/0/fan/0)."""
    t = node.get("Type")
    if t:
        return t
    parts = str(node.get("SensorId", "")).split("/")
    return {"fan": "Fan", "temperature": "Temperature", "load": "Load", "power": "Power",
            "smalldata": "SmallData", "data": "Data"}.get(parts[-2] if len(parts) > 2 else "", "")


def lhm_sensors(tree, cores):
    """LHM's data.json as sensor ids. A sensor's hardware is its grandparent — leaf under a
    type group ("Temperatures") under the hardware node — and a chip on the mainboard is
    a hardware node of its own, which is why the walk keeps the ancestors rather than a
    depth. The hardware's kind comes from the SensorId's first segment (amdcpu, intelcpu,
    gpu-nvidia, lpc, nvme…): the node texts are localised, the ids are not."""
    groups = []                                   # [(hardware node, [sensor nodes])] in order
    index = {}

    def visit(node, ancestors):
        if node.get("SensorId"):
            hw = ancestors[-2] if len(ancestors) >= 2 else (ancestors[-1] if ancestors else node)
            key = id(hw)
            if key not in index:
                index[key] = len(groups)
                groups.append((hw, []))
            groups[index[key]][1].append(node)
        for child in node.get("Children") or []:
            visit(child, ancestors + [node])

    visit(tree or {}, [])
    out, gpus = {}, 0
    for hw, sensors in groups:
        kind = str(sensors[0].get("SensorId", "")).strip("/").split("/")[0].lower()
        typed = [(_sensor_type(s), str(s.get("Text", "")), parse_value(s.get("Value"))) for s in sensors]
        typed = [t for t in typed if t[2] is not None]
        if "cpu" in kind:
            _cpu(out, typed, cores)
        elif kind.startswith("gpu"):
            _gpu(out, typed, hw.get("Text", ""), gpus)
            gpus += 1
        else:
            chip = ("nvme-" if kind == "nvme" else "") + slug(hw.get("Text", ""))
            for which, label in (("Fan", "fan"), ("Temperature", "temp")):
                n = 0
                for t, text, value in typed:
                    if t == which:
                        n += 1
                        out[f"lmsensors/{chip}/{label}{n}"] = {"value": value, "name": text}
    return out


def _cpu(out, typed, cores):
    """Core #N (1-based, as LHM counts) → cpu/cpu(N-1); the package reading fills every
    core without one of its own, so a chip that reports only a package (AMD's Tctl) still
    shows a temperature on each core the QML asks about."""
    per, package = {}, None
    for t, text, value in typed:
        if t != "Temperature":
            continue
        m = re.search(r"Core #(\d+)", text)
        if m:
            per[int(m.group(1)) - 1] = (value, text)
        elif package is None or "package" in text.lower():
            package = (value, text)
    for i in range(cores):
        value, name = per.get(i, package or (None, ""))
        if value is not None:
            out[f"cpu/cpu{i}/temperature"] = {"value": value, "name": name}


def _gpu(out, typed, name, n):
    """LHM names the card's own load "GPU Core" next to the D3D engines and the memory
    controller, so the names are preferred and the first sensor of the type is only the
    fallback; the memory figures are taken by exact name, since "the first SmallData"
    could be either of them."""
    def pick(which, preferred, exact=False):
        rows = [(text, value) for t, text, value in typed if t == which]
        by_name = dict(rows)
        for want in preferred:
            if want in by_name:
                return by_name[want]
        return None if exact or not rows else rows[0][1]

    base = f"gpu/gpu{n}/"
    out[base + "name"] = {"value": name}
    fields = {"usage": pick("Load", ["GPU Core"]),
              "temperature": pick("Temperature", ["GPU Core"]),
              "power": pick("Power", ["GPU Package", "GPU Power"])}
    used = pick("SmallData", ["GPU Memory Used"], exact=True)
    total = pick("SmallData", ["GPU Memory Total"], exact=True)
    if used is not None:
        fields["usedVram"] = used * MIB
    if total is not None:
        fields["totalVram"] = total * MIB
    for key, value in fields.items():
        if value is not None:
            out[base + key] = {"value": value}


def parse_route_print(text):
    """The default routes of `route print -4`: {interface address: gateway}, the lowest
    metric first when an address has several. Column positions, not labels: the table's
    header is localised, the dotted quads are not."""
    best = {}
    for line in text.splitlines():
        f = line.split()
        if len(f) >= 5 and f[0] == "0.0.0.0" and f[1] == "0.0.0.0":
            metric = int(f[4]) if f[4].isdigit() else 0
            if f[3] not in best or metric < best[f[3]][1]:
                best[f[3]] = (f[2], metric)
    return {addr: gw for addr, (gw, _) in best.items()}


def parse_netsh_wlan(text):
    """{interface name: signal %} from `netsh wlan show interfaces`. The labels ("Name",
    "Signal") are translated on a non-English Windows, so a block is read by shape: its
    first "key : value" line names the interface, its only percentage is the signal."""
    out, name = {}, None
    for line in text.splitlines():
        if ":" not in line:
            if not line.strip():
                name = None                      # a blank line ends the interface block
            continue
        value = line.split(":", 1)[1].strip()
        if name is None:
            name = value
        elif re.fullmatch(r"\d+\s*%", value) and name not in out:
            out[name] = float(value.rstrip("% "))
    return out


def battery_extras(d):
    """root/wmi's BatteryStatus and capacities (mW, mWh) as the ksystemstats fields: the
    rate in W, positive while charging, as batteryText() in the QML reads the sign."""
    def num(key):
        v = d.get(key)
        return float(v) if isinstance(v, (int, float)) else None

    out = {}
    charge, discharge = num("chargeRate"), num("dischargeRate")
    if charge is not None or discharge is not None:
        out["chargeRate"] = ((charge or 0) - (discharge or 0)) / 1000
    if num("remaining") is not None:
        out["charge"] = num("remaining") / 1000
    if num("full"):
        out["capacity"] = num("full") / 1000
        if num("designed"):
            out["health"] = num("full") * 100 / num("designed")
    return out


BATTERY_PS = (
    "$s = Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue | Select-Object -First 1;"
    "$f = Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1;"
    "$d = Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue | Select-Object -First 1;"
    "@{chargeRate=$s.ChargeRate; dischargeRate=$s.DischargeRate; remaining=$s.RemainingCapacity;"
    " full=$f.FullChargedCapacity; designed=$d.DesignedCapacity} | ConvertTo-Json -Compress")


# ── LibreHardwareMonitor ────────────────────────────────────────────────────────────

class LHM:
    """LHM's own web server, polled every 5 s while it answers. When it does not — LHM
    not running, its server off — the connection is refused at once, and asking every
    5 s would log nothing but cost a thread wake-up each time; so the reader backs off
    to one try every 30 s and the tree is None, meaning "these sensors do not exist".

    `demand` (the monitor visible, its block shown) turns the fetch off where nothing
    reads it; the last tree is kept, so a monitor that comes back does not blank first."""

    def __init__(self, url="http://localhost:8085/data.json", every=5.0, retry=30.0,
                 perf=None, demand=None, every_source=None):
        self.url, self.every, self.retry = url, every, retry
        self.perf, self.demand, self.every_source = perf, demand, every_source
        self._tree = None

    def tree(self):
        return self._tree

    def fetch(self):
        with urllib.request.urlopen(self.url, timeout=1) as r:
            return json.loads(r.read().decode("utf-8", "replace"))

    def start(self):
        threading.Thread(target=self._loop, daemon=True, name="lhm").start()
        return self

    def _every(self):
        """The interval the settings ask for now (the page offers it), the constructor's
        value where there is no source; a floor keeps a zero from spinning the thread."""
        if self.every_source is None:
            return float(self.every)
        try:
            return max(0.5, float(self.every_source()))
        except Exception:
            return float(self.every)

    def _loop(self):
        while True:
            if self.demand is not None and not self.demand():
                time.sleep(1.0)
                continue
            try:
                t0 = time.monotonic()
                self._tree = self.fetch()
                if self.perf is not None:
                    self.perf.record("lhm", (time.monotonic() - t0) * 1000.0)
                time.sleep(self._every())
            except Exception:
                self._tree = None
                time.sleep(self.retry)


# ── The sampler ─────────────────────────────────────────────────────────────────────

# ── the native process snapshot (Phase 4 of the Windows budget) ────────────────────────
# psutil's process_iter opens every process to read its times and working set — measured at
# 1.5 s for 370 processes on the acceptance machine, where a security agent sits on every
# OpenProcess. NtQuerySystemInformation(SystemProcessInformation) returns the same fields
# for the whole machine in one call, opening nothing: ~10 ms for the same list here. The
# struct is documented (winternl.h) and its offsets are asserted by the stand, so a
# mis-sized field fails loudly rather than reading the wrong number.

class _UNICODE_STRING(ctypes.Structure):
    _fields_ = [("Length", ctypes.c_ushort), ("MaximumLength", ctypes.c_ushort),
                ("Buffer", ctypes.c_wchar_p)]


class SYSTEM_PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("NextEntryOffset", ctypes.c_ulong), ("NumberOfThreads", ctypes.c_ulong),
        ("WorkingSetPrivateSize", ctypes.c_longlong), ("HardFaultCount", ctypes.c_ulong),
        ("NumberOfThreadsHighWatermark", ctypes.c_ulong), ("CycleTime", ctypes.c_ulonglong),
        ("CreateTime", ctypes.c_longlong), ("UserTime", ctypes.c_longlong),
        ("KernelTime", ctypes.c_longlong), ("ImageName", _UNICODE_STRING),
        ("BasePriority", ctypes.c_long), ("UniqueProcessId", ctypes.c_void_p),
        ("InheritedFromUniqueProcessId", ctypes.c_void_p), ("HandleCount", ctypes.c_ulong),
        ("SessionId", ctypes.c_ulong), ("UniqueProcessKey", ctypes.c_void_p),
        ("PeakVirtualSize", ctypes.c_size_t), ("VirtualSize", ctypes.c_size_t),
        ("PageFaultCount", ctypes.c_ulong), ("PeakWorkingSetSize", ctypes.c_size_t),
        ("WorkingSetSize", ctypes.c_size_t), ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPagedPoolUsage", ctypes.c_size_t), ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
        ("QuotaNonPagedPoolUsage", ctypes.c_size_t), ("PagefileUsage", ctypes.c_size_t),
        ("PeakPagefileUsage", ctypes.c_size_t), ("PrivatePageCount", ctypes.c_size_t),
        ("ReadOperationCount", ctypes.c_longlong), ("WriteOperationCount", ctypes.c_longlong),
        ("OtherOperationCount", ctypes.c_longlong), ("ReadTransferCount", ctypes.c_longlong),
        ("WriteTransferCount", ctypes.c_longlong), ("OtherTransferCount", ctypes.c_longlong),
    ]


SYSTEM_PROCESS_INFORMATION_CLASS = 5
STATUS_INFO_LENGTH_MISMATCH = 0xC0000004


def native_process_entries():
    """[{name, pid, cpu (seconds), rss (bytes)}] for every process in one call; [] off
    Windows or where the call is refused (a locked-down machine). No process is opened."""
    if not WINDOWS:
        return []
    try:
        ntdll = ctypes.WinDLL("ntdll")
    except OSError:
        return []
    fn = ntdll.NtQuerySystemInformation
    fn.restype = ctypes.c_ulong
    fn.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong)]
    size = 1 << 20
    buf = None
    for _ in range(6):                                  # grow until the list fits
        buf = ctypes.create_string_buffer(size)
        needed = ctypes.c_ulong(0)
        status = fn(SYSTEM_PROCESS_INFORMATION_CLASS, buf, size, ctypes.byref(needed))
        if status == STATUS_INFO_LENGTH_MISMATCH:
            size = needed.value + 65536 if needed.value else size * 2
            continue
        if status != 0:
            return []
        break
    else:
        return []
    out = []
    offset = 0
    while True:
        entry = SYSTEM_PROCESS_INFORMATION.from_buffer(buf, offset)
        name = ""
        if entry.ImageName.Buffer and entry.ImageName.Length:
            name = ctypes.wstring_at(entry.ImageName.Buffer, entry.ImageName.Length // 2)
        out.append({"name": name, "pid": int(entry.UniqueProcessId or 0),
                    "cpu": (entry.UserTime + entry.KernelTime) / 1e7,   # 100-ns units → s
                    "rss": int(entry.WorkingSetSize)})
        if entry.NextEntryOffset == 0:
            break
        offset += entry.NextEntryOffset
    return out


def native_process_rows(entries, previous, dt, count=30):
    """[name, cpu %, rss, pid] from a snapshot: the CPU share is the CPU time since the
    previous snapshot over its wall time (a process seen for the first time reads 0, as
    psutil's first call does), and the rows are the union of the `count` heaviest by CPU
    and by memory — the very selection Sampler._processes makes. Pure: the stand feeds it
    fixtures."""
    rows = []
    for e in entries:
        pid = int(e.get("pid") or 0)
        if not pid:                                     # pid 0 is the idle process
            continue
        cpu_time = float(e.get("cpu") or 0.0)
        before = previous.get(pid)
        pct = max(0.0, (cpu_time - before) / dt * 100.0) if before is not None and dt > 0 else 0.0
        rows.append([str(e.get("name") or ""), pct, int(e.get("rss") or 0), pid])
    top = {r[3]: r for r in sorted(rows, key=lambda r: r[1], reverse=True)[:count]}
    top.update({r[3]: r for r in sorted(rows, key=lambda r: r[2], reverse=True)[:count]})
    return list(top.values())


class NativeProcesses:
    """The native snapshot with the previous CPU times kept for the shares, packaged as the
    same rows the psutil walk returns. rows() is None where the call is unavailable, so the
    caller falls back to psutil."""

    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self._prev = {}
        self._at = None

    def rows(self):
        entries = native_process_entries()
        if not entries:
            return None
        now = self.clock()
        dt = (now - self._at) if self._at is not None else 0.0
        out = native_process_rows(entries, self._prev, dt)
        self._prev = {pid: float(e.get("cpu") or 0.0) for pid, e in
                      ((int(e.get("pid") or 0), e) for e in entries) if pid}
        self._at = now
        return out


def enabled_blocks(store):
    """The monitor's enabled block types from its own description (the settings'
    `blocksJson`), or None while the packaged default is in use — every block of that
    default is enabled, so None means "everything the default shows". A description that is
    absent or does not parse reads the same way: the safe answer is to keep collecting,
    never to go silent because a setting could not be understood."""
    if store is None:
        return None
    try:
        raw = store.get("monitor")[1].get("blocksJson")
    except Exception:
        return None
    if not str(raw or "").strip():
        return None
    try:
        blocks = json.loads(raw)
    except ValueError:
        return None
    if not isinstance(blocks, list):
        return None
    return {str(b.get("type")) for b in blocks
            if isinstance(b, dict) and b.get("enabled") is not False}


def block_wanted(store, kind):
    """Whether a block of this type is enabled: True while the packaged default rules."""
    blocks = enabled_blocks(store)
    return True if blocks is None else kind in blocks


def wants_processes(store):
    """Whether any enabled cpu/memory block draws a top-processes list — the one thing that
    makes the service walk every process. With the packaged default (no `blocksJson`) the
    answer is yes, since that default shows five; only a description with the count taken
    to zero (or those blocks turned off) lets the walk be skipped."""
    if store is None:
        return True
    try:
        raw = store.get("monitor")[1].get("blocksJson")
    except Exception:
        return True
    if not str(raw or "").strip():
        return True
    try:
        blocks = json.loads(raw)
    except ValueError:
        return True
    if not isinstance(blocks, list):
        return True
    for b in blocks:
        if not isinstance(b, dict) or b.get("enabled") is False:
            continue
        if b.get("type") not in ("cpu", "memory"):
            continue
        try:
            tops = float((b.get("params") or {}).get("top_processes") or 0)
        except (TypeError, ValueError):
            tops = 0.0
        if tops > 0:
            return True
    return False


class Sampler:
    """One dict in PROTOCOL.md's shape, rebuilt every `interval` seconds by `sample()`.

    `ps` and `clock` are parameters so the stand can hand in readings and a clock of its
    own: the rates (bytes/s) are deltas over this clock, and a real one would make them
    unrepeatable. `windows` gates the probes that only exist there.

    Three callables decide what is worth collecting, so a hidden or disinterested monitor
    costs nothing (Phase 1/3 of the Windows budget): `visible()` is the monitor on screen,
    `need_processes()` whether any enabled block draws a process list, `want_block(kind)` a
    probe's own block. All three default to True, which is what the stand sees: with no
    callables the sampler does exactly what it always did. `process_interval` (seconds,
    0 = every tick) is the new floor for the process walk, the most expensive reading here."""

    def __init__(self, interval=1.0, ps=psutil, lhm=None, clock=time.monotonic, windows=WINDOWS,
                 gpu=None, perf=None, process_interval=0.0, visible=None, need_processes=None,
                 want_block=None, native=None, net_interval=0.0,
                 interval_source=None, process_interval_source=None, net_interval_source=None):
        self.interval, self.ps, self.lhm, self.clock, self.windows = interval, ps, lhm, clock, windows
        self.gpu = gpu                            # gpu_win.Reader: the counters, under LHM's ids
        self.perf = perf                          # perf.Perf: the /perf meters, or None
        self.native = native                      # NativeProcesses: the one-call walk, or None
        self.process_interval = float(process_interval or 0.0)
        # The same three numbers read again while the service runs (settings_store.LiveSettings
        # through server.main): the settings window offers them, so turning one down has to be
        # felt on the next tick rather than at the next restart. None keeps the constructor's
        # value, which is what the stand passes, so a Sampler with no sources behaves as before.
        self._interval_source = interval_source
        self._process_interval_source = process_interval_source
        self._net_interval_source = net_interval_source
        # The network lines' own floor: their three psutil calls are the priciest thing left
        # in the tick (~30 ms on the desk's machine, GetAdaptersAddresses and the counters),
        # so they run every net_interval seconds and the same lines are republished in
        # between. The adapter facts (names, addresses, up/down) change rarely and are
        # cached for net_facts_interval — a minute of staleness on an address line costs
        # nothing, and it takes the two more expensive calls out of every other read.
        # 0 = every tick, which is what the stand sees.
        self.net_interval = float(net_interval or 0.0)
        self.net_facts_interval = 60.0
        self._net_at = 0.0
        self._net_sensors = {}
        self._net_prev = None
        self._net_facts_at = 0.0
        self._net_stats = {}
        self._net_addrs = {}
        self._visible = visible or (lambda: True)
        self._need_processes = need_processes or (lambda: True)
        self._want_block = want_block or (lambda kind: True)
        self._lock = threading.Lock()
        self._data = {"stamp": 0.0, "sensors": {}, "processes": [], "coreCount": 0}
        self._prev = None                         # (clock, net counters, disk counters)
        self._slow = {"gateways": {}, "signal": {}, "battery": {}, "cpuCount": None}
        self._processes_rows = None               # the last walk, kept for process_interval
        self._processes_at = 0.0
        self._static = self._static_sensors()

    def visible(self):
        try:
            return bool(self._visible())
        except Exception:
            return True

    def need_processes(self):
        try:
            return bool(self._need_processes())
        except Exception:
            return True

    def want_block(self, kind):
        try:
            return bool(self._want_block(kind))
        except Exception:
            return True

    def live(self, source, fallback):
        """One of the three rates, read again from the settings while the service runs; the
        constructor's value stands where no source was given or the store answers junk."""
        if source is None:
            return float(fallback)
        try:
            return float(source())
        except Exception:
            return float(fallback)

    def live_interval(self):
        return max(0.1, self.live(self._interval_source, self.interval))

    def start(self):
        threading.Thread(target=self._loop, daemon=True, name="sampler").start()
        if self.windows:
            threading.Thread(target=self._slow_loop, daemon=True, name="probes").start()
        return self

    def snapshot(self):
        with self._lock:
            return self._data

    def _loop(self):
        while True:
            interval = self.live_interval()
            if not self.visible():
                # Nothing draws the monitor (Win+D, or the window is gone): the tick itself
                # is parked, not just its probes — no psutil call is made at all, and
                # /monitor keeps its last answer. Two seconds, so a window that comes back
                # is fresh within the host's own two-second poll. Its probes are skipped
                # separately in _processes_if_wanted and _network, and the slow loop and the
                # capture check the same word.
                time.sleep(max(interval, 2.0))
                continue
            try:
                self.sample()
            except Exception as e:                # a bad reading must not end the thread
                print(f"monitor sample failed: {e!r}", file=sys.stderr, flush=True)
            time.sleep(interval)

    def _slow_loop(self):
        """The Windows probes on their own, slower clocks: the gateway and the socket count
        once, the Wi-Fi signal every 15 s and the battery's WMI figures every 5 minutes.
        Each runs only where a monitor is looking and its block is on — a Wi-Fi reading
        nobody draws is a subprocess nobody needs (`netsh` is started only where a wireless
        adapter exists at all, so a desktop without one never pays for it)."""
        gateways = parse_route_print(run_hidden(["route", "print", "-4"]))
        count = processor_count()
        wireless = self._wireless()
        with self._lock:
            self._slow["gateways"], self._slow["cpuCount"] = gateways, count
        last_signal = last_battery = 0.0
        while True:
            now = time.monotonic()
            if now - last_signal >= 15:
                last_signal = now
                if wireless and self.visible() and self.want_block("network"):
                    signal = parse_netsh_wlan(run_hidden(["netsh", "wlan", "show", "interfaces"]))
                    with self._lock:
                        self._slow["signal"] = signal
            if now - last_battery >= 300:
                last_battery = now
                if self.visible() and self.want_block("battery") and self._has_battery():
                    try:
                        battery = battery_extras(json.loads(powershell(BATTERY_PS) or "{}"))
                    except ValueError:
                        battery = {}
                    with self._lock:
                        self._slow["battery"] = battery
            time.sleep(1)

    def _wireless(self):
        """Whether a wireless adapter exists at all, by name: psutil has no "wireless"
        flag, the same guess this file makes for the virtual-adapter filter."""
        try:
            names = self.ps.net_if_stats() or {}
        except Exception:
            return False
        return any(re.search(r"wi-?fi|wlan|wireless", name, re.IGNORECASE) for name in names)

    def _has_battery(self):
        try:
            return self.ps.sensors_battery() is not None
        except Exception:                             # psutil raises on some machines rather than None
            return False

    @staticmethod
    def _static_sensors():
        """Hostname, OS name and kernel never change while the service runs. Windows 11
        still reports release "10" to Python: the build number tells them apart."""
        if WINDOWS:
            build = platform.version().split(".")[-1]
            release = "11" if build.isdigit() and int(build) >= 22000 else platform.release()
            edition = platform.win32_edition() if hasattr(platform, "win32_edition") else ""
            name = " ".join(x for x in ("Windows", release, edition or "") if x)
            kernel = platform.version()
        else:
            pretty = getattr(platform, "freedesktop_os_release", lambda: {})()
            name = (pretty or {}).get("PRETTY_NAME") or f"{platform.system()} {platform.release()}"
            kernel = platform.release()
        return {"os/system/hostname": {"value": platform.node()},
                "os/system/name": {"value": name},
                "os/kernel/version": {"value": kernel}}

    def sample(self):
        """One rebuilt dict, with its cost recorded for /perf (the tick alone and the
        process walk inside it, separately — that walk is the expensive one)."""
        t0 = time.monotonic()
        data = self._sample()
        if self.perf is not None:
            self.perf.record("sample", (time.monotonic() - t0) * 1000.0)
        return data

    def _sample(self):
        ps, now = self.ps, self.clock()
        s = dict(self._static)
        with self._lock:
            slow = {k: dict(v) if isinstance(v, dict) else v for k, v in self._slow.items()}

        per = ps.cpu_percent(percpu=True) or [0.0]
        cores = len(per)
        s["cpu/all/usage"] = {"value": sum(per) / cores}
        for i, v in enumerate(per):
            s[f"cpu/cpu{i}/usage"] = {"value": v}
        for i, f in enumerate(self._frequencies(cores)):
            s[f"cpu/cpu{i}/frequency"] = {"value": f}
        s["cpu/all/coreCount"] = {"value": cores}
        s["cpu/all/cpuCount"] = {"value": slow["cpuCount"] or 1}
        try:
            for k, v in zip(("1", "5", "15"), ps.getloadavg()):
                s[f"cpu/loadaverages/loadaverage{k}"] = {"value": v}
        except (AttributeError, OSError):
            pass

        vm, sw = ps.virtual_memory(), ps.swap_memory()
        s["memory/physical/total"] = {"value": vm.total}
        s["memory/physical/used"] = {"value": vm.total - vm.available}
        s["memory/physical/usedPercent"] = {"value": vm.percent}
        s["memory/swap/total"] = {"value": sw.total}
        s["memory/swap/used"] = {"value": sw.used}
        s["os/system/uptime"] = {"value": time.time() - ps.boot_time()}

        s.update(self._network(now, ps, slow))

        disk = ps.disk_io_counters(perdisk=True)
        prev_t, _, prev_disk = self._prev or (now, {}, {})
        dt = max(now - prev_t, 1e-6)
        read = write = 0.0
        for name, c in disk.items():
            old = prev_disk.get(name)
            r, w = _rate(old and old.read_bytes, c.read_bytes, dt), _rate(old and old.write_bytes, c.write_bytes, dt)
            s[f"disk/{name}/read"], s[f"disk/{name}/write"] = {"value": r}, {"value": w}
            read, write = read + r, write + w
        s["disk/all/read"], s["disk/all/write"] = {"value": read}, {"value": write}
        self._prev = (now, {}, disk)

        battery = ps.sensors_battery()
        if battery is not None:
            s["power/BAT0/chargePercentage"] = {"value": battery.percent}
            for k, v in slow["battery"].items():
                s[f"power/BAT0/{k}"] = {"value": v}

        tree = self.lhm.tree() if self.lhm else None
        if tree:
            s.update(lhm_sensors(tree, cores))
        # The counters' GPU figures fill in what LHM did not give (everything, without LHM).
        if self.gpu is not None:
            for k, v in self.gpu.sensors().items():
                s.setdefault(k, v)

        data = {"stamp": time.time(), "sensors": s, "processes": self._processes_if_wanted(now), "coreCount": cores}
        with self._lock:
            self._data = data
        return data

    def _processes_if_wanted(self, now):
        """The process walk, the one reading that costs: skipped while no enabled block
        shows a list or the monitor is off screen, and no more often than process_interval
        seconds otherwise — the rows are re-published unchanged in between, which is what
        the model reads anyway (it keeps the previous rows when a tick brings none)."""
        if not (self.need_processes() and self.visible()):
            self._processes_rows = None
            return []
        every = self.live(self._process_interval_source, self.process_interval)
        if (self._processes_rows is not None and every > 0
                and now - self._processes_at < every):
            return self._processes_rows
        t0 = time.monotonic()
        rows = self._processes()
        if self.perf is not None:
            self.perf.record("processes", (time.monotonic() - t0) * 1000.0)
        self._processes_rows, self._processes_at = rows, now
        return rows

    def _frequencies(self, cores):
        """One MHz value per core; psutil on Windows knows only one, so it is repeated."""
        try:
            freqs = self.ps.cpu_freq(percpu=True) or []
            if len(freqs) != cores:
                one = self.ps.cpu_freq()
                freqs = [one] * cores if one else []
            return [f.current for f in freqs]
        except Exception:
            return []

    def _network(self, now, ps, slow):
        """The `network/<iface>/…` lines, at `net_interval` seconds and no oftener.
        `ps.net_io_counters(pernic)`, `net_if_stats` and `net_if_addrs` are, after the
        process walk, the priciest part of the tick (the first two walk every adapter
        through Windows' own APIs: ~30 ms on the desk's machine), which is why the lines are
        published unchanged between reads — the rates are honest because the delta is taken
        over the real gap. Nothing is read while the monitor is off screen or its network
        block is off; then the lines simply do not exist, as `pressure/*` on Windows."""
        due = (self.net_interval <= 0 or self._net_at == 0.0
               or now - self._net_at >= self.net_interval)
        if self._net_interval_source is not None:
            every = self.live(self._net_interval_source, self.net_interval)
            due = every <= 0 or self._net_at == 0.0 or now - self._net_at >= every
        if not due:
            return self._net_sensors
        self._net_at = now
        if not (self.visible() and self.want_block("network")):
            self._net_sensors = {}
            return {}
        counters = ps.net_io_counters(pernic=True)
        if self._net_facts_at == 0.0 or now - self._net_facts_at >= self.net_facts_interval:
            self._net_stats, self._net_addrs = ps.net_if_stats(), ps.net_if_addrs()
            self._net_facts_at = now
        stats, addrs = self._net_stats, self._net_addrs
        prev_t, prev_net, _ = self._net_prev or (now, {}, {})
        dt = max(now - prev_t, 1e-6)
        out = {}
        for name, c in counters.items():
            st = stats.get(name)
            ip4 = next((a.address for a in addrs.get(name, []) if a.family == socket.AF_INET), None)
            if not st or not st.isup or not ip4 or VIRTUAL.search(name):
                continue
            old = prev_net.get(name)
            base = f"network/{name}/"
            out[base + "download"] = {"value": _rate(old and old.bytes_recv, c.bytes_recv, dt)}
            out[base + "upload"] = {"value": _rate(old and old.bytes_sent, c.bytes_sent, dt)}
            out[base + "totalDownload"] = {"value": c.bytes_recv}
            out[base + "totalUpload"] = {"value": c.bytes_sent}
            out[base + "ipv4address"] = {"value": ip4}
            if ip4 in slow["gateways"]:
                out[base + "ipv4gateway"] = {"value": slow["gateways"][ip4]}
            if name in slow["signal"]:
                out[base + "signal"] = {"value": slow["signal"][name]}
        self._net_prev = (now, counters, {})
        self._net_sensors = out
        return out

    def _processes(self):
        """[name, cpu %, rss, pid] for the union of the thirty heaviest by CPU and by
        memory. On Windows the native one-call snapshot answers (Phase 4: psutil opens every
        process, ~1.5 s for 370 of them behind a security agent; the native call is ~10 ms);
        where it is unavailable the psutil walk below stands in. psutil keeps the Process
        objects between process_iter() calls, so each cpu_percent() is the share since the
        previous tick — the first tick reads zeros, which is why the sampler never reports
        from a single pass. The idle process (pid 0) would always top the CPU list and is
        left out."""
        if self.native is not None:
            rows = self.native.rows()
            if rows is not None:
                return rows
        rows = []
        for p in self.ps.process_iter(["name", "pid", "cpu_percent", "memory_info"]):
            i = p.info
            if not i.get("pid"):
                continue
            mem = i.get("memory_info")
            rows.append([i.get("name") or "", float(i.get("cpu_percent") or 0.0),
                         int(mem.rss) if mem else 0, int(i["pid"])])
        top = {r[3]: r for r in sorted(rows, key=lambda r: r[1], reverse=True)[:30]}
        top.update({r[3]: r for r in sorted(rows, key=lambda r: r[2], reverse=True)[:30]})
        return list(top.values())


if __name__ == "__main__":
    # A look at what this machine publishes, without the server.
    sampler = Sampler()
    sampler.sample()
    time.sleep(1)
    print(json.dumps(sampler.sample(), indent=1, default=str))
