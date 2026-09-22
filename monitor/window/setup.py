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
import filecmp
import gettext
import json
import os
import signal
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent   # <repo>/monitor/window/setup.py
SRC = REPO / "monitor"
HOME = Path.home()
UI_DEST = HOME / ".local/share/plaintop/ui"
CONFIG = HOME / ".config/plaintop/monitor.json"
AUTOSTART = HOME / ".config/autostart/plaintop-window.desktop"
LAUNCHER = HOME / ".local/share/applications/plaintop-settings.desktop"
PIDFILE = HOME / ".local/share/plaintop/window.pid"
KWINRULES = HOME / ".config/kwinrulesrc"
APPLETSRC = HOME / ".config/plasma-org.kde.plasma.desktop-appletsrc"
# Translations: the plasmoid's own catalogs, built into its package and deployed where the
# window's KI18nContext looks for them — XDG_DATA_HOME/locale (decision 7).
DOMAIN = "plasma_applet_org.s1dd1.plaintop"
LOCALE_BUILD = SRC / "package" / "contents" / "locale"
LOCALE_DEST = HOME / ".local/share/locale"
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
    "processInterval": 2,
    "colorFg": "#C8CCD4",
    "colorAccent": "#E05561",
    "colorDim": "#6B7280",
    "colorValue": "#8FB6E0",
}


def packaged_blocks():
    """The generated description: the same one the plasmoid falls back to."""
    js = SRC / "package" / "contents" / "code" / "description.js"
    if not js.exists():
        subprocess.run([sys.executable, str(SRC / "generate.py")], check=False)
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
        print(f"  • parameters filled in from the packaged description: {filled}")

    cfg["blocks"] = blocks

    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    tmp = CONFIG.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(CONFIG)
    print(f"  → {CONFIG} (blocks: {len(cfg['blocks'])}, font {cfg['fontSize']} pt"
          f"{', from the plasmoid settings' if ok else ', defaults'})")
    return cfg


REINSTALL = "./install.sh --plaintop-window"


# ── Menu and autostart entries ───────────────────────────────────────────────
# The .desktop files are UI too: English Name/Comment, plus Name[xx]/Comment[xx] for every
# language whose catalog translates them. N_ only marks the text for po/extract.py; the
# translation happens here, when the file is written, from the .mo files just built.
def N_(context, text):
    return context, text


def desktop_key(key, entry):
    context, text = entry
    out = f"{key}={text}\n"
    for mo in sorted(LOCALE_BUILD.glob(f"*/LC_MESSAGES/{DOMAIN}.mo")):
        with open(mo, "rb") as f:
            translated = gettext.GNUTranslations(f).pgettext(context, text)
        if translated != text:
            out += f"{key}[{mo.parent.parent.name}]={translated}\n"
    return out

AUTOSTART_NAME = N_("autostart entry: name", "plaintop — text monitor")
AUTOSTART_COMMENT = N_("autostart entry: comment",
                       "The monitor in its own window, clicks pass through")
LAUNCHER_NAME = N_("menu entry: name", "plaintop — monitor settings")
LAUNCHER_COMMENT = N_("menu entry: comment", "Appearance, palette and blocks of the text monitor")


def build_catalogs(quiet=False):
    """po/*/<domain>.po → LOCALE_BUILD, the same files the plasmoid package carries."""
    r = subprocess.run([sys.executable, str(REPO / "po" / "build.py"), DOMAIN, str(LOCALE_BUILD)],
                       capture_output=quiet, text=True)
    return r.returncode == 0


def deployed_files():
    """(source, destination) of every file the window runs from. One list serves both the
    copy and the status check, so the check cannot miss a file the copy gained."""
    pairs = [(SRC / "shared" / name, UI_DEST / name)
             for name in ("MonitorData.qml", "MonitorView.qml", "SensorRegistry.qml")]
    pairs += [(SRC / "window" / name, UI_DEST / name) for name in ("window.qml", "settings.qml")]
    # The services block runs this; MonitorData resolves it next to itself by default.
    pairs.append((SRC / "package" / "contents" / "code" / "services.sh",
                  UI_DEST / "services.sh"))
    pairs += [(mo, LOCALE_DEST / mo.relative_to(LOCALE_BUILD))
              for mo in sorted(LOCALE_BUILD.glob("*/LC_MESSAGES/*.mo"))]
    return pairs


def stale_files():
    """Deployed files that are missing or differ from the repository."""
    return [dst.name for src, dst in deployed_files()
            if not dst.exists() or not filecmp.cmp(src, dst, shallow=False)]


def started_before_deploy(pid):
    """True when the window was started before its newest file was deployed.

    qml6 reads the QML once, at start: a window that outlived a deploy keeps running the
    old code however well the files match.
    """
    # ⚠️ Through /proc/uptime, not the btime of /proc/stat: btime is a whole second, and
    # a window started 0.05 s after its deploy was reported as older than it.
    try:
        ticks = int(Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[19])
        uptime = float(Path("/proc/uptime").read_text().split()[0])
    except (OSError, ValueError, IndexError):
        return False
    started = time.time() - uptime + ticks / os.sysconf("SC_CLK_TCK")
    # ctime, not mtime: copy2 carries the source's mtime over, ctime is when it landed here.
    newest = max((dst.stat().st_ctime for _, dst in deployed_files() if dst.exists()), default=0)
    return started + 0.5 < newest


def files_status():
    """⚠️ Existence is not enough: on 2026-09-22 the window ran a SensorRegistry.qml one fix
    behind the repository for a day, and the status line said only "present"."""
    if not (UI_DEST / "window.qml").exists():
        return f"missing ({UI_DEST})"
    if not build_catalogs(quiet=True):
        return "⚠️ translations do not build: python3 po/build.py"
    stale = stale_files()
    if stale:
        return f"⚠️ differ from the repo: {', '.join(stale)} — redeploy: {REINSTALL}"
    return f"match the repo ({UI_DEST})"


def deploy_files():
    UI_DEST.mkdir(parents=True, exist_ok=True)
    if not build_catalogs():
        sys.exit(1)
    for src, dst in deployed_files():
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    (UI_DEST / "services.sh").chmod(0o755)
    # The editor builds its block list from the vocabulary in the generated description.
    desc = SRC / "package" / "contents" / "code" / "description.js"
    if not desc.exists():
        subprocess.run([sys.executable, str(SRC / "generate.py")], check=False)
    if desc.exists():
        shutil.copy2(desc, UI_DEST / "description.js")
    print(f"  → {UI_DEST}")


def write_autostart():
    AUTOSTART.parent.mkdir(parents=True, exist_ok=True)
    AUTOSTART.write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        + desktop_key("Name", AUTOSTART_NAME)
        + desktop_key("Comment", AUTOSTART_COMMENT)
        + f"Exec=env QML_XHR_ALLOW_FILE_READ=1 qml6 {UI_DEST / 'window.qml'}\n"
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
        + desktop_key("Name", LAUNCHER_NAME)
        + desktop_key("Comment", LAUNCHER_COMMENT)
        + f"Exec=env QML_XHR_ALLOW_FILE_READ=1 qml6 {UI_DEST / 'settings.qml'}\n"
        "Icon=utilities-system-monitor\n"
        "Terminal=false\n"
        "Categories=Settings;Utility;\n",
        encoding="utf-8")
    print(f"  → {LAUNCHER}")


def settings():
    env = dict(os.environ, QML_XHR_ALLOW_FILE_READ="1")
    subprocess.Popen(["qml6", str(UI_DEST / "settings.qml")], env=env, start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("  ✓ editor opened")


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
    print(f'  → {KWINRULES}: rule "{RULE_NAME}" ({x},{y} {width}x{height})')
    subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "reconfigure"],
                   capture_output=True, check=False)


def windows():
    """Pids of every running instance of this window, however it was started.

    ⚠️ Not a pid file: the autostart entry launches the window without writing one, so
    after a reboot the file is stale, `status` said "not running" about a live window,
    and `start` put a second copy on the desktop. And not `pkill -f`: that pattern would
    also match the shell running this script. The process table, filtered by the exact
    executable and the exact file, is the one source that cannot drift.
    """
    target = str(UI_DEST / "window.qml")
    found = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if (entry / "comm").read_text().strip() != "qml6":
                continue
            args = (entry / "cmdline").read_bytes().split(b"\0")
        except OSError:
            continue
        if any(a.decode(errors="replace") == target for a in args):
            found.append(int(entry.name))
    return found


def stop():
    pids = windows()
    if not pids:
        print("  • window is not running")
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
            print(f"  ✓ window stopped (pid {pid})")
        except ProcessLookupError:
            pass
    PIDFILE.unlink(missing_ok=True)


def start():
    stop()
    env = dict(os.environ, QML_XHR_ALLOW_FILE_READ="1")
    proc = subprocess.Popen(["qml6", str(UI_DEST / "window.qml")],
                            env=env, start_new_session=True,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    PIDFILE.parent.mkdir(parents=True, exist_ok=True)
    PIDFILE.write_text(str(proc.pid))
    print(f"  ✓ window started (pid {proc.pid})")


def status():
    print(f"  files:      {files_status()}")
    if CONFIG.exists():
        try:
            cfg = json.loads(CONFIG.read_text(encoding="utf-8"))
            print(f"  settings:   present, blocks: {len(cfg.get('blocks', []))}")
        except json.JSONDecodeError:
            print("  settings:   file present, but does not parse")
    else:
        print("  settings:   missing")
    print(f"  autostart:  {'present' if AUTOSTART.exists() else 'missing'}")
    print(f"  editor:     {'present' if LAUNCHER.exists() else 'missing'} (qml6 {UI_DEST / 'settings.qml'})")
    _, data = read_kwinrules()
    print(f"  KWin rule:  {'present' if any(v.get('Description') == RULE_NAME for v in data.values()) else 'missing'}")
    pids = windows()
    print(f"  window:     {'running (pid ' + ', '.join(map(str, pids)) + ')' if pids else 'not running'}"
          + ("  ⚠️ more than one instance" if len(pids) > 1 else ""))
    if any(started_before_deploy(pid) for pid in pids):
        print(f"  ⚠️ the window started before the files were deployed — it runs the old code: {REINSTALL}")


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
        sys.exit(f"unknown action: {action}")


if __name__ == "__main__":
    main()
