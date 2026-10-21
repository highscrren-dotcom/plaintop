#!/usr/bin/env python3
"""Assemble the Windows hosts from the shared sources, as install.sh assembles the
plasmoid packages: the shared QML is copied in next to each host (the copies are
gitignored — the sources stay in one place), the monitor's description is generated from
schema/, and the translation catalogs are converted for Qt's translator.

    python3 win/build.py [--qt DIR]      # DIR holds bin/lconvert; else PATH, else QT_DIR

lconvert must be told the target language: without it the plural forms are silently
dropped ("Removed plural forms as the target language has less forms"), and %1 update /
%1 updates would both read as the singular — verified on Qt 6.10, docs/GOTCHAS.md. The
catalog's msgctxt lands in Qt's disambiguation, which is what the hosts' i18n shim asks
for (win/host/imports/plaintop/I18n.js).
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOST = ROOT / "win" / "host"

# host directory → files copied into it, relative to the repository root.
COPIES = {
    "monitor": ["monitor/shared/MonitorData.qml", "monitor/shared/MonitorView.qml",
                "monitor/shared/SensorRegistry.qml", "monitor/package/contents/ui/ActionMenu.qml",
                "monitor/package/contents/code/description.js"],
    "spectrum": ["spectrum/shared/Ring.qml", "spectrum/shared/Spectrum.qml", "player/shared/PlayerView.qml"],
    "player": ["player/shared/PlayerView.qml"],
    "weather": ["weather/package/contents/ui/WeatherView.qml", "weather/package/contents/ui/Sources.js",
                "weather/package/contents/ui/Icons.js"],
    "calendar": ["calendar/package/contents/ui/CalendarView.qml", "calendar/package/contents/ui/Sticker.qml",
                 "calendar/package/contents/ui/Reminder.qml", "calendar/package/contents/ui/HolidayKinds.js"],
}
# The main.xml of each widget, copied for a packaged service (settings_store.py reads
# them from the repository when it runs from one).
KCFG = {w: f"{w}/package/contents/config/main.xml" for w in COPIES}
DOMAINS = {"monitor": "plaintop", "spectrum": "plainspectrum", "player": "plainplayer",
           "weather": "plainweather", "calendar": "plaincalendar"}


def find_lconvert(qt_dir):
    exe = "lconvert.exe" if os.name == "nt" else "lconvert"
    for d in (qt_dir, os.environ.get("QT_DIR"), os.environ.get("Qt6_DIR"), os.environ.get("QT_ROOT_DIR")):
        if d:
            for p in (Path(d) / "bin" / exe, Path(d) / exe):
                if p.is_file():
                    return str(p)
    return shutil.which(exe) or ""


def copy_shared():
    for target, files in COPIES.items():
        d = HOST / target
        d.mkdir(parents=True, exist_ok=True)
        for f in files:
            src = ROOT / f
            if not src.is_file():
                sys.exit(f"  ✗ missing: {f}")
            shutil.copy2(src, d / src.name)
    cfg = ROOT / "win" / "service" / "config"
    cfg.mkdir(exist_ok=True)
    for w, f in KCFG.items():
        shutil.copy2(ROOT / f, cfg / f"{w}.xml")
    # The calendar's reminder sounds, for the service to play.
    sounds = ROOT / "win" / "service" / "sounds"
    sounds.mkdir(exist_ok=True)
    for wav in (ROOT / "calendar" / "package" / "contents" / "sounds").glob("*.wav"):
        shutil.copy2(wav, sounds / wav.name)
    print(f"  ✓ shared files copied into {HOST.relative_to(ROOT)}/<widget>/")


def generate_description():
    r = subprocess.run([sys.executable, str(ROOT / "monitor" / "generate.py")], text=True)
    if r.returncode != 0:
        sys.exit("  ✗ the monitor's description did not generate")


def build_catalogs(lconvert):
    out = HOST / "i18n"
    out.mkdir(exist_ok=True)
    built = 0
    for lang_dir in sorted((ROOT / "po").iterdir()):
        if not lang_dir.is_dir():
            continue
        lang = lang_dir.name
        for w, short in DOMAINS.items():
            po = lang_dir / f"plasma_applet_org.s1dd1.{short}.po"
            if not po.is_file():
                continue
            qm = out / f"{short}_{lang}.qm"
            r = subprocess.run([lconvert, "-target-language", lang, "-i", str(po), "-o", str(qm)],
                               capture_output=True, text=True)
            if r.returncode != 0:
                sys.exit(f"  ✗ lconvert failed on {po.relative_to(ROOT)}: {r.stderr.strip()}")
            if "Removed plural forms" in r.stderr:
                sys.exit(f"  ✗ {po.relative_to(ROOT)}: the plural forms were dropped — the language was not recognised")
            built += 1
    print(f"  ✓ {built} catalogs → {out.relative_to(ROOT)}/")


def main(argv):
    qt_dir = ""
    if "--qt" in argv:
        qt_dir = argv[argv.index("--qt") + 1]
    generate_description()
    copy_shared()
    lconvert = find_lconvert(qt_dir)
    if lconvert:
        build_catalogs(lconvert)
    else:
        print("  ! lconvert not found (give --qt DIR or set QT_DIR): the hosts run in English")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
