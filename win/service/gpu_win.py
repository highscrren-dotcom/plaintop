"""GPU sensors without LibreHardwareMonitor: what Task Manager reads.

The load comes from the performance counters `\\GPU Engine(*)\\Utilization Percentage`,
one instance per process and engine; a card's figure is Task Manager's — the busiest
engine type, summed over processes. The memory in use is `\\GPU Adapter Memory(*)\\
Dedicated Usage` and `Shared Usage`. Both are read from pdh.dll through ctypes with the
English counter names (PdhAddEnglishCounter — the desk's Windows speaks Russian). The
name and the size of the card's own memory come from the display class in the registry
(DriverDesc, HardwareInformation.qwMemorySize): Win32_VideoController's AdapterRAM is a
32-bit figure that stops at 4 GB. Temperature and power the counters do not have:
nvidia-smi gives them where it is; an Intel or AMD card shows none without LHM.

The counters name a card by its LUID, and so does DXGI: IDXGIFactory1::EnumAdapters1
(dxgi.dll through ctypes, three vtable calls) lists the adapters with their LUID, name,
dedicated memory, shared memory limit and a flag for the software adapter — the key
that joins the counters to a card. The first desk had three "cards": the counters list
the Microsoft Basic Render Driver too, and the registry's and nvidia-smi's orders are
their own; matched by index, an NVIDIA T600 came out twice and its memory under a
nameless third. nvidia-smi's row is matched by the card's name. The registry is the
fallback where DXGI cannot be asked. LHM, when it runs, is preferred for every id it
gives (monitor_win.Sampler merges this under it).

An integrated GPU has next to no dedicated memory and lives in the shared half of RAM,
which is what Task Manager shows for it: below 1 GiB of its own, a card's "VRAM" is the
shared usage against half of the physical memory.
"""
import ctypes
import os
import re
import shutil
import subprocess
import sys
import threading
import time

WINDOWS = sys.platform == "win32"
MIB = 1048576
GIB = 1073741824
CLASS_DISPLAY = r"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"

PDH_FMT_DOUBLE = 0x00000200
PDH_MORE_DATA = 0x800007D2
PDH_CSTATUS_VALID_DATA = 0x00000000
PDH_CSTATUS_NEW_DATA = 0x00000001

ENGINE = re.compile(r"luid_(0x[0-9a-f]+_0x[0-9a-f]+).*?engtype_([0-9a-z_]+)", re.IGNORECASE)
LUID = re.compile(r"luid_(0x[0-9a-f]+_0x[0-9a-f]+)", re.IGNORECASE)


# ── the pure part: counter instances → a card's figures ─────────────────────────────

def usage_by_card(items):
    """[(instance, percent)] of GPU Engine → {luid: percent}. Per engine type the sum over
    the processes, the card's figure the busiest type, capped at 100 — Task Manager's."""
    per = {}
    for name, value in items:
        m = ENGINE.search(str(name))
        if not m:
            continue
        luid, kind = m.group(1).lower(), m.group(2).lower()
        kinds = per.setdefault(luid, {})
        kinds[kind] = kinds.get(kind, 0.0) + max(0.0, float(value))
    return {luid: min(100.0, max(kinds.values(), default=0.0)) for luid, kinds in per.items()}


def memory_by_card(items):
    """[(instance, bytes)] of GPU Adapter Memory → {luid: bytes}, summed over the card's
    physical parts (phys_0, phys_1 — one on every card so far)."""
    out = {}
    for name, value in items:
        m = LUID.search(str(name))
        if m:
            luid = m.group(1).lower()
            out[luid] = out.get(luid, 0.0) + max(0.0, float(value))
    return out


def card_sensors(index, name, usage, dedicated_used, shared_used, dedicated_total, ram_total,
                 nvidia=None, shared_total=0):
    """One card's sensor ids. `nvidia` is a row of nvidia_smi() for the same card, whose
    temperature and power are the only source of them here. An integrated GPU (below a
    GiB of its own) shows its shared usage against the shared limit DXGI reports, or
    half of RAM where only the registry was asked."""
    base = f"gpu/gpu{index}/"
    out = {base + "usage": {"value": float(usage)}}
    if name:
        out[base + "name"] = {"value": str(name)}
    if dedicated_total >= GIB:
        out[base + "usedVram"] = {"value": float(dedicated_used)}
        out[base + "totalVram"] = {"value": float(dedicated_total)}
    else:
        out[base + "usedVram"] = {"value": float(dedicated_used + shared_used)}
        if shared_total:
            out[base + "totalVram"] = {"value": float(shared_total)}
        elif ram_total:
            out[base + "totalVram"] = {"value": float(ram_total) / 2}
    if nvidia:
        for key, field in (("temperature", "temperature"), ("power", "power")):
            if nvidia.get(field) is not None:
                out[base + key] = {"value": float(nvidia[field])}
        if nvidia.get("name"):
            out[base + "name"] = {"value": nvidia["name"]}
        if nvidia.get("memory_used") is not None and nvidia.get("memory_total"):
            out[base + "usedVram"] = {"value": float(nvidia["memory_used"]) * MIB}
            out[base + "totalVram"] = {"value": float(nvidia["memory_total"]) * MIB}
    return out


def parse_nvidia_smi(text):
    """The rows of `nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu,memory.used,
    memory.total,power.draw --format=csv,noheader,nounits`; a field nvidia-smi cannot read
    is "[N/A]" and comes back None."""
    rows = []
    for line in str(text or "").splitlines():
        parts = [p.strip() for p in line.split(",")]
        if len(parts) != 6:
            continue

        def num(s):
            try:
                return float(s)
            except ValueError:
                return None
        rows.append({"name": parts[0], "usage": num(parts[1]), "temperature": num(parts[2]),
                     "memory_used": num(parts[3]), "memory_total": num(parts[4]), "power": num(parts[5])})
    return rows


def luid_key(high, low):
    """A LUID as the counters spell it in an instance name: luid_0x<high>_0x<low>."""
    return f"0x{high & 0xFFFFFFFF:08x}_0x{low & 0xFFFFFFFF:08x}"


def pick_smi(adapter, rows, adapters):
    """nvidia-smi's row for an adapter: the same name; else the one row for the one
    NVIDIA adapter (vendor 0x10DE) when there is exactly one of each."""
    name = str(adapter.get("name", "")).strip().lower()
    for r in rows:
        if str(r.get("name", "")).strip().lower() == name:
            return r
    nvidia = [a for a in adapters if a.get("vendor") == 0x10DE]
    if len(rows) == 1 and len(nvidia) == 1 and nvidia[0] is adapter:
        return rows[0]
    return None


def cards_from(adapters, usage, dedicated, shared, smi=(), ram_total=0):
    """The cards as sensor ids: DXGI's hardware adapters in its order (the software one
    left out), each with the counters' figures by its LUID and nvidia-smi's row by name."""
    hardware = [a for a in adapters if not a.get("software")]
    out = {}
    for i, a in enumerate(hardware):
        luid = a["luid"]
        out.update(card_sensors(i, a.get("name", ""), usage.get(luid, 0.0), dedicated.get(luid, 0.0),
                                shared.get(luid, 0.0), int(a.get("dedicated") or 0), ram_total,
                                pick_smi(a, list(smi or []), hardware), int(a.get("shared") or 0)))
    return out


# ── Windows: dxgi.dll, pdh.dll, the registry, nvidia-smi ────────────────────────────

class _GUID(ctypes.Structure):
    _fields_ = [("Data1", ctypes.c_uint32), ("Data2", ctypes.c_uint16), ("Data3", ctypes.c_uint16),
                ("Data4", ctypes.c_ubyte * 8)]


class _LUID(ctypes.Structure):
    _fields_ = [("LowPart", ctypes.c_uint32), ("HighPart", ctypes.c_int32)]


class _AdapterDesc1(ctypes.Structure):
    # DXGI_ADAPTER_DESC1
    _fields_ = [("Description", ctypes.c_wchar * 128), ("VendorId", ctypes.c_uint32), ("DeviceId", ctypes.c_uint32),
                ("SubSysId", ctypes.c_uint32), ("Revision", ctypes.c_uint32),
                ("DedicatedVideoMemory", ctypes.c_size_t), ("DedicatedSystemMemory", ctypes.c_size_t),
                ("SharedSystemMemory", ctypes.c_size_t), ("AdapterLuid", _LUID), ("Flags", ctypes.c_uint32)]


IID_IDXGIFactory1 = _GUID(0x770AAE78, 0xF26F, 0x4DBA, (ctypes.c_ubyte * 8)(0xA8, 0x29, 0x25, 0x3C, 0x83, 0xD1, 0xB3, 0x87))
DXGI_ADAPTER_FLAG_SOFTWARE = 2
VTBL_RELEASE, VTBL_ENUM_ADAPTERS1, VTBL_GET_DESC1 = 2, 12, 10


def _com_method(obj, index, restype, *argtypes):
    """A COM interface's method by its slot in the vtable, callable with the object first."""
    vtable = ctypes.cast(obj, ctypes.POINTER(ctypes.c_void_p))[0]
    fn = ctypes.cast(ctypes.c_void_p(vtable), ctypes.POINTER(ctypes.c_void_p))[index]
    return ctypes.WINFUNCTYPE(restype, ctypes.c_void_p, *argtypes)(fn)


def dxgi_adapters():
    """[{"name", "luid", "vendor", "dedicated", "shared", "software"}] in DXGI's order
    (the primary first); [] off Windows or where DXGI cannot be asked, said on stderr."""
    if not WINDOWS:
        return []
    out = []
    try:
        dxgi = ctypes.WinDLL("dxgi")
        create = dxgi.CreateDXGIFactory1
        create.restype = ctypes.c_uint32
        create.argtypes = [ctypes.POINTER(_GUID), ctypes.POINTER(ctypes.c_void_p)]
        factory = ctypes.c_void_p()
        hr = create(ctypes.byref(IID_IDXGIFactory1), ctypes.byref(factory))
        if hr != 0 or not factory:
            print(f"dxgi: CreateDXGIFactory1 0x{hr:08X}", file=sys.stderr, flush=True)
            return []
        try:
            enum_adapters = _com_method(factory, VTBL_ENUM_ADAPTERS1, ctypes.c_uint32, ctypes.c_uint32,
                                        ctypes.POINTER(ctypes.c_void_p))
            i = 0
            while True:
                adapter = ctypes.c_void_p()
                if enum_adapters(factory, i, ctypes.byref(adapter)) != 0 or not adapter:
                    break
                try:
                    desc = _AdapterDesc1()
                    get_desc = _com_method(adapter, VTBL_GET_DESC1, ctypes.c_uint32, ctypes.POINTER(_AdapterDesc1))
                    if get_desc(adapter, ctypes.byref(desc)) == 0:
                        out.append({"name": desc.Description, "luid": luid_key(desc.AdapterLuid.HighPart, desc.AdapterLuid.LowPart),
                                    "vendor": int(desc.VendorId), "dedicated": int(desc.DedicatedVideoMemory),
                                    "shared": int(desc.SharedSystemMemory),
                                    "software": bool(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)})
                finally:
                    _com_method(adapter, VTBL_RELEASE, ctypes.c_uint32)(adapter)
                i += 1
        finally:
            _com_method(factory, VTBL_RELEASE, ctypes.c_uint32)(factory)
    except Exception as e:
        print(f"dxgi: {e!r}", file=sys.stderr, flush=True)
    return out


class _CounterValue(ctypes.Structure):
    # PDH_FMT_COUNTERVALUE: a DWORD status, then a union whose widest member is 8 bytes.
    _fields_ = [("CStatus", ctypes.c_uint32), ("doubleValue", ctypes.c_double)]


class _CounterItem(ctypes.Structure):
    # PDH_FMT_COUNTERVALUE_ITEM_W: the instance name, then the value.
    _fields_ = [("szName", ctypes.c_wchar_p), ("FmtValue", _CounterValue)]


class Query:
    """One PDH query with named counters; values() after at least two collect()s a second
    apart, since a utilization counter is a rate."""

    def __init__(self):
        self.pdh = ctypes.WinDLL("pdh")
        self.pdh.PdhOpenQueryW.restype = ctypes.c_uint32
        self.pdh.PdhOpenQueryW.argtypes = [ctypes.c_wchar_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_void_p)]
        self.pdh.PdhAddEnglishCounterW.restype = ctypes.c_uint32
        self.pdh.PdhAddEnglishCounterW.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_size_t,
                                                   ctypes.POINTER(ctypes.c_void_p)]
        self.pdh.PdhCollectQueryData.restype = ctypes.c_uint32
        self.pdh.PdhCollectQueryData.argtypes = [ctypes.c_void_p]
        self.pdh.PdhGetFormattedCounterArrayW.restype = ctypes.c_uint32
        self.pdh.PdhGetFormattedCounterArrayW.argtypes = [ctypes.c_void_p, ctypes.c_uint32,
                                                          ctypes.POINTER(ctypes.c_uint32),
                                                          ctypes.POINTER(ctypes.c_uint32), ctypes.c_void_p]
        self.pdh.PdhCloseQuery.restype = ctypes.c_uint32
        self.pdh.PdhCloseQuery.argtypes = [ctypes.c_void_p]
        self.handle = ctypes.c_void_p()
        rc = self.pdh.PdhOpenQueryW(None, 0, ctypes.byref(self.handle))
        if rc != 0:
            raise OSError(f"PdhOpenQuery: 0x{rc:08X}")
        self.counters = {}

    def add(self, key, path):
        c = ctypes.c_void_p()
        rc = self.pdh.PdhAddEnglishCounterW(self.handle, path, 0, ctypes.byref(c))
        if rc != 0:
            raise OSError(f"PdhAddEnglishCounter {path}: 0x{rc:08X}")
        self.counters[key] = c

    def collect(self):
        return self.pdh.PdhCollectQueryData(self.handle) == 0

    def values(self, key):
        """[(instance name, value)] of a wildcard counter; [] until the second sample."""
        c = self.counters[key]
        size, count = ctypes.c_uint32(0), ctypes.c_uint32(0)
        rc = self.pdh.PdhGetFormattedCounterArrayW(c, PDH_FMT_DOUBLE, ctypes.byref(size), ctypes.byref(count), None)
        if rc != PDH_MORE_DATA or size.value == 0:
            return []
        buf = ctypes.create_string_buffer(size.value)
        rc = self.pdh.PdhGetFormattedCounterArrayW(c, PDH_FMT_DOUBLE, ctypes.byref(size), ctypes.byref(count), buf)
        if rc != 0:
            return []
        items = ctypes.cast(buf, ctypes.POINTER(_CounterItem))
        out = []
        for i in range(count.value):
            item = items[i]
            if item.FmtValue.CStatus in (PDH_CSTATUS_VALID_DATA, PDH_CSTATUS_NEW_DATA):
                out.append((item.szName or "", item.FmtValue.doubleValue))
        return out

    def close(self):
        try:
            self.pdh.PdhCloseQuery(self.handle)
        except Exception:
            pass


def registry_cards():
    """[(name, dedicated bytes)] from the display class key, in the order of its driver
    keys; [] off Windows or without the key. qwMemorySize is a QWORD, sometimes stored as
    eight REG_BINARY bytes."""
    if not WINDOWS:
        return []
    import winreg
    out = []
    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, CLASS_DISPLAY) as key:
            i = 0
            while True:
                try:
                    sub = winreg.EnumKey(key, i)
                except OSError:
                    break
                i += 1
                if not sub.isdigit():
                    continue
                try:
                    with winreg.OpenKey(key, sub) as k:
                        name = str(winreg.QueryValueEx(k, "DriverDesc")[0])
                        try:
                            size, kind = winreg.QueryValueEx(k, "HardwareInformation.qwMemorySize")
                            if isinstance(size, bytes):
                                size = int.from_bytes(size[:8], "little")
                            size = int(size or 0)
                        except OSError:
                            size = 0
                except OSError:
                    continue
                out.append((name, size))
    except OSError:
        return []
    return out


def nvidia_smi(timeout=5):
    exe = shutil.which("nvidia-smi") or os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                                                     "System32", "nvidia-smi.exe")
    if not os.path.isfile(exe):
        return []
    try:
        flags = {"creationflags": subprocess.CREATE_NO_WINDOW} if WINDOWS else {}
        out = subprocess.run([exe, "--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw",
                              "--format=csv,noheader,nounits"], capture_output=True, text=True,
                             timeout=timeout, encoding="utf-8", errors="replace", **flags).stdout
    except Exception:
        return []
    return parse_nvidia_smi(out)


class Reader:
    """The thread: the counters every `interval` seconds, nvidia-smi every `slow` seconds,
    the registry once; sensors() is the latest reading. Off Windows, or where the counters
    are missing, sensors() is {} and the reason is said once on stderr."""

    def __init__(self, interval=2.0, slow=5.0, ram_total=0):
        self.interval, self.slow, self.ram_total = interval, slow, ram_total
        self._lock = threading.Lock()
        self._sensors = {}
        self._cards = []                         # LUIDs in the order first seen: a stable index
        self.enabled = WINDOWS

    def start(self):
        if self.enabled:
            threading.Thread(target=self._loop, daemon=True, name="gpu").start()
        return self

    def sensors(self):
        with self._lock:
            return dict(self._sensors)

    def _loop(self):
        try:
            query = Query()
            query.add("engine", r"\GPU Engine(*)\Utilization Percentage")
            query.add("dedicated", r"\GPU Adapter Memory(*)\Dedicated Usage")
            query.add("shared", r"\GPU Adapter Memory(*)\Shared Usage")
        except Exception as e:
            print(f"gpu counters not available: {e!r}", file=sys.stderr, flush=True)
            return
        adapters = dxgi_adapters()
        names = registry_cards() if not adapters else []
        if not self.ram_total:
            try:
                import psutil
                self.ram_total = psutil.virtual_memory().total
            except Exception:
                self.ram_total = 0
        smi, last_smi = [], 0.0
        while True:
            try:
                query.collect()
                now = time.monotonic()
                if now - last_smi >= self.slow:
                    last_smi = now
                    smi = nvidia_smi()
                usage = usage_by_card(query.values("engine"))
                dedicated = memory_by_card(query.values("dedicated"))
                shared = memory_by_card(query.values("shared"))
                if adapters:
                    out = cards_from(adapters, usage, dedicated, shared, smi, self.ram_total)
                else:
                    # No DXGI: the counters' LUIDs in the order first seen, the registry's
                    # names and sizes in theirs — right with one card, a guess with more.
                    for luid in list(dedicated) + list(shared) + list(usage):
                        if luid not in self._cards:
                            self._cards.append(luid)
                    out = {}
                    for i, luid in enumerate(self._cards):
                        name, total = names[i] if i < len(names) else ("", 0)
                        out.update(card_sensors(i, name, usage.get(luid, 0.0), dedicated.get(luid, 0.0),
                                                shared.get(luid, 0.0), total, self.ram_total,
                                                smi[i] if i < len(smi) else None))
                with self._lock:
                    self._sensors = out
            except Exception as e:
                print(f"gpu sample failed: {e!r}", file=sys.stderr, flush=True)
            time.sleep(self.interval)


if __name__ == "__main__":
    # `python gpu_win.py`: five seconds of readings, as the monitor would get them;
    # `--adapters`: what DXGI says, and nvidia-smi's rows.
    import json
    if "--adapters" in sys.argv:
        print(json.dumps({"dxgi": dxgi_adapters(), "registry": registry_cards(), "nvidia-smi": nvidia_smi()},
                         ensure_ascii=False, indent=1))
        sys.exit(0)
    r = Reader(interval=1.0).start()
    for _ in range(5):
        time.sleep(1.2)
        print(json.dumps(r.sensors(), ensure_ascii=False, indent=1))
