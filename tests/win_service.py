#!/usr/bin/env python3
"""Stand for the Windows service's own parts, win/service/{server,monitor_win,exec_win}.py:
the sensor dict `/monitor` publishes, the LibreHardwareMonitor tree walk, the command
recogniser behind `/exec` and its emulators, and the server's routing, token and Origin
rules, against an in-process server on an ephemeral port.

    python3 tests/win_service.py

Nothing here depends on the machine: psutil is replaced by made-up readings, the Windows
probes by fixtures, the other endpoints' modules by fakes — so the same checks pass on the
Linux desktop and on a Windows runner.
"""
import http.client
import importlib
import json
import os
import re
import shutil
import socket
import sys
import tempfile
import threading
import time
from pathlib import Path
from types import SimpleNamespace as NS

# The runner's pipe on Windows is cp1252: the check marks below would raise.
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "win" / "service"))
mw = importlib.import_module("monitor_win")
ex = importlib.import_module("exec_win")
srv = importlib.import_module("server")
relay = srv.load_relay()

passed = 0


def ok(cond, what):
    global passed
    if not cond:
        print("  ✗ " + what)
        sys.exit(1)
    passed += 1


# ── /monitor: the sampler on made-up readings ─────────────────────────────────────────

BOOT = 1_700_000_000.0


def fake_psutil(state):
    """A machine with four cores, one real link and three adapters that are not, two disks
    and a battery; `state["step"]` advances every counter so rates can be checked."""
    def counters(recv, sent):
        return NS(bytes_recv=recv, bytes_sent=sent)

    def step():
        return state["step"]

    inet, inet6 = socket.AF_INET, socket.AF_INET6
    return NS(
        cpu_percent=lambda percpu=False: [10.0, 20.0, 30.0, 40.0] if percpu else 25.0,
        cpu_freq=lambda percpu=False: [NS(current=3500.0)] if percpu else NS(current=3500.0),
        getloadavg=lambda: (0.5, 0.25, 0.125),
        virtual_memory=lambda: NS(total=16 * 2**30, available=10 * 2**30, percent=37.5),
        swap_memory=lambda: NS(total=4 * 2**30, used=2**30),
        boot_time=lambda: BOOT,
        net_io_counters=lambda pernic=False: {
            "Ethernet": counters(1000 + 5000 * step(), 500 + 1000 * step()),
            "Wi-Fi": counters(10, 10),
            "vEthernet (WSL)": counters(99, 99),
            "Loopback Pseudo-Interface 1": counters(99, 99),
            "Bluetooth Network Connection": counters(99, 99)},
        net_if_stats=lambda: {"Ethernet": NS(isup=True), "Wi-Fi": NS(isup=False), "vEthernet (WSL)": NS(isup=True),
                              "Loopback Pseudo-Interface 1": NS(isup=True), "Bluetooth Network Connection": NS(isup=True)},
        net_if_addrs=lambda: {"Ethernet": [NS(family=inet6, address="fe80::1"), NS(family=inet, address="192.168.1.5")],
                              "Wi-Fi": [NS(family=inet, address="192.168.1.9")],
                              "vEthernet (WSL)": [NS(family=inet, address="172.20.0.1")],
                              "Loopback Pseudo-Interface 1": [NS(family=inet, address="127.0.0.1")],
                              "Bluetooth Network Connection": []},
        disk_io_counters=lambda perdisk=False: {
            "PhysicalDrive0": NS(read_bytes=10**6 + 2048 * step(), write_bytes=10**6 + 1024 * step()),
            "PhysicalDrive1": NS(read_bytes=2048 * step(), write_bytes=0)},
        sensors_battery=lambda: NS(percent=73.0),
        # pid i: cpu i %, memory (70-i) MiB — the two top-30 lists overlap in nothing.
        process_iter=lambda attrs=None: [NS(info={"name": f"p{i}.exe", "pid": i, "cpu_percent": float(i),
                                                  "memory_info": NS(rss=(70 - i) * 2**20)}) for i in range(70)],
    )


def test_sampler():
    state, clock = {"step": 0}, [100.0]
    sampler = mw.Sampler(interval=1, ps=fake_psutil(state), clock=lambda: clock[0], windows=False)
    first = sampler.sample()
    s = first["sensors"]
    ok(set(first) == {"stamp", "sensors", "processes", "coreCount"}, "the dict has PROTOCOL.md's four keys")
    ok(first["coreCount"] == 4 and s["cpu/all/coreCount"]["value"] == 4, "coreCount is the number of cpuN")
    ok(s["network/Ethernet/download"]["value"] == 0.0, "no rate from a single reading")
    ok(all(isinstance(v, dict) and "value" in v for v in s.values()), "every sensor is {value[, name]}")
    ok(all(isinstance(v["value"], (int, float, str)) for v in s.values()), "values are numbers or text")

    state["step"], clock[0] = 1, 102.0                       # 2 s later, counters advanced
    d = sampler.sample()
    s = d["sensors"]
    ok(abs(d["stamp"] - time.time()) < 5, "stamp is wall-clock seconds")
    ok(s["cpu/all/usage"]["value"] == 25.0 and s["cpu/cpu3/usage"]["value"] == 40.0, "cpu usage per core and the mean")
    ok([s[f"cpu/cpu{i}/frequency"]["value"] for i in range(4)] == [3500.0] * 4, "one frequency repeated for every core (MHz)")
    ok(s["cpu/all/cpuCount"]["value"] == 1, "one processor until WMI says otherwise")
    ok(s["cpu/loadaverages/loadaverage1"]["value"] == 0.5 and s["cpu/loadaverages/loadaverage15"]["value"] == 0.125, "load averages")
    ok(s["memory/physical/used"]["value"] == 6 * 2**30 and s["memory/physical/total"]["value"] == 16 * 2**30, "memory used = total − available, in bytes")
    ok(s["memory/physical/usedPercent"]["value"] == 37.5 and s["memory/swap/used"]["value"] == 2**30, "memory percent and the page file")
    ok(abs(s["os/system/uptime"]["value"] - (time.time() - BOOT)) < 5, "uptime in seconds since boot")
    ok(all(isinstance(s[k]["value"], str) and s[k]["value"] for k in ("os/system/hostname", "os/system/name", "os/kernel/version")), "os/* are text")
    ok(s["network/Ethernet/download"]["value"] == 2500.0 and s["network/Ethernet/upload"]["value"] == 500.0, "rates are bytes/s over the sampler's clock")
    ok(s["network/Ethernet/totalDownload"]["value"] == 6000 and s["network/Ethernet/ipv4address"]["value"] == "192.168.1.5", "totals and the address")
    ok(not [k for k in s if k.startswith("network/") and not k.startswith("network/Ethernet/")],
       "a link that is down, loopback, WSL and Bluetooth adapters are not interfaces: " + repr([k for k in s if k.startswith("network/")]))
    ok(s["disk/PhysicalDrive0/read"]["value"] == 1024.0 and s["disk/PhysicalDrive0/write"]["value"] == 512.0, "disk rates per disk")
    ok(s["disk/all/read"]["value"] == 2048.0 and s["disk/all/write"]["value"] == 512.0, "disk/all is the sum")
    ok(s["power/BAT0/chargePercentage"]["value"] == 73.0 and "power/BAT0/capacity" not in s, "the battery from psutil alone: percentage only")
    ok(not [k for k in s if k.startswith("pressure/")], "no pressure/* ids")
    procs = d["processes"]
    pids = sorted(r[3] for r in procs)
    ok(len(procs) == 60 and pids == list(range(1, 31)) + list(range(40, 70)), "the union of top 30 by cpu and top 30 by memory, pid 0 left out")
    ok(all(len(r) == 4 and isinstance(r[0], str) and isinstance(r[1], float) and isinstance(r[2], int) and isinstance(r[3], int) for r in procs),
       "a process is [name, cpu %, rss bytes, pid]")
    ok(sampler.snapshot() is d, "snapshot() is the latest dict")
    json.dumps(d)
    print("  ✓ Sampler: the sensor dict from psutil readings")

    # The slow probes' results, as the Windows loop leaves them, reach the ids.
    sampler._slow.update({"gateways": {"192.168.1.5": "192.168.1.1"}, "signal": {"Ethernet": 80.0}, "cpuCount": 2,
                          "battery": mw.battery_extras({"chargeRate": 0, "dischargeRate": 12500, "remaining": 30000,
                                                        "full": 48000, "designed": 60000})})
    s = sampler.sample()["sensors"]
    ok(s["network/Ethernet/ipv4gateway"]["value"] == "192.168.1.1" and s["network/Ethernet/signal"]["value"] == 80.0, "gateway and signal on the matching interface")
    ok(s["cpu/all/cpuCount"]["value"] == 2, "cpuCount from WMI")
    ok(s["power/BAT0/chargeRate"]["value"] == -12.5 and s["power/BAT0/charge"]["value"] == 30.0, "chargeRate in W, negative while discharging; charge in Wh")
    ok(s["power/BAT0/capacity"]["value"] == 48.0 and s["power/BAT0/health"]["value"] == 80.0, "capacity in Wh, health in %")
    print("  ✓ Sampler: the Windows probes merge into the ids")


def test_parsers():
    route = ("===========================================================================\n"
             "IPv4 Route Table\nActive Routes:\n"
             "Network Destination        Netmask          Gateway       Interface  Metric\n"
             "          0.0.0.0          0.0.0.0      192.168.1.1     192.168.1.5     25\n"
             "          0.0.0.0          0.0.0.0       10.0.0.138      10.0.0.12     55\n"
             "          0.0.0.0          0.0.0.0       10.0.0.139      10.0.0.12     35\n"
             "        127.0.0.0        255.0.0.0         On-link         127.0.0.1    331\n")
    ok(mw.parse_route_print(route) == {"192.168.1.5": "192.168.1.1", "10.0.0.12": "10.0.0.139"}, "route print: default routes by interface address, lowest metric")
    ok(mw.parse_route_print("") == {}, "route print: nothing")
    netsh = ("\nThere is 1 interface on the system:\n\n"
             "    Name                   : Wi-Fi\n    Description            : Intel(R) Wi-Fi 6 AX200 160MHz\n"
             "    State                  : connected\n    SSID                   : Home\n"
             "    Channel                : 44\n    Receive rate (Mbps)    : 866.7\n    Signal                 : 87%\n"
             "    Profile                : Home\n\n    Hosted network status  : Not available\n")
    ok(mw.parse_netsh_wlan(netsh) == {"Wi-Fi": 87.0}, "netsh wlan: the signal under the interface's name")
    russian = netsh.replace("Name   ", "Имя    ").replace("Signal ", "Сигнал ")
    ok(mw.parse_netsh_wlan(russian) == {"Wi-Fi": 87.0}, "netsh wlan: read by shape, so a translated Windows works too")
    ok(mw.parse_netsh_wlan("There is no wireless interface on the system.\n") == {}, "netsh wlan: no adapter")
    ok(mw.battery_extras({"chargeRate": 20000, "dischargeRate": 0, "remaining": 10000, "full": 50000, "designed": 50000})
       == {"chargeRate": 20.0, "charge": 10.0, "capacity": 50.0, "health": 100.0}, "battery: charging reads positive")
    ok(mw.battery_extras({}) == {}, "battery: nothing from WMI, nothing published")
    for text, want in (("54,0 °C", 54.0), ("1.234 RPM", 1234.0), ("1,234 RPM", 1234.0), ("2.048,0 MB", 2048.0),
                       ("12.0 %", 12.0), ("120,5 W", 120.5), ("0,500 V", 0.5), ("-", None), ("", None), (None, None)):
        ok(mw.parse_value(text) == want, f"parse_value({text!r}) == {want!r}, got {mw.parse_value(text)!r}")
    ok(mw.slug("Nuvoton NCT6798D") == "nuvoton-nct6798d" and mw.slug("  ") == "chip", "slug: lmsensors-style chip ids")
    print("  ✓ parsers: route print, netsh wlan, WMI battery, LHM values")


LHM_TREE = {"id": 0, "Text": "Sensor", "Children": [{"id": 1, "Text": "DESKTOP-1", "ImageURL": "images_icon/computer.png", "Children": [
    {"id": 2, "Text": "ASUS PRIME X570-P", "ImageURL": "images_icon/mainboard.png", "Children": [
        {"id": 3, "Text": "Nuvoton NCT6798D", "ImageURL": "images_icon/chip.png", "Children": [
            {"id": 4, "Text": "Voltages", "ImageURL": "images_icon/voltage.png", "Children": [
                {"id": 5, "Text": "Vcore", "Value": "1,224 V", "SensorId": "/lpc/nct6798d/0/voltage/0", "Type": "Voltage"}]},
            {"id": 6, "Text": "Temperatures", "ImageURL": "images_icon/temperature.png", "Children": [
                {"id": 7, "Text": "Temperature #1", "Value": "38,0 °C", "SensorId": "/lpc/nct6798d/0/temperature/0", "Type": "Temperature"},
                {"id": 8, "Text": "Temperature #2", "Value": "41,5 °C", "SensorId": "/lpc/nct6798d/0/temperature/1", "Type": "Temperature"}]},
            {"id": 9, "Text": "Fans", "ImageURL": "images_icon/fan.png", "Children": [
                {"id": 10, "Text": "Fan #1", "Value": "1.234 RPM", "SensorId": "/lpc/nct6798d/0/fan/0", "Type": "Fan"},
                {"id": 11, "Text": "Fan #2", "Value": "0 RPM", "SensorId": "/lpc/nct6798d/0/fan/1", "Type": "Fan"}]}]}]},
    {"id": 20, "Text": "AMD Ryzen 7 5800X", "ImageURL": "images_icon/cpu.png", "Children": [
        {"id": 21, "Text": "Load", "ImageURL": "images_icon/load.png", "Children": [
            {"id": 22, "Text": "CPU Total", "Value": "12,3 %", "SensorId": "/amdcpu/0/load/0", "Type": "Load"}]},
        {"id": 23, "Text": "Temperatures", "ImageURL": "images_icon/temperature.png", "Children": [
            {"id": 24, "Text": "Core #1", "Value": "54,0 °C", "SensorId": "/amdcpu/0/temperature/0", "Type": "Temperature"},
            {"id": 25, "Text": "Core #2", "Value": "56,5 °C", "SensorId": "/amdcpu/0/temperature/1", "Type": "Temperature"},
            {"id": 26, "Text": "CPU Package", "Value": "65,0 °C", "SensorId": "/amdcpu/0/temperature/2", "Type": "Temperature"}]}]},
    {"id": 30, "Text": "NVIDIA GeForce RTX 3080", "ImageURL": "images_icon/nvidia.png", "Children": [
        {"id": 31, "Text": "Load", "ImageURL": "images_icon/load.png", "Children": [
            {"id": 32, "Text": "GPU Core", "Value": "12,0 %", "SensorId": "/gpu-nvidia/0/load/0", "Type": "Load"},
            {"id": 33, "Text": "GPU Memory", "Value": "20,0 %", "SensorId": "/gpu-nvidia/0/load/4", "Type": "Load"}]},
        {"id": 34, "Text": "Temperatures", "ImageURL": "images_icon/temperature.png", "Children": [
            {"id": 35, "Text": "GPU Core", "Value": "45,0 °C", "SensorId": "/gpu-nvidia/0/temperature/0", "Type": "Temperature"}]},
        {"id": 36, "Text": "Data", "ImageURL": "images_icon/data.png", "Children": [
            {"id": 37, "Text": "GPU Memory Total", "Value": "10.240,0 MB", "SensorId": "/gpu-nvidia/0/smalldata/3", "Type": "SmallData"},
            {"id": 38, "Text": "GPU Memory Used", "Value": "2.048,0 MB", "SensorId": "/gpu-nvidia/0/smalldata/2", "Type": "SmallData"}]},
        {"id": 39, "Text": "Powers", "ImageURL": "images_icon/power.png", "Children": [
            {"id": 40, "Text": "GPU Package", "Value": "120,5 W", "SensorId": "/gpu-nvidia/0/power/0", "Type": "Power"}]}]},
    {"id": 50, "Text": "Samsung SSD 980 PRO 1TB", "ImageURL": "images_icon/hdd.png", "Children": [
        {"id": 51, "Text": "Temperatures", "ImageURL": "images_icon/temperature.png", "Children": [
            {"id": 52, "Text": "Temperature", "Value": "39,0 °C", "SensorId": "/nvme/0/temperature/0", "Type": "Temperature"}]}]}]}]}


def test_lhm():
    s = mw.lhm_sensors(LHM_TREE, 4)
    ok(s["lmsensors/nuvoton-nct6798d/fan1"] == {"value": 1234.0, "name": "Fan #1"}, "a chip fan: lmsensors/<slug>/fan1 with LHM's own name")
    ok(s["lmsensors/nuvoton-nct6798d/fan2"]["value"] == 0.0, "a stopped fan is still a sensor")
    ok(s["lmsensors/nuvoton-nct6798d/temp1"] == {"value": 38.0, "name": "Temperature #1"}, "a chip temperature")
    ok(s["lmsensors/nuvoton-nct6798d/temp2"]["value"] == 41.5, "numbered in LHM's order")
    ok(not [k for k in s if "voltage" in k or "vcore" in k.lower()], "voltages are not published")
    ok(s["cpu/cpu0/temperature"] == {"value": 54.0, "name": "Core #1"} and s["cpu/cpu1/temperature"]["value"] == 56.5, "Core #N → cpu/cpu(N-1)")
    ok(s["cpu/cpu2/temperature"] == {"value": 65.0, "name": "CPU Package"} and s["cpu/cpu3/temperature"]["value"] == 65.0, "the package fills the cores without one")
    ok("cpu/cpu4/temperature" not in s, "no temperature beyond the core count")
    ok(s["gpu/gpu0/name"]["value"] == "NVIDIA GeForce RTX 3080", "the GPU's name is the hardware node's text")
    ok(s["gpu/gpu0/usage"]["value"] == 12.0 and s["gpu/gpu0/temperature"]["value"] == 45.0, "GPU usage from 'GPU Core', not the memory controller")
    ok(s["gpu/gpu0/usedVram"]["value"] == 2048 * 1048576 and s["gpu/gpu0/totalVram"]["value"] == 10240 * 1048576, "VRAM MB → bytes")
    ok(s["gpu/gpu0/power"]["value"] == 120.5, "GPU power in W")
    ok(s["lmsensors/nvme-samsung-ssd-980-pro-1tb/temp1"]["value"] == 39.0, "an NVMe drive as lmsensors/nvme-…/temp1, where the disks block looks")
    ok("cpu/all/usage" not in s, "LHM's CPU load is not published: psutil's is")
    package_only = {"Text": "x", "Children": [{"Text": "CPU", "Children": [{"Text": "Temperatures", "Children": [
        {"Text": "Core (Tctl/Tdie)", "Value": "71,2 °C", "SensorId": "/amdcpu/0/temperature/2", "Type": "Temperature"}]}]}]}
    ok(mw.lhm_sensors(package_only, 2) == {"cpu/cpu0/temperature": {"value": 71.2, "name": "Core (Tctl/Tdie)"},
                                            "cpu/cpu1/temperature": {"value": 71.2, "name": "Core (Tctl/Tdie)"}}, "a package-only chip: every core")
    untyped = {"Text": "x", "Children": [{"Text": "Nuvoton NCT6798D", "Children": [{"Text": "Fans", "Children": [
        {"Text": "Fan #1", "Value": "800 RPM", "SensorId": "/lpc/nct6798d/0/fan/0"}]}]}]}
    ok(mw.lhm_sensors(untyped, 1) == {"lmsensors/nuvoton-nct6798d/fan1": {"value": 800.0, "name": "Fan #1"}}, "an older LHM without Type: the kind from the SensorId path")
    ok(mw.lhm_sensors(None, 4) == {} and mw.lhm_sensors({}, 4) == {}, "no tree, no sensors")
    ok(mw.LHM().tree() is None, "LHM reader: no tree until it has answered")
    print("  ✓ lhm_sensors: LHM's tree as ksystemstats ids")


# ── /exec: the recogniser and the emulators ───────────────────────────────────────────

CODE = "/C:/Users/me/AppData/Local/plaintop/host/code"      # what Qt.resolvedUrl gives on Windows
BOARD = ("cat /sys/devices/virtual/dmi/id/board_vendor /sys/devices/virtual/dmi/id/board_name "
         "/sys/devices/virtual/dmi/id/bios_version 2>/dev/null || tr -d '\\0' < /proc/device-tree/model 2>/dev/null")


def rows(result, sep="|"):
    return [line.split(sep) for line in result["stdout"].rstrip("\n").split("\n")] if result["stdout"] else []


def test_dispatch():
    cases = [
        ("cat /sys/devices/system/node/node*/cpulist", ("cpulist", [])),
        ("LC_ALL=C lscpu", ("lscpu", [])),
        (BOARD, ("board", [])),
        ("cat /proc/loadavg", ("loadavg", [])),
        ("timeout 5 df -B1 --output=target,size,used,pcent / D: 2>/dev/null", ("df", ["-B1", "--output=target,size,used,pcent", "/", "D:"])),
        ("bash " + CODE + "/services.sh", ("services", [])),
        ("bash " + CODE + "/health.sh 3", ("health", ["3"])),
        ("bash " + CODE + "/units.sh --user 'foo.service' 'it'\\''s'", ("units", ["--user", "foo.service", "it's"])),
        ("bash " + CODE + "/peripherals.sh", ("peripherals", [])),
        ("bash " + CODE + "/sound.sh input", ("sound", ["input"])),
        ("bash " + CODE + "/sound.sh", ("sound", [])),
        ("bash " + CODE + "/repos.sh '~/plaintop' '/srv/x y'", ("repos", ["~/plaintop", "/srv/x y"])),
        ("bash " + CODE + "/services.sh # 1759600000000", ("services", [])),
        ("echo hello # 1759600000000", ("shell", ["echo hello"])),
        ("echo hello 2>/dev/null", ("shell", ["echo hello"])),
        ("cat /etc/hostname", ("shell", ["cat /etc/hostname"])),
        ("bash /somewhere/else.sh", ("shell", ["bash /somewhere/else.sh"])),
        ("echo 'unbalanced", ("shell", ["echo 'unbalanced"])),
    ]
    for command, want in cases:
        got = ex.dispatch(command)
        ok(got == want, f"dispatch({command!r}) → {got!r}, wanted {want!r}")
    print("  ✓ dispatch: every line MonitorData builds finds its emulator, the rest the shell")


def test_hardware_lines():
    r = ex.run("cat /sys/devices/system/node/node*/cpulist")
    lines = r["stdout"].rstrip("\n").split("\n")
    ok(r["exit code"] == 0 and all(re.fullmatch(r"\d+(-\d+)?(,\d+(-\d+)?)*", l) for l in lines), "cpulist: one kernel-style list per node: " + repr(lines))
    cpus = set()
    for line in lines:                                        # parseNodes() in the QML
        for part in line.split(","):
            lo, hi = (part.split("-") + [part])[:2]
            cpus |= set(range(int(lo), int(hi) + 1))
    n = os.cpu_count() or 1
    ok(cpus == set(range(n)) if n <= 64 else cpus <= set(range(n)), f"cpulist covers the {n} logical cpus")
    ok(ex.ranges([0, 1, 2, 3, 8, 9]) == "0-3,8-9" and ex.ranges([5]) == "5" and ex.ranges([]) == "", "ranges: runs as the kernel writes them")

    r = ex.run("LC_ALL=C lscpu")
    fields = {l.split(":")[0].strip(): l.split(":", 1)[1].strip() for l in r["stdout"].splitlines() if ":" in l}
    ok(r["exit code"] == 0 and set(fields) >= {"Model name", "Socket(s)", "Core(s) per socket", "Thread(s) per core"}, "lscpu: the four keys parseLscpu reads: " + repr(fields))
    ok(all(fields[k].isdigit() and int(fields[k]) >= 1 for k in ("Socket(s)", "Core(s) per socket", "Thread(s) per core")), "lscpu: counts are positive integers")
    ok(fields["Model name"] != "", "lscpu: a model name")

    r = ex.run(BOARD)
    ok((r["exit code"] == 0 and len(r["stdout"].rstrip("\n").split("\n")) >= 3) or (r["exit code"] != 0 and r["stdout"] == ""),
       "board: three lines on exit 0, or a non-zero exit parseBoard ignores: " + repr(r))
    real = ex.board_lines
    ex.board_lines = lambda: ["ASUSTeK COMPUTER INC.", "PRIME X570-P", "4021"]
    try:
        l = ex.run(BOARD)["stdout"].strip().split("\n")
        ok(l[0] + " " + l[1] + "  (BIOS " + l[2] + ")" == "ASUSTeK COMPUTER INC. PRIME X570-P  (BIOS 4021)", "board: the line the QML composes")
    finally:
        ex.board_lines = real

    r = ex.run("cat /proc/loadavg")
    f = r["stdout"].split()
    ok(r["exit code"] == 0 and len(f) == 5 and all(re.fullmatch(r"\d+\.\d\d", x) for x in f[:3]), "loadavg: three numbers first, as /proc/loadavg: " + repr(r["stdout"]))
    print("  ✓ cpulist, lscpu, board, loadavg: the once-only lines")


def test_df():
    system = os.environ.get("SystemDrive", "C:") + "\\"
    ok(ex.df_target("/", nt=True) == system and ex.df_target("D:", nt=True) == "D:\\" and ex.df_target("D:\\", nt=True) == "D:\\", "df targets on Windows: / is the system drive, D: a drive")
    ok(ex.df_target("/", nt=False) == "/" and ex.df_target("/home", nt=False) == "/home", "df targets elsewhere: as given")
    r = ex.run("timeout 5 df -B1 --output=target,size,used,pcent / D: 2>/dev/null")
    lines = r["stdout"].rstrip("\n").split("\n")
    ok(len(lines) >= 2, "df: a header line and at least the system drive: " + repr(lines))
    table = [l.split() for l in lines[1:]]                    # the QML skips the header, splits on whitespace
    ok(all(len(f) == 4 and f[1].isdigit() and f[2].isdigit() and re.fullmatch(r"\d+%", f[3]) for f in table), "df: target size used N% per row: " + repr(table))
    root = [f for f in table if f[0] == "/"]
    ok(len(root) == 1 and int(root[0][1]) >= int(root[0][2]) > 0, "df: / printed as given, size ≥ used > 0")
    if not os.path.exists("D:\\"):
        ok([f for f in table if f[0] == "D:"] == [] and r["exit code"] == 1 and "D:" in r["stderr"], "df: a drive that is not there: no row, an error, exit 1")
    print("  ✓ df: the table the disks block parses")


def test_services():
    saved = ex.container_engine, ex.ollama_line, ex.winget_count
    ex.container_engine = lambda e: "docker|1|3" if e == "docker" else None
    ex.ollama_line = lambda: "ollama|idle|2"
    ex.winget_count = lambda: 4
    try:
        r = ex.run("bash " + CODE + "/services.sh")
        ok(rows(r) == [["docker", "1", "3"], ["ollama", "idle", "2"], ["winget", "4"]], "services: key|fields per service that answers: " + repr(r))
        ex.winget_count = lambda: None
        ok(rows(ex.run("bash " + CODE + "/services.sh")) == [["docker", "1", "3"], ["ollama", "idle", "2"]], "services: no winget line while the count is not known")
    finally:
        ex.container_engine, ex.ollama_line, ex.winget_count = saved
    table = ("   -\r   \\\r   |\r\n"
             "Name                 Id                 Version   Available  Source\n"
             "------------------------------------------------------------------\n"
             "Mozilla Firefox      Mozilla.Firefox    130.0     131.0      winget\n"
             "7-Zip                7zip.7zip          23.01     24.08      winget\n"
             "2 upgrades available.\n\n"
             "The following packages have an upgrade available, but require explicit targeting for upgrade:\n"
             "Name                 Id                 Version   Available  Source\n"
             "------------------------------------------------------------------\n"
             "Some Tool            Some.Tool          1.0       1.1        winget\n"
             "1 package(s) have version numbers that cannot be determined.\n")
    ok(ex.winget_pending(table) == 3, "winget: rows of every table, not the summaries")
    ok(ex.winget_pending("No installed package found matching input criteria.\n") == 0, "winget: nothing pending")
    slow = ex.Cached(60, lambda: (time.sleep(0.3), 7)[1], background=True)
    ok(slow.get() is None, "a background cache answers at once, with nothing, on the first ask")
    time.sleep(0.6)
    ok(slow.get() == 7, "…and with the value once the producer is done")
    calls = []
    sync = ex.Cached(60, lambda: calls.append(1) or len(calls))
    ok(sync.get() == 1 and sync.get() == 1 and len(calls) == 1, "a synchronous cache produces once within its ttl")
    print("  ✓ services.sh: docker, ollama, winget lines; the caches")


EVENTS_XML = (
    "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System>"
    "<Provider Name='Service Control Manager' Guid='{555908d1-a6d7-4695-8e1e-26931d2012f4}' EventSourceName='Service Control Manager'/>"
    "<EventID Qualifiers='49152'>7000</EventID><Level>2</Level><TimeCreated SystemTime='2026-10-04T10:11:12.1234567Z'/>"
    "<Channel>System</Channel></System><EventData><Data Name='param1'>Foo Service</Data><Data Name='param2'>%%1053</Data></EventData></Event>"
    "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System>"
    "<Provider Name='Microsoft-Windows-DistributedCOM' Guid='{1B562E86-B7AA-4131-BADC-B6F3A001407E}'/>"
    "<EventID>10016</EventID><Level>2</Level><TimeCreated SystemTime='2026-10-03T23:59:59.0000000Z'/></System>"
    "<EventData><Data Name='param1'>application-specific</Data></EventData>"
    "<RenderingInfo Culture='en-US'><Message>The application-specific permission settings\ndo not grant Local Activation</Message></RenderingInfo></Event>")


def test_health():
    events = ex.parse_events(EVENTS_XML)
    ok(len(events) == 2 and events[0][1] == "Service Control Manager" and events[0][2] == "Foo Service %%1053", "wevtutil xml: the provider, the Data fields as the message")
    ok(events[1][2] == "The application-specific permission settings do not grant Local Activation", "wevtutil xml: the rendered message when there is one, on one line")
    ok(events[0][0] > events[1][0] > 1.7e9, "wevtutil xml: TimeCreated as epoch seconds")
    ok(ex.parse_events("<Event><System>broken") == [] and ex.parse_events("") == [], "wevtutil xml: garbage is no events")

    saved = ex.failed_services, ex.event_errors, ex.reboot_pending
    long = "x" * 200
    ex.failed_services = lambda: 2
    ex.event_errors = lambda: (5, 1, [("Service Control Manager", "The Foo service failed to start"),
                                      ("Service Control Manager", "The Foo service failed to start"),
                                      ("DCOM", long), ("Kernel-Power", "unexpected shutdown")])
    ex.reboot_pending = lambda: True
    try:
        r = ex.run("bash " + CODE + "/health.sh 2")
        f = rows(r)
        ok(f[0] == ["failed", "2", "0"] and f[1] == ["err", "5", "1"] and f[2] == ["reboot", "yes"], "health: failed, err, reboot lines: " + repr(f))
        ok(f[3] == ["errline", "Service Control Manager", "The Foo service failed to start"], "health: the newest error first, duplicates folded")
        ok(f[4][:2] == ["errline", "DCOM"] and len("|".join(f[4][1:])) == 120 and len(f) == 5, "health: n lines, each cut at 120 characters")
        ok(rows(ex.run("bash " + CODE + "/health.sh 0"))[-1] == ["reboot", "yes"], "health: no error lines for 0")
        ex.failed_services = lambda: None
        ex.event_errors = lambda: None
        ex.reboot_pending = lambda: False
        ok(rows(ex.run("bash " + CODE + "/health.sh 3")) == [["failed", "?", "0"]], "health: '?' when the service manager did not answer, no err line without a log")
    finally:
        ex.failed_services, ex.event_errors, ex.reboot_pending = saved
    r = ex.run("bash " + CODE + "/health.sh 3")
    ok(r["exit code"] == 0 and r["stdout"].startswith("failed|"), "health: the real gatherers answer in the format: " + repr(r["stdout"]))
    print("  ✓ health.sh: failed, err, errline, reboot")


def test_units_sound_repos_peripherals():
    saved = ex.service_state
    ex.service_state = lambda n: {"Spooler": "running", "Fax": "stopped", "W32Time": "start_pending"}.get(n, "")
    try:
        r = ex.run("bash " + CODE + "/units.sh --user 'Spooler' 'Fax' 'W32Time' 'nothing.service'")
        ok(rows(r) == [["Spooler", "active"], ["Fax", "inactive"], ["W32Time", "activating"], ["nothing.service", "inactive"]], "units: unit|state, --user ignored: " + repr(r))
    finally:
        ex.service_state = saved
    ok(ex.unit_state("stop_pending") == "deactivating" and ex.unit_state("paused") == "inactive" and ex.unit_state("") == "inactive", "units: psutil's words as systemd's")
    ok(ex.run("bash " + CODE + "/units.sh")["stdout"] == "", "units: no units, no lines")

    saved = ex.audio_device
    ex.audio_device = lambda flow: ("Speakers (Realtek)", 0.455, False) if flow == "output" else ("Mic|Array", 0.8, True)
    try:
        ok(rows(ex.run("bash " + CODE + "/sound.sh")) == [["sink", "Speakers (Realtek)", "46", "0"]], "sound: sink|name|volume%|muted, rounded as the script's awk")
        ok(rows(ex.run("bash " + CODE + "/sound.sh input")) == [["sink", "Speakers (Realtek)", "46", "0"], ["source", "Mic Array", "80", "1"]], "sound: the source too with 'input', '|' in a name made a space")
        ex.audio_device = lambda flow: None
        ok(ex.run("bash " + CODE + "/sound.sh")["stdout"] == "", "sound: nothing without pycaw, as without wpctl")
    finally:
        ex.audio_device = saved

    if shutil.which("git"):
        with tempfile.TemporaryDirectory() as tmp:
            r = ex.run("bash " + CODE + "/repos.sh " + "'" + tmp.replace("'", "'\\''") + "'")
            ok(rows(r) == [[os.path.basename(tmp), "notgit"]], "repos: a directory that is no repository: " + repr(r))
        if (ROOT / ".git").exists():
            f = rows(ex.run("bash " + CODE + "/repos.sh '" + str(ROOT) + "'"))
            ok(len(f) == 1 and len(f[0]) == 5 and f[0][0] == ROOT.name and f[0][1] and all(x.isdigit() for x in f[0][2:]), "repos: name|branch|dirty|ahead|behind for this repository: " + repr(f))
        print("  ✓ repos.sh: git answers")
    else:
        print("  - repos.sh: git not in PATH, skipped")

    saved = ex.bluetooth_batteries
    ex.bluetooth_batteries = lambda: "MX Master 3|80|unknown\r\nnot a device line\n\n"
    try:
        ok(rows(ex.run("bash " + CODE + "/peripherals.sh")) == [["MX Master 3", "80", "unknown"]], "peripherals: model|percentage|state, other output dropped")
    finally:
        ex.bluetooth_batteries = saved
    print("  ✓ units.sh, sound.sh, peripherals.sh: the formats the QML splits on '|'")


def test_shell():
    for command in ("echo hello", "echo hello # 1759600000000", "echo hello 2>/dev/null"):
        r = ex.run(command)
        ok(r["exit code"] == 0 and r["stdout"].strip() == "hello" and set(r) == {"stdout", "stderr", "exit code"}, f"shell: {command!r} → {r!r}")
    saved = ex.failed_services
    ex.failed_services = lambda: 1 / 0
    try:
        r = ex.run("bash " + CODE + "/health.sh 3")
        ok(r["exit code"] == 1 and "ZeroDivisionError" in r["stderr"], "an emulator's exception is a failed command, not a 500")
    finally:
        ex.failed_services = saved
    print("  ✓ the shell for unknown commands, the nonce and 2>/dev/null stripped")


# ── The server: routing, token, Origin ────────────────────────────────────────────────

FRAME = [100, 200, 300, 400, 10, 20, 30, 40]


class FakeStore:
    def get(self, widget):
        if widget != "monitor":
            raise KeyError(widget)
        return 7, {"winX": 1}

    def update(self, widget, mapping):
        return 8


class FakeManager:
    def status(self):
        return {"running": ["monitor"]}

    def handle(self, request):
        return {"ok": True, "got": request}


def test_server():
    modules = {
        "exec_win": ex, "bands": None, "holidays_win": None,
        "player_win": NS(snapshot=lambda: {"players": [], "current": -1},
                         command=lambda i, c: (i, c) == ("Spotify.exe", "PlayPause")),
        "notes_bridge": NS(run=lambda args: ("ran " + " ".join(args), 0)),
        "timezones": NS(info=lambda z: {"zone": z, "offset": 0, "city": z.split("/")[-1]}),
        "settings_store": NS(Store=FakeStore), "ui": NS(Manager=FakeManager),
    }
    sampler = NS(snapshot=lambda: {"stamp": 1.0, "sensors": {"cpu/all/usage": {"value": 1.5}}, "processes": [["a.exe", 1.0, 2, 3]], "coreCount": 4})
    capture = NS(frame=lambda: list(FRAME), state=lambda: {"frames": 1, "restarts": 0, "source": "x", "age": 0.0, "bars": 8, "fps": 30, "backend": "fake"})
    svc = srv.Service("secret-token", sampler=sampler, capture=capture, modules=modules)
    server = srv.make_server(0, svc)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    conn = http.client.HTTPConnection("127.0.0.1", server.server_address[1], timeout=5)
    token = {"X-Plaintop-Token": "secret-token"}

    def req(method, path, body=None, headers=None):
        conn.request(method, path, body=None if body is None else json.dumps(body).encode() if not isinstance(body, bytes) else body,
                     headers=headers or {})
        r = conn.getresponse()
        data = r.read()
        return r.status, r.getheader("Content-Type"), data, r

    try:
        status, ctype, data, r = req("GET", "/monitor")
        d = json.loads(data)
        ok(status == 200 and ctype == "application/json; charset=utf-8" and d["sensors"]["cpu/all/usage"]["value"] == 1.5 and d["processes"] == [["a.exe", 1.0, 2, 3]], "/monitor: the sampler's dict as JSON")
        ok(not r.will_close, "HTTP/1.1 keep-alive: the connection stays open")

        status, ctype, data, _ = req("GET", "/bands?bars=4&mono=1")
        want = ",".join(str(v) for v in relay.resample(relay.fold_mono(FRAME), 4))
        ok(status == 200 and ctype == "text/plain" and data.decode() == want, f"/bands?bars=4&mono=1 folds and resamples with the relay's own functions: {data!r}")
        ok(req("GET", "/bands")[2].decode() == ",".join(map(str, FRAME)), "/bands: the frame as it is")
        ok(req("GET", "/bands?bars=3")[2].decode() == ",".join(str(v) for v in relay.resample(FRAME, 3)), "/bands?bars=3: stereo, resampled")
        ok(json.loads(req("GET", "/state")[2])["backend"] == "fake", "/state: the capture's state, with the backend")

        status, _, data, r = req("POST", "/exec", {"command": "echo hello"})
        ok(status == 401 and json.loads(data) == {"error": "token missing or wrong"} and not r.will_close, "POST without a token: 401, the connection kept")
        ok(req("POST", "/exec", {"command": "echo hello"}, {"X-Plaintop-Token": "nope"})[0] == 401, "POST with a wrong token: 401")
        ok(req("POST", "/exec", {"command": "echo hello"}, {**token, "Origin": "http://evil"})[0] == 403, "a token with an Origin header: 403")
        ok(req("GET", "/monitor", None, {"Origin": "null"})[0] == 403, "even a GET with an Origin header: 403")
        status, _, data, _ = req("POST", "/exec", {"command": "echo hello"}, token)
        ok(status == 200 and json.loads(data)["stdout"].strip() == "hello" and json.loads(data)["exit code"] == 0, "POST /exec with the token runs the command")
        ok(req("POST", "/exec", b"{not json", token)[0] == 400, "a body that is not JSON: 400")
        ok(req("POST", "/exec", {}, token)[0] == 400, "no command: 400")

        ok(json.loads(req("GET", "/player")[2]) == {"players": [], "current": -1}, "/player: player_win.snapshot()")
        ok(json.loads(req("POST", "/player", {"id": "Spotify.exe", "command": "PlayPause"}, token)[2]) == {"ok": True}, "POST /player: command(id, name) → ok")
        ok(json.loads(req("POST", "/player", {"id": "x", "command": "Next"}, token)[2]) == {"ok": False}, "POST /player: a refused command → ok false")
        ok(req("POST", "/player", {"id": 5}, token)[0] == 400, "POST /player without a command: 400")
        ok(json.loads(req("POST", "/notes", {"args": ["sync", "--every", "15"]}, token)[2]) == {"stdout": "ran sync --every 15", "exit code": 0}, "/notes: notes_bridge.run(args)")
        ok(req("POST", "/notes", {"args": "sync"}, token)[0] == 400, "/notes: args must be a list")
        status, _, data, _ = req("GET", "/holidays?regions=RU,DE-BY&year=2026&month=10&lang=ru")
        ok(status == 503 and json.loads(data) == {"error": "module not available"}, "a missing module: 503")
        ok(req("GET", "/holidays/regions?lang=ru")[0] == 503, "/holidays/regions from the same missing module: 503")
        ok(json.loads(req("GET", "/time?zone=Europe/Berlin")[2])["city"] == "Berlin", "/time: timezones.info(zone)")

        ok(json.loads(req("GET", "/settings/monitor")[2]) == {"stamp": 7, "values": {"winX": 1}}, "/settings/<widget>: stamp and values")
        status, _, data, r = req("GET", "/settings/monitor?since=7")
        ok(status == 304 and data == b"" and not r.will_close, "/settings/<widget>?since=<stamp>: 304, no body, connection kept")
        ok(req("GET", "/settings/monitor?since=6")[0] == 200, "an older stamp gets the values")
        ok(req("GET", "/settings/nope")[0] == 404, "an unknown widget: 404")
        ok(json.loads(req("POST", "/settings/monitor", {"winX": 5}, token)[2]) == {"stamp": 8}, "POST /settings/<widget>: the new stamp")
        ok(req("POST", "/settings/monitor", {"winX": 5})[0] == 401, "POST /settings without a token: 401")
        ok(json.loads(req("GET", "/ui")[2]) == {"running": ["monitor"]}, "GET /ui: Manager.status()")
        ok(json.loads(req("POST", "/ui", {"show": "monitor", "on": True}, token)[2])["got"] == {"show": "monitor", "on": True}, "POST /ui: Manager.handle(request)")
        quits = []
        svc.on_quit = lambda: quits.append(1)
        ok(json.loads(req("POST", "/ui", {"quit": True}, token)[2])["ok"] is True and quits == [1], "POST /ui quit: answered, then the service ends")
        svc.capture = None
        ok(req("GET", "/bands")[2].decode() == ",".join(["0"] * 512), "/bands without a capture: silence, BARS per channel")
        ok(json.loads(req("GET", "/state")[2])["backend"] == "none", "/state without a capture names no backend")
        svc.capture = capture
        status, _, data, _ = req("GET", "/nothing")
        ok(status == 404 and json.loads(data) == {"error": "no such path"}, "an unknown path: 404 as {error}")
        ok(req("POST", "/monitor", {}, token)[0] == 404, "a POST to a GET path: 404")
        svc.sampler = None
        ok(req("GET", "/monitor")[0] == 503, "/monitor without a sampler: 503")
        svc.sampler = sampler
    finally:
        conn.close()
        server.shutdown()
        server.server_close()
    print("  ✓ server: routing, token, Origin, keep-alive, 304/404/503")


def test_token():
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "plaintop" / "token"
        srv.write_token(path, "abc")
        ok(path.read_text(encoding="utf-8") == "abc", "the token file holds the token")
        if os.name == "posix":
            ok(os.stat(path).st_mode & 0o777 == 0o600, "…readable by this user only")
        srv.write_token(path, "def")
        ok(path.read_text(encoding="utf-8") == "def", "a restart rewrites it")
    ok(srv.token_path().parts[-2:] == ("plaintop", "token"), "the token's place: …/plaintop/token")
    print("  ✓ token file")


if __name__ == "__main__":
    test_sampler()
    test_parsers()
    test_lhm()
    test_dispatch()
    test_hardware_lines()
    test_df()
    test_services()
    test_health()
    test_units_sound_repos_peripherals()
    test_shell()
    test_server()
    test_token()
    print(f"  ✓ win_service.py: {passed} checks passed")
