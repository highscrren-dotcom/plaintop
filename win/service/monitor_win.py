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
    """LHM's own web server, polled every 2 s while it answers. When it does not — LHM
    not running, its server off — the connection is refused at once, and asking every
    2 s would log nothing but cost a thread wake-up each time; so the reader backs off
    to one try every 30 s and the tree is None, meaning "these sensors do not exist"."""

    def __init__(self, url="http://localhost:8085/data.json", every=2.0, retry=30.0):
        self.url, self.every, self.retry = url, every, retry
        self._tree = None

    def tree(self):
        return self._tree

    def fetch(self):
        with urllib.request.urlopen(self.url, timeout=1) as r:
            return json.loads(r.read().decode("utf-8", "replace"))

    def start(self):
        threading.Thread(target=self._loop, daemon=True, name="lhm").start()
        return self

    def _loop(self):
        while True:
            try:
                self._tree = self.fetch()
                time.sleep(self.every)
            except Exception:
                self._tree = None
                time.sleep(self.retry)


# ── The sampler ─────────────────────────────────────────────────────────────────────

class Sampler:
    """One dict in PROTOCOL.md's shape, rebuilt every `interval` seconds by `sample()`.

    `ps` and `clock` are parameters so the stand can hand in readings and a clock of its
    own: the rates (bytes/s) are deltas over this clock, and a real one would make them
    unrepeatable. `windows` gates the probes that only exist there."""

    def __init__(self, interval=1.0, ps=psutil, lhm=None, clock=time.monotonic, windows=WINDOWS):
        self.interval, self.ps, self.lhm, self.clock, self.windows = interval, ps, lhm, clock, windows
        self._lock = threading.Lock()
        self._data = {"stamp": 0.0, "sensors": {}, "processes": [], "coreCount": 0}
        self._prev = None                         # (clock, net counters, disk counters)
        self._slow = {"gateways": {}, "signal": {}, "battery": {}, "cpuCount": None}
        self._static = self._static_sensors()

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
            try:
                self.sample()
            except Exception as e:                # a bad reading must not end the thread
                print(f"monitor sample failed: {e!r}", file=sys.stderr, flush=True)
            time.sleep(self.interval)

    def _slow_loop(self):
        """The Windows probes on their own, slower clocks: the gateway and the socket count
        once, the Wi-Fi signal every 10 s, the battery's WMI figures every 60 s."""
        gateways = parse_route_print(run_hidden(["route", "print", "-4"]))
        count = processor_count()
        with self._lock:
            self._slow["gateways"], self._slow["cpuCount"] = gateways, count
        last_signal = last_battery = 0.0
        while True:
            now = time.monotonic()
            if now - last_signal >= 10:
                last_signal = now
                signal = parse_netsh_wlan(run_hidden(["netsh", "wlan", "show", "interfaces"]))
                with self._lock:
                    self._slow["signal"] = signal
            if now - last_battery >= 60 and self._has_battery():
                last_battery = now
                try:
                    battery = battery_extras(json.loads(powershell(BATTERY_PS) or "{}"))
                except ValueError:
                    battery = {}
                with self._lock:
                    self._slow["battery"] = battery
            time.sleep(1)

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

        net, disk = ps.net_io_counters(pernic=True), ps.disk_io_counters(perdisk=True)
        prev_t, prev_net, prev_disk = self._prev or (now, {}, {})
        dt = max(now - prev_t, 1e-6)

        def rate(old, new):
            return max(0.0, (new - old) / dt) if old is not None else 0.0

        stats, addrs = ps.net_if_stats(), ps.net_if_addrs()
        for name, c in net.items():
            st = stats.get(name)
            ip4 = next((a.address for a in addrs.get(name, []) if a.family == socket.AF_INET), None)
            if not st or not st.isup or not ip4 or VIRTUAL.search(name):
                continue
            old = prev_net.get(name)
            base = f"network/{name}/"
            s[base + "download"] = {"value": rate(old and old.bytes_recv, c.bytes_recv)}
            s[base + "upload"] = {"value": rate(old and old.bytes_sent, c.bytes_sent)}
            s[base + "totalDownload"] = {"value": c.bytes_recv}
            s[base + "totalUpload"] = {"value": c.bytes_sent}
            s[base + "ipv4address"] = {"value": ip4}
            if ip4 in slow["gateways"]:
                s[base + "ipv4gateway"] = {"value": slow["gateways"][ip4]}
            if name in slow["signal"]:
                s[base + "signal"] = {"value": slow["signal"][name]}

        read = write = 0.0
        for name, c in disk.items():
            old = prev_disk.get(name)
            r, w = rate(old and old.read_bytes, c.read_bytes), rate(old and old.write_bytes, c.write_bytes)
            s[f"disk/{name}/read"], s[f"disk/{name}/write"] = {"value": r}, {"value": w}
            read, write = read + r, write + w
        s["disk/all/read"], s["disk/all/write"] = {"value": read}, {"value": write}
        self._prev = (now, net, disk)

        battery = ps.sensors_battery()
        if battery is not None:
            s["power/BAT0/chargePercentage"] = {"value": battery.percent}
            for k, v in slow["battery"].items():
                s[f"power/BAT0/{k}"] = {"value": v}

        tree = self.lhm.tree() if self.lhm else None
        if tree:
            s.update(lhm_sensors(tree, cores))

        data = {"stamp": time.time(), "sensors": s, "processes": self._processes(), "coreCount": cores}
        with self._lock:
            self._data = data
        return data

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

    def _processes(self):
        """[name, cpu %, rss, pid] for the union of the thirty heaviest by CPU and by
        memory. psutil keeps the Process objects between process_iter() calls, so each
        cpu_percent() is the share since the previous tick — the first tick reads zeros,
        which is why the sampler never reports from a single pass. The idle process (pid
        0) would always top the CPU list and is left out."""
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
