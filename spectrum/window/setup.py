#!/usr/bin/env python3
"""Deploy, start and stop the standalone (click-through) visualizer window.

⚠️ This host is retired (decision 9, docs/DECISIONS.md): the plasmoid lets both mouse
buttons through by itself, so a second host has nothing left to add. `retire` takes an
installed setup out — `./install.sh --windows-off` runs it for both widgets. The file
stays for reference; the settings file ~/.config/plainspectrum/ring.json is left alone.

⚠️ Under Wayland a window cannot place itself, so position and size come from a KWin
rule matched on the window title. The rule is written here, idempotently, next to whatever
rules the user already has.
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

REPO = Path(__file__).resolve().parent.parent.parent
SRC = REPO / "spectrum"
HOME = Path.home()
UI_DEST = HOME / ".local/share/plainspectrum/ui"
CONFIG = HOME / ".config/plainspectrum/ring.json"
AUTOSTART = HOME / ".config/autostart/plainspectrum-window.desktop"
LAUNCHER = HOME / ".local/share/applications/plainspectrum-settings.desktop"
PIDFILE = HOME / ".local/share/plainspectrum/window.pid"
KWINRULES = HOME / ".config/kwinrulesrc"
# Translations: the plasmoid's own catalogs, built into its package and deployed where the
# editor's KI18nContext looks for them — XDG_DATA_HOME/locale (decision 7).
DOMAIN = "plasma_applet_org.s1dd1.plainspectrum"
LOCALE_BUILD = SRC / "package" / "contents" / "locale"
LOCALE_DEST = HOME / ".local/share/locale"
RULE_NAME = "plainspectrum ring"
TITLE = "plainspectrum"


REINSTALL = "./install.sh --spectrum-window"


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

AUTOSTART_NAME = N_("autostart entry: name", "plainspectrum — audio visualizer")
AUTOSTART_COMMENT = N_("autostart entry: comment",
                       "The spectrum ring in its own window, clicks pass through")
LAUNCHER_NAME = N_("menu entry: name", "plainspectrum — settings")
LAUNCHER_COMMENT = N_("menu entry: comment", "Shape, colour and behaviour of the spectrum ring")


def build_catalogs(quiet=False):
    """po/*/<domain>.po → LOCALE_BUILD, the same files the plasmoid package carries."""
    r = subprocess.run([sys.executable, str(REPO / "po" / "build.py"), DOMAIN, str(LOCALE_BUILD)],
                       capture_output=quiet, text=True)
    return r.returncode == 0


def deployed_files():
    """(source, destination) of every file the window runs from. One list serves both the
    copy and the status check, so the check cannot miss a file the copy gained."""
    pairs = [(SRC / "shared" / name, UI_DEST / name) for name in ("Ring.qml", "Spectrum.qml")]
    pairs += [(SRC / "window" / name, UI_DEST / name) for name in ("window.qml", "settings.qml")]
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
    """⚠️ Existence is not enough: on 2026-09-22 the monitor window ran a SensorRegistry.qml one
    fix behind the repository for a day, and the status line said only "present"."""
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
    print(f"  → {UI_DEST}")

    if not CONFIG.exists():
        CONFIG.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SRC / "window" / "ring.default.json", CONFIG)
        print(f"  → {CONFIG} (defaults)")
    else:
        print(f"  • {CONFIG} left as is")


def write_autostart():
    # The launcher sets QML_XHR_ALLOW_FILE_READ: this host reads its own JSON config, and
    # unlike inside plasmashell that switch is ours to make.
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
    """A menu entry for the settings editor: the window host has no Plasma dialog."""
    LAUNCHER.parent.mkdir(parents=True, exist_ok=True)
    LAUNCHER.write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        + desktop_key("Name", LAUNCHER_NAME)
        + desktop_key("Comment", LAUNCHER_COMMENT)
        + f"Exec=qml6 {UI_DEST / 'settings.qml'}\n"
        "Icon=audio-volume-high\n"
        "Terminal=false\n"
        "Categories=Settings;Utility;\n",
        encoding="utf-8")
    print(f"  → {LAUNCHER}")


def settings():
    subprocess.Popen(["qml6", str(UI_DEST / "settings.qml")], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("  ✓ editor opened")


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
    PIDFILE.write_text(str(proc.pid))
    print(f"  ✓ window started (pid {proc.pid})")


def remove_rule():
    """Take our own KWin rule out of kwinrulesrc; every other rule stays as it was."""
    order, data = read_kwinrules()
    mine = [s for s, v in data.items() if v.get("Description") == RULE_NAME]
    if not mine:
        print("  • no KWin rule of ours")
        return
    for section in mine:
        order.remove(section)
        del data[section]
    general = data.setdefault("General", {})
    rules = [r for r in general.get("rules", "").split(",") if r and r not in mine]
    general["rules"] = ",".join(rules)
    general["count"] = str(len(rules))
    out = []
    for section in order:
        out.append(f"[{section}]")
        out.extend(f"{k}={v}" for k, v in data[section].items())
        out.append("")
    KWINRULES.write_text("\n".join(out), encoding="utf-8")
    subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "reconfigure"],
                   capture_output=True, check=False)
    print(f'  ✓ KWin rule "{RULE_NAME}" removed')


def retire():
    """The window host is over: the plasmoid lets both mouse buttons through by itself
    (decision 9). Stop the window and take out everything install put in place — autostart,
    editor launcher, KWin rule, deployed files, the catalogs — except the settings file,
    which is the user's."""
    stop()
    for path, what in ((AUTOSTART, "autostart entry"), (LAUNCHER, "editor launcher")):
        if path.exists():
            path.unlink()
            print(f"  ✓ {what} removed")
        else:
            print(f"  • no {what}")
    remove_rule()
    if UI_DEST.exists():
        shutil.rmtree(UI_DEST)
        print(f"  ✓ deployed files removed ({UI_DEST})")
    else:
        print("  • no deployed files")
    n = 0
    for mo in LOCALE_DEST.glob(f"*/LC_MESSAGES/{DOMAIN}.mo"):
        mo.unlink()
        n += 1
    if n:
        print(f"  ✓ window catalogs removed ({n} languages)")
    PIDFILE.unlink(missing_ok=True)
    print(f"  • settings kept: {CONFIG}")


def retired():
    return not UI_DEST.exists() and not AUTOSTART.exists()


def status():
    if retired():
        print("  retired — the plasmoid is the only host (./install.sh --windows-off)")
        return
    print(f"  files:      {files_status()}")
    print(f"  settings:   {'present' if CONFIG.exists() else 'missing'} ({CONFIG})")
    print(f"  autostart:  {'present' if AUTOSTART.exists() else 'missing'}")
    print(f"  editor:     {'present' if LAUNCHER.exists() else 'missing'} (qml6 {UI_DEST / 'settings.qml'})")
    _, data = read_kwinrules()
    has_rule = any(v.get("Description") == RULE_NAME for v in data.values())
    print(f"  KWin rule:  {'present' if has_rule else 'missing'}")
    pids = windows()
    print(f"  window:     {'running (pid ' + ', '.join(map(str, pids)) + ')' if pids else 'not running'}"
          + ("  ⚠️ more than one instance" if len(pids) > 1 else ""))
    if any(started_before_deploy(pid) for pid in pids):
        print(f"  ⚠️ the window started before the files were deployed — it runs the old code: {REINSTALL}")


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
    elif action in ("start", "stop", "status", "settings", "retire"):
        globals()[action]()
    else:
        sys.exit(f"unknown action: {action}")


if __name__ == "__main__":
    main()
