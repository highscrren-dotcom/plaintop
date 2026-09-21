#!/usr/bin/env python3
"""Deploy, start and stop the standalone (click-through) visualizer window.

Why a separate host at all: a desktop plasmoid never hands over the left mouse button —
four ways were tried, see docs/GOTCHAS.md. A plain window with
Qt.WindowTransparentForInput does.

⚠️ Under Wayland a window cannot place itself, so position and size come from a KWin
rule matched on the window title. The rule is written here, idempotently, next to whatever
rules the user already has.
"""
import json
import os
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
SRC = REPO / "spectrum"
HOME = Path.home()
UI_DEST = HOME / ".local/share/plainspectrum/ui"
CONFIG = HOME / ".config/plainspectrum/ring.json"
AUTOSTART = HOME / ".config/autostart/plainspectrum-window.desktop"
LAUNCHER = HOME / ".local/share/applications/plainspectrum-settings.desktop"
PIDFILE = HOME / ".local/share/plainspectrum/window.pid"
KWINRULES = HOME / ".config/kwinrulesrc"
RULE_NAME = "plainspectrum ring"
TITLE = "plainspectrum"


def deploy_files():
    UI_DEST.mkdir(parents=True, exist_ok=True)
    for name in ("Ring.qml", "Spectrum.qml"):
        shutil.copy2(SRC / "shared" / name, UI_DEST / name)
    for name in ("window.qml", "settings.qml"):
        shutil.copy2(SRC / "window" / name, UI_DEST / name)
    print(f"  → {UI_DEST}")

    if not CONFIG.exists():
        CONFIG.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SRC / "window" / "ring.default.json", CONFIG)
        print(f"  → {CONFIG} (по умолчанию)")
    else:
        print(f"  • {CONFIG} оставлен как есть")


def write_autostart():
    # The launcher sets QML_XHR_ALLOW_FILE_READ: this host reads its own JSON config, and
    # unlike inside plasmashell that switch is ours to make.
    AUTOSTART.parent.mkdir(parents=True, exist_ok=True)
    AUTOSTART.write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=plainspectrum — визуализатор звука\n"
        "Comment=Кольцо спектра отдельным окном, клики проходят насквозь\n"
        f"Exec=env QML_XHR_ALLOW_FILE_READ=1 qml6 {UI_DEST / 'window.qml'}\n"
        "Terminal=false\n"
        "X-GNOME-Autostart-enabled=true\n"
        "X-KDE-autostart-after=panel\n",
        encoding="utf-8")
    print(f"  → {AUTOSTART}")


def write_launcher():
    """A menu entry for the settings editor: the window host has no Plasma dialog."""
    LAUNCHER.parent.mkdir(parents=True, exist_ok=True)
    LAUNCHER.write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=plainspectrum — настройки\n"
        "Comment=Форма, цвет и поведение кольца спектра\n"
        f"Exec=qml6 {UI_DEST / 'settings.qml'}\n"
        "Icon=audio-volume-high\n"
        "Terminal=false\n"
        "Categories=Settings;Utility;\n",
        encoding="utf-8")
    print(f"  → {LAUNCHER}")


def settings():
    subprocess.Popen(["qml6", str(UI_DEST / "settings.qml")], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("  ✓ редактор открыт")


def read_kwinrules():
    """Parse kwinrulesrc into (order, {section: {key: value}})."""
    order, data, section = [], {}, None
    if KWINRULES.exists():
        for line in KWINRULES.read_text(encoding="utf-8").split("\n"):
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1]
                if section not in data:
                    order.append(section)
                    data[section] = {}
            elif "=" in line and section is not None:
                key, _, value = line.partition("=")
                data[section][key] = value
    return order, data


def write_kwinrules(order, data):
    out = []
    for section in order:
        out.append(f"[{section}]")
        for key, value in data[section].items():
            out.append(f"{key}={value}")
        out.append("")
    KWINRULES.parent.mkdir(parents=True, exist_ok=True)
    KWINRULES.write_text("\n".join(out), encoding="utf-8")


def ensure_rule(x, y, width, height):
    """Force position, size, keep-below and skip-taskbar for our window title."""
    order, data = read_kwinrules()

    # Reuse our own rule if it is already there; never touch anyone else's.
    mine = None
    for section, values in data.items():
        if values.get("Description") == RULE_NAME:
            mine = section
            break
    if mine is None:
        mine = str(uuid.uuid4())
        order.append(mine)
        data[mine] = {}

    # Rule verbs: 2 = Force, 3 = Apply. Position and size are forced, or KWin re-centres
    # the window on every start.
    data[mine].update({
        "Description": RULE_NAME,
        "title": TITLE,
        "titlematch": "1",           # exact match
        "types": "1",                # normal window
        "position": f"{x},{y}",
        "positionrule": "2",
        "size": f"{width},{height}",
        "sizerule": "2",
        "below": "true",
        "belowrule": "2",
        "skiptaskbar": "true",
        "skiptaskbarrule": "2",
        "skippager": "true",
        "skippagerrule": "2",
        "skipswitcher": "true",
        "skipswitcherrule": "2",
        "noborder": "true",
        "noborderrule": "2",
        "acceptfocus": "false",
        "acceptfocusrule": "2",
    })

    general = data.setdefault("General", {})
    if "General" not in order:
        order.insert(0, "General")
    rules = [r for r in general.get("rules", "").split(",") if r]
    if mine not in rules:
        rules.append(mine)
    general["rules"] = ",".join(rules)
    general["count"] = str(len(rules))

    write_kwinrules(order, data)
    print(f"  → {KWINRULES}: правило «{RULE_NAME}» ({x},{y} {width}x{height})")
    subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "reconfigure"],
                   capture_output=True, check=False)


def stop():
    """Stop by recorded pid: matching the command line with pkill -f would also match
    this script's own invocation — that mistake already cost a shell in this project."""
    if not PIDFILE.exists():
        print("  • окно не запущено (нет pid-файла)")
        return
    pid = PIDFILE.read_text().strip()
    if pid.isdigit() and Path(f"/proc/{pid}").exists():
        subprocess.run(["kill", pid], check=False)
        print(f"  ✓ окно остановлено (pid {pid})")
    else:
        print("  • процесса по записанному pid нет")
    PIDFILE.unlink(missing_ok=True)


def start():
    stop()
    env = dict(os.environ, QML_XHR_ALLOW_FILE_READ="1")
    proc = subprocess.Popen(["qml6", str(UI_DEST / "window.qml")],
                            env=env, start_new_session=True,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    PIDFILE.write_text(str(proc.pid))
    print(f"  ✓ окно запущено (pid {proc.pid})")


def status():
    print(f"  файлы:      {'есть' if (UI_DEST / 'window.qml').exists() else 'нет'} ({UI_DEST})")
    print(f"  настройки:  {'есть' if CONFIG.exists() else 'нет'} ({CONFIG})")
    print(f"  автозапуск: {'есть' if AUTOSTART.exists() else 'нет'}")
    print(f"  редактор:   {'есть' if LAUNCHER.exists() else 'нет'} (qml6 {UI_DEST / 'settings.qml'})")
    _, data = read_kwinrules()
    has_rule = any(v.get("Description") == RULE_NAME for v in data.values())
    print(f"  правило KWin: {'есть' if has_rule else 'нет'}")
    alive = PIDFILE.exists() and Path(f"/proc/{PIDFILE.read_text().strip()}").exists()
    print(f"  окно:       {'работает' if alive else 'не запущено'}")


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "install"
    if action == "install":
        cfg = json.loads((SRC / "window" / "ring.default.json").read_text(encoding="utf-8"))
        if CONFIG.exists():
            try:
                cfg.update(json.loads(CONFIG.read_text(encoding="utf-8")))
            except json.JSONDecodeError:
                pass
        side = 2 * (cfg["radius"] + cfg["minLength"] + cfg["maxLength"] + cfg["thickness"])
        deploy_files()
        write_autostart()
        write_launcher()
        ensure_rule(int(os.environ.get("PLAINSPECTRUM_X", 700)),
                    int(os.environ.get("PLAINSPECTRUM_Y", 170)),
                    side, side)
        start()
    elif action in ("start", "stop", "status", "settings"):
        globals()[action]()
    else:
        sys.exit(f"неизвестное действие: {action}")


if __name__ == "__main__":
    main()
