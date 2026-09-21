#!/usr/bin/env python3
"""Deploy, start and stop the standalone (click-through) text monitor window.

A desktop plasmoid never hands over the left mouse button; a plain window with
Qt.WindowTransparentForInput does — see docs/GOTCHAS.md.

⚠️ Under Wayland a window cannot place itself, so position and size come from a KWin
rule matched on the window title. The rule is written here, next to whatever rules the
user already has, and never touches anyone else's.

Settings live in ~/.config/plaintop/monitor.json. `export` fills that file from the
plasmoid's own settings dialog, so the dialog stays the editor for both hosts until the
window host gets one of its own.
"""
import json
import os
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent   # <repo>/plaintop/window/setup.py
SRC = REPO / "plaintop"
HOME = Path.home()
UI_DEST = HOME / ".local/share/plaintop/ui"
CONFIG = HOME / ".config/plaintop/monitor.json"
AUTOSTART = HOME / ".config/autostart/plaintop-window.desktop"
LAUNCHER = HOME / ".local/share/applications/plaintop-settings.desktop"
PIDFILE = HOME / ".local/share/plaintop/window.pid"
KWINRULES = HOME / ".config/kwinrulesrc"
APPLETSRC = HOME / ".config/plasma-org.kde.plasma.desktop-appletsrc"
RULE_NAME = "plaintop monitor"
TITLE = "plaintop"

DEFAULTS = {
    "fontFamily": "JetBrainsMono Nerd Font Mono",
    "fontSize": 10,
    "padLeft": 48,
    "padTop": 44,
    "widgetWidth": 500,
    "widgetHeight": 950,
    "updateInterval": 1000,
    "colorFg": "#C8CCD4",
    "colorAccent": "#E05561",
    "colorDim": "#6B7280",
    "colorValue": "#8FB6E0",
}


def packaged_blocks():
    """The generated description: the same one the plasmoid falls back to."""
    js = REPO / "plasmoid" / "package" / "contents" / "code" / "description.js"
    if not js.exists():
        subprocess.run([sys.executable, str(REPO / "plasmoid" / "generate.py")], check=False)
    if not js.exists():
        return []
    text = js.read_text(encoding="utf-8")
    start = text.index("var BLOCKS = ") + len("var BLOCKS = ")
    end = text.index("var VOCAB = ")
    return json.loads(text[start:end].strip())


def plasmoid_settings():
    """Read the plasmoid's own settings, so the dialog can serve both hosts.

    ⚠️ Read straight from the config file rather than through the running shell: the
    values are in [Containments][N][Applets][M][Configuration][General], and a stopped
    plasmashell would leave a D-Bus query with nothing to answer it.
    """
    if not APPLETSRC.exists():
        return {}, None
    values, section, found = {}, None, None
    for line in APPLETSRC.read_text(encoding="utf-8").split("\n"):
        if line.startswith("["):
            section = line
        elif "=" in line and section and section.endswith("[Configuration][General]"):
            key, _, value = line.partition("=")
            if key == "plugin":
                continue
            values.setdefault(section, {})[key] = value
    # The applet that has our own keys is the one we want.
    for sect, keys in values.items():
        if "blocksJson" in keys or "padLeft" in keys or "fontFamily" in keys:
            found = keys
    return found or {}, found is not None


def build_config(overwrite_blocks=True):
    cfg = dict(DEFAULTS)
    if CONFIG.exists():
        try:
            cfg.update(json.loads(CONFIG.read_text(encoding="utf-8")))
        except json.JSONDecodeError:
            pass

    stored, ok = plasmoid_settings()
    for key in DEFAULTS:
        if key in stored:
            raw = stored[key]
            cfg[key] = int(raw) if isinstance(DEFAULTS[key], int) and raw.isdigit() else raw

    blocks = cfg.get("blocks") or []
    if overwrite_blocks or not blocks:
        raw = stored.get("blocksJson", "")
        if raw:
            try:
                parsed = json.loads(raw.replace("\\\\", "\\"))
                if isinstance(parsed, list) and parsed:
                    blocks = parsed
            except json.JSONDecodeError:
                pass
        if not blocks:
            blocks = packaged_blocks()
    # ⚠️ Fill parameters the user's own layout predates. New params (a fan sensor id, an
    # NVMe sensor id) are empty in the vocabulary on purpose — machine-specific values live
    # in schema/widget.json — so a saved layout would silently lose those readings. This
    # takes them from the packaged block of the same type once.
    reference = {}
    for b in packaged_blocks():
        reference.setdefault(b["type"], b.get("params", {}))
    filled = 0
    for b in blocks:
        params = b.setdefault("params", {})
        for key, value in reference.get(b["type"], {}).items():
            if key not in params:
                params[key] = value
                filled += 1
    if filled:
        print(f"  • параметров дополнено из пакетного описания: {filled}")

    cfg["blocks"] = blocks

    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    tmp = CONFIG.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(CONFIG)
    print(f"  → {CONFIG} ({len(cfg['blocks'])} блоков, шрифт {cfg['fontSize']} пт"
          f"{', из настроек плазмоида' if ok else ', по умолчанию'})")
    return cfg


def deploy_files():
    UI_DEST.mkdir(parents=True, exist_ok=True)
    for name in ("MonitorData.qml", "MonitorView.qml", "SensorRegistry.qml"):
        shutil.copy2(SRC / "shared" / name, UI_DEST / name)
    for name in ("window.qml", "settings.qml"):
        shutil.copy2(SRC / "window" / name, UI_DEST / name)
    # The editor builds its block list from the vocabulary in the generated description.
    desc = REPO / "plasmoid" / "package" / "contents" / "code" / "description.js"
    if not desc.exists():
        subprocess.run([sys.executable, str(REPO / "plasmoid" / "generate.py")], check=False)
    if desc.exists():
        shutil.copy2(desc, UI_DEST / "description.js")
    # The services block runs this; MonitorData resolves it next to itself by default.
    shutil.copy2(REPO / "plasmoid" / "package" / "contents" / "code" / "services.sh",
                 UI_DEST / "services.sh")
    (UI_DEST / "services.sh").chmod(0o755)
    print(f"  → {UI_DEST}")


def write_autostart():
    AUTOSTART.parent.mkdir(parents=True, exist_ok=True)
    AUTOSTART.write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=plaintop — текстовый монитор\n"
        "Comment=Монитор отдельным окном, клики проходят насквозь\n"
        f"Exec=env QML_XHR_ALLOW_FILE_READ=1 qml6 {UI_DEST / 'window.qml'}\n"
        "Terminal=false\n"
        "X-GNOME-Autostart-enabled=true\n"
        "X-KDE-autostart-after=panel\n",
        encoding="utf-8")
    print(f"  → {AUTOSTART}")


def write_launcher():
    """A menu entry for the editor: this host has no Plasma dialog."""
    LAUNCHER.parent.mkdir(parents=True, exist_ok=True)
    LAUNCHER.write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=plaintop — настройки монитора\n"
        "Comment=Вид, палитра и блоки текстового монитора\n"
        f"Exec=env QML_XHR_ALLOW_FILE_READ=1 qml6 {UI_DEST / 'settings.qml'}\n"
        "Icon=utilities-system-monitor\n"
        "Terminal=false\n"
        "Categories=Settings;Utility;\n",
        encoding="utf-8")
    print(f"  → {LAUNCHER}")


def settings():
    env = dict(os.environ, QML_XHR_ALLOW_FILE_READ="1")
    subprocess.Popen(["qml6", str(UI_DEST / "settings.qml")], env=env, start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("  ✓ редактор открыт")


def read_kwinrules():
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


def ensure_rule(x, y, width, height):
    order, data = read_kwinrules()
    mine = None
    for section, values in data.items():
        if values.get("Description") == RULE_NAME:
            mine = section
            break
    if mine is None:
        mine = str(uuid.uuid4())
        order.append(mine)
        data[mine] = {}

    data[mine].update({
        "Description": RULE_NAME,
        "title": TITLE,
        "titlematch": "1",
        "types": "1",
        "position": f"{x},{y}",
        "positionrule": "2",        # 2 = Force, or KWin re-centres it on every start
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

    out = []
    for section in order:
        out.append(f"[{section}]")
        out.extend(f"{k}={v}" for k, v in data[section].items())
        out.append("")
    KWINRULES.parent.mkdir(parents=True, exist_ok=True)
    KWINRULES.write_text("\n".join(out), encoding="utf-8")
    print(f"  → {KWINRULES}: правило «{RULE_NAME}» ({x},{y} {width}x{height})")
    subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "reconfigure"],
                   capture_output=True, check=False)


def stop():
    """Stop by recorded pid: pkill -f on the command line would also match this script."""
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
    PIDFILE.parent.mkdir(parents=True, exist_ok=True)
    PIDFILE.write_text(str(proc.pid))
    print(f"  ✓ окно запущено (pid {proc.pid})")


def status():
    print(f"  файлы:      {'есть' if (UI_DEST / 'window.qml').exists() else 'нет'} ({UI_DEST})")
    if CONFIG.exists():
        try:
            cfg = json.loads(CONFIG.read_text(encoding="utf-8"))
            print(f"  настройки:  есть, блоков {len(cfg.get('blocks', []))}")
        except json.JSONDecodeError:
            print("  настройки:  файл есть, но не разбирается")
    else:
        print("  настройки:  нет")
    print(f"  автозапуск: {'есть' if AUTOSTART.exists() else 'нет'}")
    print(f"  редактор:   {'есть' if LAUNCHER.exists() else 'нет'} (qml6 {UI_DEST / 'settings.qml'})")
    _, data = read_kwinrules()
    print(f"  правило KWin: {'есть' if any(v.get('Description') == RULE_NAME for v in data.values()) else 'нет'}")
    alive = PIDFILE.exists() and Path(f"/proc/{PIDFILE.read_text().strip()}").exists()
    print(f"  окно:       {'работает' if alive else 'не запущено'}")


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "install"
    if action == "install":
        deploy_files()
        cfg = build_config(overwrite_blocks=False)
        write_autostart()
        write_launcher()
        ensure_rule(int(os.environ.get("PLAINTOP_X", 0)), int(os.environ.get("PLAINTOP_Y", 0)),
                    int(cfg["widgetWidth"]), int(cfg["widgetHeight"]))
        start()
    elif action == "export":
        cfg = build_config(overwrite_blocks=True)
        ensure_rule(int(os.environ.get("PLAINTOP_X", 0)), int(os.environ.get("PLAINTOP_Y", 0)),
                    int(cfg["widgetWidth"]), int(cfg["widgetHeight"]))
    elif action in ("start", "stop", "status", "settings"):
        globals()[action]()
    else:
        sys.exit(f"неизвестное действие: {action}")


if __name__ == "__main__":
    main()
