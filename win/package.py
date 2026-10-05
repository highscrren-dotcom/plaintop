#!/usr/bin/env python3
"""Pack the Windows port into one folder, then a zip: dist/plaintop-win/.

    python win\\package.py --qt C:\\Qt\\6.11.3\\msvc2022_64

What goes in:
  plaintop.exe, _internal/   the service and the launcher, frozen by PyInstaller
  host/                      the hosts, the shims, the built copies and the catalogs (win/build.py)
  qt/bin/qml.exe + DLLs, qt/qml/   Qt's qml tool with the modules the hosts import, by windeployqt
  service/config/, service/sounds/, calendar/notes.py, spectrum/relay.py   what the service reads at run time

The frozen service finds qml.exe at qt/bin/ beside host/ (ui.find_qml), notes.py through
PLAINTOP_NOTES set by the launcher stub below, and the relay's functions by the path the
server resolves. Needs: pip install pyinstaller; a Qt with windeployqt. Written without a
Windows machine: the CI job runs it on windows-latest and keeps the result as an artifact —
that run is its verification.
"""
import importlib.util
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist" / "plaintop-win"


def tool(name, qt_dir):
    exe = name + (".exe" if os.name == "nt" else "")
    for d in (qt_dir, os.environ.get("QT_DIR"), os.environ.get("QT_ROOT_DIR")):
        if d and (Path(d) / "bin" / exe).is_file():
            return str(Path(d) / "bin" / exe)
    return shutil.which(exe) or ""


def main(argv):
    qt_dir = argv[argv.index("--qt") + 1] if "--qt" in argv else ""
    if subprocess.run([sys.executable, str(ROOT / "win" / "build.py")] + (["--qt", qt_dir] if qt_dir else [])).returncode != 0:
        sys.exit("  ✗ build.py failed")
    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir(parents=True)

    # The hosts, with the built copies and the catalogs.
    shutil.copytree(ROOT / "win" / "host", DIST / "host", ignore=shutil.ignore_patterns("__pycache__"))
    # What the service reads beside itself at run time.
    for sub in ("config", "sounds"):
        shutil.copytree(ROOT / "win" / "service" / sub, DIST / "service" / sub)
    (DIST / "calendar").mkdir()
    shutil.copy2(ROOT / "calendar" / "package" / "contents" / "code" / "notes.py", DIST / "calendar" / "notes.py")
    (DIST / "spectrum").mkdir()
    shutil.copy2(ROOT / "spectrum" / "relay.py", DIST / "spectrum" / "relay.py")

    # Qt: the qml tool and whatever the hosts import, found by windeployqt from the QML.
    qml = tool("qml", qt_dir)
    deploy = tool("windeployqt", qt_dir)
    if not qml or not deploy:
        sys.exit("  ✗ qml and windeployqt are needed: give --qt DIR")
    qt_bin = DIST / "qt" / "bin"
    qt_bin.mkdir(parents=True)
    shutil.copy2(qml, qt_bin / Path(qml).name)
    r = subprocess.run([deploy, "--qmldir", str(ROOT / "win" / "host"), "--qmldir", str(ROOT / "win" / "host" / "imports"),
                        "--no-translations", "--qmlimport", str(ROOT / "win" / "host" / "imports"),
                        str(qt_bin / Path(qml).name)])
    if r.returncode != 0:
        sys.exit("  ✗ windeployqt failed")

    # The service, frozen. The launcher is win/plaintop.py; the service's modules are
    # imported by name from win/service, so they are hidden imports here.
    hidden = ["server", "paths", "monitor_win", "gpu_win", "exec_win", "bands", "player_win", "notes_bridge", "holidays_win",
              "timezones", "settings_store", "ui", "notify_win"]
    cmd = [sys.executable, "-m", "PyInstaller", "--noconfirm", "--onedir", "--name", "plaintop",
           "--distpath", str(DIST.parent / "_py"), "--workpath", str(DIST.parent / "_work"),
           "--specpath", str(DIST.parent / "_work"), "--paths", str(ROOT / "win" / "service"),
           "--noconsole", str(ROOT / "win" / "plaintop.py")]
    # notes.py and relay.py are loaded by path at run time, so the analysis never sees
    # what they import: the standard library modules they need are named here.
    hidden += ["argparse", "binascii", "configparser", "http.client", "http.server", "secrets", "socket",
               "ssl", "webbrowser", "xml.etree.ElementTree", "zoneinfo", "urllib.parse"]
    for h in hidden:
        cmd += ["--hidden-import", h]
    # holidays' country modules are imported lazily by the package, and its names come
    # from gettext catalogs under holidays/locale/ — data, which --collect-submodules
    # leaves out: the first frozen /holidays answered "No translation file found for
    # domain". tzdata's zones are data too, when the package is there (Windows has no
    # zone database of its own for zoneinfo).
    cmd += ["--collect-submodules", "holidays", "--collect-data", "holidays"]
    if importlib.util.find_spec("tzdata") is not None:
        cmd += ["--collect-data", "tzdata"]
    # The capture and the media session, whichever is installed where the zip is built:
    # soundcard reads its C declarations from a header beside its module (data), the
    # WinRT projections are imported by name at run time (player_win), unseen by the
    # analysis. The first desk had neither: no spectrum, "no player".
    optional = (("soundcard", ["--hidden-import", "soundcard", "--collect-data", "soundcard"]),
                ("pyaudiowpatch", ["--hidden-import", "pyaudiowpatch"]),
                ("winsdk", ["--hidden-import", "winsdk.windows.media.control", "--hidden-import", "winsdk._winrt",
                            "--hidden-import", "winsdk.system"]),
                ("winrt.windows.media.control", ["--hidden-import", "winrt.windows.media.control",
                                                 "--hidden-import", "winrt.system", "--hidden-import", "winrt.windows.foundation",
                                                 "--hidden-import", "winrt.windows.storage.streams"]))
    for pkg, extra in optional:
        try:
            present = importlib.util.find_spec(pkg) is not None
        except (ImportError, ValueError):
            present = False
        print(f"  {'+' if present else '-'} {pkg}")
        if present:
            cmd += extra
    if subprocess.run(cmd).returncode != 0:
        sys.exit("  ✗ PyInstaller failed")
    frozen = DIST.parent / "_py" / "plaintop"
    for item in frozen.iterdir():
        dest = DIST / item.name
        if item.is_dir():
            shutil.copytree(item, dest)
        else:
            shutil.copy2(item, dest)
    shutil.rmtree(DIST.parent / "_py")
    shutil.rmtree(DIST.parent / "_work")

    (DIST / "README.txt").write_text(
        "plaintop for Windows 11 — https://github.com/highscrren-dotcom/plaintop\n\n"
        "Run plaintop.exe: the service, the widgets and the tray icon. Settings are in\n"
        "%APPDATA%\\plaintop\\*.ini. Autostart: a shortcut to plaintop.exe in shell:startup.\n"
        "The font JetBrainsMono Nerd Font Mono is not included: https://www.nerdfonts.com\n"
        "Details: win/README.md in the repository.\n", encoding="utf-8")
    out = ROOT / "dist" / "plaintop-win.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in DIST.rglob("*"):
            if f.is_file():
                z.write(f, f.relative_to(DIST.parent))
    print(f"  ✓ {out.relative_to(ROOT)} ({out.stat().st_size // 1024 // 1024} MiB)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
