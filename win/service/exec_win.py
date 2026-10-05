#!/usr/bin/env python3
"""Answers for `/exec`: the monitor's Linux command lines, from Windows sources.

`MonitorData.qml` is shared with the Plasma widget unchanged, so it keeps building the
command lines of a Linux desktop — `LC_ALL=C lscpu`, `bash …/health.sh 3`, `df`. Rather
than teach the QML about Windows, the service recognises the lines the monitor is known
to run and answers each in the output format the QML already parses; the scripts under
`monitor/package/contents/code/` are the reference for those formats, line for line.
Anything it does not recognise is a `command` block of the user's own and goes to the
shell, as the Plasma engine would run it.

Recognition is by the script's base name and the command's first word, never by the
directory: the hosts may live anywhere, and the QML writes POSIX quoting (`shlex`).

The action items the active lines offer (`kill`, `systemctl`, a konsole) are not
translated yet: the Windows host ships with the active lines off.
"""
import math
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime

import monitor_win as mw            # powershell(), run_hidden(), the shared subprocess flags

try:
    import psutil
except ImportError:
    psutil = None
try:
    import winreg
except ImportError:
    winreg = None

WINDOWS = mw.WINDOWS
HIDDEN = mw.HIDDEN
SCRIPTS = ("services.sh", "health.sh", "units.sh", "sound.sh", "repos.sh", "peripherals.sh")
# The host appends " # <ms>" to an action's command so the same text runs twice; the QML's
# own lines end in "2>/dev/null". cmd.exe knows neither, so both go before anything runs.
NONCE = re.compile(r"\s*#\s*\d+\s*$")
DEVNULL = re.compile(r"\s*2>/dev/null\s*$")


class Cached:
    """A value refreshed at most every `ttl` seconds. A `background` cache never makes a
    request wait: a stale read returns what it has — None before the first result — and
    starts the producer in a thread of its own, which is what a 30-second winget needs."""

    def __init__(self, ttl, producer, background=False):
        self.ttl, self.producer, self.background = ttl, producer, background
        self.value, self.stamp, self.running = None, None, False
        self.lock = threading.Lock()

    def get(self):
        with self.lock:
            fresh = self.stamp is not None and time.monotonic() - self.stamp < self.ttl
            if fresh:
                return self.value
            if self.background:
                if not self.running:
                    self.running = True
                    threading.Thread(target=self._refresh, daemon=True).start()
                return self.value
        self._refresh()
        return self.value

    def _refresh(self):
        try:
            value = self.producer()
        except Exception:
            value = None
        with self.lock:
            self.value, self.stamp, self.running = value, time.monotonic(), False


# ── Recognition ─────────────────────────────────────────────────────────────────────

def dispatch(command):
    """(emulator name, its arguments) for a command line, ("shell", [text]) for the rest."""
    text = DEVNULL.sub("", NONCE.sub("", command.strip()))
    try:
        args = shlex.split(text, posix=True)
    except ValueError:
        return "shell", [text]
    while args and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", args[0]):
        args.pop(0)                                   # LC_ALL=C and the like
    if len(args) >= 3 and args[0] == "timeout":
        args = args[2:]
    if not args:
        return "shell", [text]
    head = args[0]
    if head == "bash" and len(args) >= 2:
        # The path comes from Qt.resolvedUrl, with forward slashes even on Windows; a
        # backslash in it would be an escape under POSIX quoting, as the QML writes it.
        base = os.path.basename(args[1])
        if base in SCRIPTS:
            return base[:-3], args[2:]
    if head == "cat" and len(args) >= 2:
        if "cpulist" in args[1]:
            return "cpulist", []
        if "board_vendor" in args[1]:
            return "board", []
        if args[1] == "/proc/loadavg":
            return "loadavg", []
    if head == "lscpu":
        return "lscpu", []
    if head == "df":
        return "df", args[1:]
    return "shell", [text]


def run(command):
    """The `/exec` answer: {"stdout", "stderr", "exit code"}, the executable engine's keys."""
    name, args = dispatch(command)
    if name == "shell":
        return shell(args[0])
    try:
        out = EMULATORS[name](args)
    except Exception as e:                            # an emulator's bug is a failed command
        return {"stdout": "", "stderr": repr(e), "exit code": 1}
    if isinstance(out, tuple):
        stdout, stderr, code = out
        return {"stdout": stdout, "stderr": stderr, "exit code": code}
    return {"stdout": out, "stderr": "", "exit code": 0}


def shell(text):
    """The user's own command through the shell (cmd.exe /c here), 10 s at most."""
    try:
        r = subprocess.run(text, shell=True, capture_output=True, text=True, timeout=10,
                           encoding="utf-8", errors="replace", **HIDDEN)
    except subprocess.TimeoutExpired as e:
        return {"stdout": e.stdout or "", "stderr": "timeout", "exit code": 124}
    except Exception as e:
        return {"stdout": "", "stderr": repr(e), "exit code": 1}
    return {"stdout": r.stdout, "stderr": r.stderr, "exit code": r.returncode}


# ── cat …/cpulist, lscpu, cat …/board_*, cat /proc/loadavg ─────────────────────────

def ranges(cpus):
    """A set of cpu numbers as the kernel's cpulist: {0,1,2,3,8,9} → "0-3,8-9"."""
    cpus, out = sorted(cpus), []
    while cpus:
        lo = hi = cpus.pop(0)
        while cpus and cpus[0] == hi + 1:
            hi = cpus.pop(0)
        out.append(str(lo) if lo == hi else f"{lo}-{hi}")
    return ",".join(out)


def numa_masks():
    """The processor mask of every NUMA node, from kernel32; [] where there is no answer.
    GetNumaNodeProcessorMask covers the first processor group only (64 logical CPUs)."""
    if not WINDOWS:
        return []
    try:
        import ctypes
        k = ctypes.windll.kernel32
        highest = ctypes.c_ulong()
        if not k.GetNumaHighestNodeNumber(ctypes.byref(highest)):
            return []
        out = []
        for node in range(highest.value + 1):
            mask = ctypes.c_ulonglong()
            if k.GetNumaNodeProcessorMask(ctypes.c_ubyte(node), ctypes.byref(mask)) and mask.value:
                out.append(mask.value)
        return out
    except Exception:
        return []


def cpulist(args):
    n = os.cpu_count() or 1
    masks = numa_masks()
    if not masks:
        return ranges(range(n)) + "\n"
    return "".join(ranges(i for i in range(64) if m >> i & 1) + "\n" for m in masks)


def cpu_model():
    if winreg:
        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"HARDWARE\DESCRIPTION\System\CentralProcessor\0") as k:
                return str(winreg.QueryValueEx(k, "ProcessorNameString")[0]).strip()
        except OSError:
            pass
    try:
        with open("/proc/cpuinfo", encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.startswith("model name"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or platform.machine()


def lscpu(args):
    """The five lines parseLscpu() reads; the counts from psutil and WMI, since Windows
    has no lscpu and WMI's sockets are what `cpu/all/cpuCount` shows anyway. CPU(s) is the
    thread count itself: a hybrid CPU (performance cores with two threads beside efficiency
    cores with one) has no whole number of threads per core, and an integer division of
    threads by cores made the first desk's line say 20c/20t for 20 cores and 28 threads."""
    logical = os.cpu_count() or 1
    physical = (psutil.cpu_count(logical=False) if psutil else None) or logical
    sockets = max(1, mw.processor_count())
    return (f"Model name:            {cpu_model()}\n"
            f"CPU(s):                {logical}\n"
            f"Socket(s):             {sockets}\n"
            f"Core(s) per socket:    {max(1, physical // sockets)}\n"
            f"Thread(s) per core:    {max(1, round(logical / physical))}\n")


def board_lines():
    """Vendor, board, BIOS version: the registry's SMBIOS copy on Windows, sysfs elsewhere."""
    if winreg:
        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"HARDWARE\DESCRIPTION\System\BIOS") as k:
                out = []
                for name in ("BaseBoardManufacturer", "BaseBoardProduct", "BIOSVersion"):
                    v = winreg.QueryValueEx(k, name)[0]
                    out.append(str(v[0] if isinstance(v, list) and v else v).strip())
                return out
        except OSError:
            return []
    out = []
    for name in ("board_vendor", "board_name", "bios_version"):
        try:
            with open(f"/sys/devices/virtual/dmi/id/{name}", encoding="utf-8", errors="replace") as f:
                out.append(f.read().strip())
        except OSError:
            return []
    return out


def board(args):
    lines = board_lines()
    if len(lines) < 3:
        return "", "", 1                          # parseBoard() runs on exit code 0 only
    return "".join(line + "\n" for line in lines)


def loadavg(args):
    try:
        l1, l5, l15 = psutil.getloadavg()
    except Exception:
        l1 = l5 = l15 = 0.0
    return f"{l1:.2f} {l5:.2f} {l15:.2f} 0/0 0\n"


# ── df ──────────────────────────────────────────────────────────────────────────────

def df_target(target, nt=WINDOWS):
    """The path to measure for a mount the description names: "/" is the system drive,
    "D:" or "D:\\" that drive. Printed back as given, so the QML's rows keep their keys."""
    if not nt:
        return target
    if target == "/":
        return os.environ.get("SystemDrive", "C:") + "\\"
    if re.match(r"^[A-Za-z]:", target):
        return target[:2] + "\\"
    return target


def df(args):
    """A header line, then "target size used N%" per mount, as `df -B1 --output=target,
    size,used,pcent` prints them; the header is skipped by the QML, so its words do not
    matter. Use% is df's: used over used+free, rounded up."""
    rows, errors, code = ["Mounted on          1B-blocks        Used Use%"], [], 0
    for target in (a for a in args if not a.startswith("-")):
        try:
            u = psutil.disk_usage(df_target(target)) if psutil else shutil.disk_usage(df_target(target))
        except Exception as e:
            errors.append(f"df: {target}: {e}")
            code = 1
            continue
        pct = math.ceil(u.used * 100 / (u.used + u.free)) if u.used + u.free else 0
        rows.append(f"{target} {u.total} {u.used} {pct}%")
    return "".join(r + "\n" for r in rows), "".join(e + "\n" for e in errors), code


# ── services.sh ─────────────────────────────────────────────────────────────────────

def container_engine(engine):
    """"docker|running|total", "docker|noaccess", or None without the engine: one `ps -a`
    with the state column, as the script does."""
    if not shutil.which(engine):
        return None
    try:
        r = subprocess.run([engine, "ps", "-a", "--format", "{{.State}}"], capture_output=True,
                           text=True, timeout=5, **HIDDEN)
    except Exception:
        return f"{engine}|noaccess"
    if r.returncode != 0:
        return f"{engine}|noaccess"
    states = [s for s in r.stdout.split() if s]
    up = sum(1 for s in states if s in ("running", "paused", "restarting"))
    return f"{engine}|{up}|{len(states)}"


def ollama_line():
    """What ollama has loaded: the API first (cheap), the CLI when it does not answer."""
    host = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434")
    host = host if host.startswith("http") else "http://" + host
    key = '"name":'                                   # one per model in both answers
    try:
        with urllib.request.urlopen(host + "/api/ps", timeout=2) as r:
            loaded = r.read().decode("utf-8", "replace")
        if key not in loaded:
            with urllib.request.urlopen(host + "/api/tags", timeout=2) as r:
                return f"ollama|idle|{r.read().decode('utf-8', 'replace').count(key)}"
    except Exception:
        pass
    if not shutil.which("ollama"):
        return None
    out = mw.run_hidden(["ollama", "ps"], timeout=3).splitlines()
    f = out[1].split() if len(out) > 1 else []
    if len(f) >= 4:
        return f"ollama|model|{f[0]} {f[2]}{f[3]}"
    listed = [l for l in mw.run_hidden(["ollama", "list"], timeout=3).splitlines()[1:] if l.strip()]
    return f"ollama|idle|{len(listed)}"


def winget_pending(text):
    """The rows of winget's upgrade table(s): everything after a dashed rule until a blank
    line or the summary ("2 upgrades available."), which begins with the count and is
    localised — the table rows begin with a package name."""
    count, in_table = 0, False
    for line in text.splitlines():
        s = line.strip()
        if re.fullmatch(r"-{5,}", s):
            in_table = True
        elif in_table:
            if not s or re.match(r"^\d+\s", s):
                in_table = False
            else:
                count += 1
    return count


def _winget():
    out = mw.run_hidden(["winget", "upgrade", "--include-unknown", "--accept-source-agreements"], timeout=120)
    return winget_pending(out)


winget = Cached(1800, _winget, background=True)


def winget_count():
    if not WINDOWS or not shutil.which("winget"):
        return None
    return winget.get()


def services(args):
    lines = [container_engine(e) for e in ("docker", "podman")] + [ollama_line()]
    pending = winget_count()
    if pending is not None:
        lines.append(f"winget|{pending}")
    return "".join(line + "\n" for line in lines if line)


# ── health.sh ───────────────────────────────────────────────────────────────────────

def failed_services():
    """Services set to start automatically that are not running — the nearest thing to
    systemd's failed units. None where there is no service manager to ask."""
    if not WINDOWS or not psutil:
        return None
    down = 0
    for s in psutil.win_service_iter():
        try:
            if s.start_type() == "automatic" and s.status() != "running":
                down += 1
        except Exception:
            continue
    return down


def parse_events(xml):
    """[(time, source, message)] from wevtutil's XML, newest first as queried. The events
    come concatenated without a root, so one is added; the message is the rendered one
    when present, else the event's Data fields joined — the raw form has no catalog."""
    try:
        root = ET.fromstring("<Events>" + xml + "</Events>")
    except ET.ParseError:
        return []
    out = []
    for ev in root:
        source, stamp, message, data = "", None, "", []
        for el in ev.iter():
            tag = el.tag.split("}")[-1]
            if tag == "Provider":
                source = el.get("Name") or el.get("EventSourceName") or ""
            elif tag == "TimeCreated":
                stamp = el.get("SystemTime")
            elif tag == "Message":
                message = el.text or ""
            elif tag == "Data" and el.text:
                data.append(el.text)
        try:
            when = datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp() if stamp else 0.0
        except ValueError:
            when = 0.0
        out.append((when, source, re.sub(r"\s+", " ", message or " ".join(data)).strip()))
    return out


def _event_log(log):
    return parse_events(mw.run_hidden(["wevtutil", "qe", log, "/q:*[System[(Level=1 or Level=2)]]",
                                       "/c:40", "/rd:true", "/f:xml"], timeout=20))


def _events():
    """(System errors since boot, Application errors since boot, [(source, message)]).
    Forty newest per log, so a count reads "40" when there are more — the lines are the
    point, and the full count would mean a time-bounded second query per log."""
    boot = psutil.boot_time() if psutil else 0.0
    system = [e for e in _event_log("System") if e[0] >= boot]
    app = [e for e in _event_log("Application") if e[0] >= boot]
    return len(system), len(app), [(s, m) for _, s, m in system]


events = Cached(60, _events)


def event_errors():
    return events.get() if WINDOWS else None


def reboot_pending():
    if not winreg:
        return False
    for key in (r"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
                r"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"):
        try:
            winreg.CloseKey(winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, key))
            return True
        except OSError:
            continue
    return False


def health_lines(failed, errors, reboot, n):
    """The script's lines in its order: failed, err, reboot, then up to n distinct error
    lines, newest first, "source|message" cut at 120 characters before the prefix."""
    lines = [f"failed|{'?' if failed is None else failed}|0"]
    if errors:
        lines.append(f"err|{errors[0]}|{errors[1]}")
    if reboot:
        lines.append("reboot|yes")
    if errors and n > 0:
        seen = []
        for source, message in errors[2]:
            row = f"{source}|{message}"[:120]
            if row not in seen:
                seen.append(row)
        lines += ["errline|" + row for row in seen[:n]]
    return "".join(line + "\n" for line in lines)


def health(args):
    n = int(args[0]) if args and args[0].isdigit() else 3
    return health_lines(failed_services(), event_errors(), reboot_pending(), n)


# ── units.sh ────────────────────────────────────────────────────────────────────────

STATES = {"running": "active", "stopped": "inactive", "start_pending": "activating",
          "stop_pending": "deactivating", "continue_pending": "activating", "pause_pending": "deactivating"}


def service_state(name):
    """psutil's status word for a Windows service, "" for one that does not exist."""
    if not WINDOWS or not psutil:
        return ""
    try:
        return psutil.win_service_get(name).status()
    except Exception:
        return ""


def unit_state(status):
    return STATES.get(status, "inactive")


def units(args):
    args = list(args)
    if args[:1] == ["--user"]:
        args.pop(0)                                   # no user manager here: accepted, ignored
    return "".join(f"{u}|{unit_state(service_state(u))}\n" for u in args)


# ── sound.sh ────────────────────────────────────────────────────────────────────────

def audio_device(flow):
    """(name, volume 0..1, muted) of the default output or input through pycaw, None
    without it. COM must be initialised in the request's thread, hence CoInitialize
    here rather than at import; comtypes does it for the importing thread only."""
    try:
        import comtypes
        from pycaw.pycaw import AudioUtilities
    except Exception:
        return None
    try:
        try:
            comtypes.CoInitialize()
        except Exception:
            pass                                      # already initialised in this thread
        dev = AudioUtilities.GetSpeakers() if flow == "output" else AudioUtilities.GetMicrophone()
        device = AudioUtilities.CreateDevice(dev)
        volume = device.EndpointVolume
        return (device.FriendlyName or "", float(volume.GetMasterVolumeLevelScalar()), bool(volume.GetMute()))
    except Exception:
        return None


def sound(args):
    kinds = [("sink", "output")] + ([("source", "input")] if args[:1] == ["input"] else [])
    out = []
    for kind, flow in kinds:
        d = audio_device(flow)
        if d:
            name, volume, muted = d
            out.append(f"{kind}|{name.replace('|', ' ')}|{int(volume * 100 + 0.5)}|{1 if muted else 0}\n")
    return "".join(out)


# ── repos.sh ────────────────────────────────────────────────────────────────────────

def git(path, *args):
    try:
        r = subprocess.run(["git", "-C", path, *args], capture_output=True, text=True, timeout=10, **HIDDEN)
    except Exception:
        return None
    return r.stdout if r.returncode == 0 else None


def repos(args):
    out = []
    for p in args:
        p = os.path.expanduser(p)
        name = os.path.basename(p.rstrip("/\\")) or p
        branch = git(p, "rev-parse", "--abbrev-ref", "HEAD")
        if branch is None:
            out.append(f"{name}|notgit\n")
            continue
        dirty = len([l for l in (git(p, "status", "--porcelain") or "").splitlines() if l])
        behind, _, ahead = (git(p, "rev-list", "--left-right", "--count", "@{upstream}...HEAD") or "").strip().partition("\t")
        out.append(f"{name}|{branch.strip()}|{dirty}|{ahead or 0}|{behind or 0}\n")
    return "".join(out)


# ── peripherals.sh ──────────────────────────────────────────────────────────────────

# The battery level of a Bluetooth device sits in one device property; Windows keeps no
# charging state for them, so the third field says so rather than guessing.
BLUETOOTH_PS = (
    "Get-PnpDevice -Class Bluetooth -Status OK -ErrorAction SilentlyContinue | ForEach-Object {"
    " $p = Get-PnpDeviceProperty -InstanceId $_.InstanceId"
    " -KeyName '{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2' -ErrorAction SilentlyContinue;"
    " if ($p -and $null -ne $p.Data) { '{0}|{1}|unknown' -f ($_.FriendlyName -replace '\\|',' '), $p.Data } }")

bluetooth = Cached(60, lambda: mw.powershell(BLUETOOTH_PS))


def bluetooth_batteries():
    return bluetooth.get() if WINDOWS else ""


def peripherals(args):
    text = bluetooth_batteries() or ""
    return "".join(line.strip() + "\n" for line in text.splitlines() if line.count("|") >= 2)


EMULATORS = {"cpulist": cpulist, "lscpu": lscpu, "board": board, "loadavg": loadavg, "df": df,
             "services": services, "health": health, "units": units, "sound": sound,
             "repos": repos, "peripherals": peripherals}


if __name__ == "__main__":
    # `python3 exec_win.py 'LC_ALL=C lscpu'`: one command line, its answer.
    import json
    print(json.dumps(run(" ".join(sys.argv[1:]) or "LC_ALL=C lscpu"), indent=1))
