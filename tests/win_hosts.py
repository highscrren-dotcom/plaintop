#!/usr/bin/env python3
"""Driver for tests/win_hosts.qml and tests/win_settings.qml: builds the hosts, starts the
service, runs the two QtTest stands offscreen against it, stops the service.

    python3 tests/win_hosts.py [--qt DIR] [--service PATH] [--keep] [--only hosts|settings]

DIR holds bin/qmltestrunner and bin/lconvert (else QT_DIR, QT_ROOT_DIR, PATH). The service
is win/service/server.py unless --service names another program that speaks
win/PROTOCOL.md (a stand-in for a machine without the real sources). The port is a free
one and the token is made here and given to the service through PLAINTOP_TOKEN; both reach
the stand through a generated QML module, because qmltestrunner passes no arguments of
its own through to the QML it runs.
"""
import os
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

# The runner's pipe on Windows is cp1252: the check marks below would raise.
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent


def find_tool(name, qt_dir):
    exe = name + (".exe" if os.name == "nt" else "")
    for d in (qt_dir, os.environ.get("QT_DIR"), os.environ.get("QT_ROOT_DIR"), os.environ.get("Qt6_DIR")):
        if d and (Path(d) / "bin" / exe).is_file():
            return str(Path(d) / "bin" / exe)
    return shutil.which(exe) or ""


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_for(url, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=1) as r:
                if r.status == 200:
                    return True
        except Exception:
            time.sleep(0.2)
    return False


def main(argv):
    qt_dir = argv[argv.index("--qt") + 1] if "--qt" in argv else ""
    service = argv[argv.index("--service") + 1] if "--service" in argv else str(ROOT / "win" / "service" / "server.py")
    runner = find_tool("qmltestrunner", qt_dir)
    if not runner:
        sys.exit("  ✗ qmltestrunner not found: give --qt DIR or set QT_DIR")
    build = [sys.executable, str(ROOT / "win" / "build.py")] + (["--qt", qt_dir] if qt_dir else [])
    if subprocess.run(build).returncode != 0:
        sys.exit("  ✗ win/build.py failed")

    port = free_port()
    token = secrets.token_urlsafe(16)
    env = dict(os.environ, PLAINTOP_PORT=str(port), PLAINTOP_TOKEN=token, PLAINTOP_NO_HOSTS="1")
    proc = subprocess.Popen([sys.executable, service, str(port)], env=env)
    try:
        if not wait_for(f"http://127.0.0.1:{port}/monitor", 20):
            sys.exit("  ✗ the service did not answer /monitor within 20 s")
        with tempfile.TemporaryDirectory(prefix="plaintop-stand-") as tmp:
            mod = Path(tmp) / "standargs"
            mod.mkdir()
            (mod / "qmldir").write_text("module standargs\nsingleton StandArgs 1.0 StandArgs.qml\n", encoding="utf-8")
            (mod / "StandArgs.qml").write_text(
                "pragma Singleton\nimport QtQuick\nQtObject { readonly property int port: %d\n"
                "    readonly property string token: %r }\n" % (port, token), encoding="utf-8")
            qenv = dict(os.environ, QT_QPA_PLATFORM=os.environ.get("QT_QPA_PLATFORM", "offscreen"),
                        QT_FORCE_STDERR_LOGGING="1")
            only = argv[argv.index("--only") + 1] if "--only" in argv else ""
            stands = [n for n in ("win_hosts", "win_settings") if not only or n.endswith(only)]
            for name in stands:
                cmd = [runner, "-import", str(ROOT / "win" / "host" / "imports"), "-import", tmp,
                       "-input", str(ROOT / "tests" / f"{name}.qml")]
                print("  →", " ".join(cmd), flush=True)
                code = subprocess.run(cmd, env=qenv, cwd=str(ROOT)).returncode
                if code != 0:
                    return code
            return 0
    finally:
        if "--keep" not in argv:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
