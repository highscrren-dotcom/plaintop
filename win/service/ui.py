"""The process manager: starts and stops the widget hosts, the settings window and the
tray, and answers /ui.

A host is `qml.exe` from Qt 6 running one of win/host/*.qml — nothing of our own in C++.
This module finds qml.exe, builds its command line (the import path of the shims, the
catalog of the user's language, the service's port and the write token after `--`), and
keeps the processes it started; nothing else is ever killed. With `behindIcons` on, a
host's window is parented under the wallpaper's WorkerW through user32, the way
wallpaper engines do — unverified on a desktop as of this writing, see win/README.md.
"""
import ctypes
import locale
import os
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

WIDGETS = ("monitor", "spectrum", "player", "weather", "calendar")
# po/<lang>/ directories the catalogs are built from (win/build.py).
LANGUAGES = ("de", "es", "fr", "ja", "pl", "pt_BR", "ru", "uk", "zh_CN")
DOMAINS = {"monitor": "plaintop", "spectrum": "plainspectrum", "player": "plainplayer",
           "weather": "plainweather", "calendar": "plaincalendar",
           "tray": "plaintop"}         # the tray's strings live in the monitor's catalog


def ui_language():
    """The user's interface language as a po/ directory name, or "" for English."""
    name = ""
    if os.name == "nt":
        try:
            langid = ctypes.windll.kernel32.GetUserDefaultUILanguage()
            name = locale.windows_locale.get(langid, "")
        except Exception:
            name = ""
    if not name:
        name = os.environ.get("LANGUAGE", "").split(":")[0] or (locale.getlocale()[0] or "")
    name = name.replace("-", "_")
    if name in LANGUAGES:
        return name
    short = name.split("_")[0]
    if short in LANGUAGES:
        return short
    if short == "pt":
        return "pt_BR"
    if short == "zh":
        return "zh_CN"
    return ""


def find_qml(host_dir):
    """qml.exe: the environment first, then PATH, then a Qt beside the service (the zip
    the packager builds), then the usual Qt installer places."""
    env = os.environ.get("PLAINTOP_QML")
    if env and Path(env).is_file():
        return env
    exe = "qml.exe" if os.name == "nt" else "qml"
    found = shutil.which(exe)
    if found:
        return found
    here = Path(host_dir).resolve().parent
    # The zip the packager builds: plaintop.exe, host/ and qt/bin/ side by side.
    for p in (here / "qt" / "bin" / exe, here.parent / "qt" / "bin" / exe, Path(sys.argv[0]).resolve().parent / "qt" / "bin" / exe):
        if p.is_file():
            return str(p)
    if os.name == "nt":
        for root in (Path("C:/Qt"),):
            if root.is_dir():
                for p in sorted(root.glob("6.*/*/bin/qml.exe"), reverse=True):
                    return str(p)
    return ""


class Manager:
    def __init__(self, host_dir, port, token, qml=None, store=None):
        self.host_dir = Path(host_dir).resolve()
        self.port = port
        self.token = token
        self.store = store
        self.qml = qml or find_qml(self.host_dir)
        self.lang = ui_language()
        self.procs = {}                 # name → Popen
        self.lock = threading.Lock()
        self.quitting = False

    # ── command lines ─────────────────────────────────────────────────────────
    def catalog(self, widget):
        if not self.lang:
            return None
        qm = self.host_dir / "i18n" / f"{DOMAINS.get(widget, widget)}_{self.lang}.qm"
        return str(qm) if qm.is_file() else None

    def command(self, qml_file, widget, extra=(), transparent=True, widgets=False):
        """qml's command line. `--transparent` asks for an alpha channel in the window's
        surface — without it a "transparent" window is black on Windows; `-a widget` is
        the QApplication the tray icon needs (Qt.labs.platform has no native tray without
        Qt Widgets)."""
        cmd = [self.qml, "-I", str(self.host_dir / "imports")]
        if transparent:
            cmd.append("--transparent")
        if widgets:
            cmd += ["-a", "widget"]
        qm = self.catalog(widget)
        if qm:
            cmd += ["-translation", qm]
        cmd += [str(self.host_dir / qml_file), "--",
                "--port", str(self.port), "--token", self.token, "--widget", widget]
        cmd += list(extra)
        return cmd

    def spawn(self, name, cmd):
        if not self.qml:
            raise RuntimeError("qml.exe not found: set PLAINTOP_QML or put Qt's bin on PATH")
        kwargs = {}
        if os.name == "nt":
            # No console window for a GUI host; the output still reaches our stderr.
            kwargs["creationflags"] = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        env = dict(os.environ)
        # A non-native Controls style: the Windows style refuses the customised rows of the
        # settings window ("does not support customization of this control") and complains
        # offscreen; Fusion draws the same everywhere.
        env.setdefault("QT_QUICK_CONTROLS_STYLE", "Fusion")
        env.setdefault("QT_QPA_PLATFORM", os.environ.get("PLAINTOP_QPA", "windows" if os.name == "nt" else env.get("QT_QPA_PLATFORM", "")))
        if not env["QT_QPA_PLATFORM"]:
            del env["QT_QPA_PLATFORM"]
        proc = subprocess.Popen(cmd, stdout=sys.stderr, stderr=subprocess.STDOUT, env=env, **kwargs)
        with self.lock:
            self.procs[name] = proc
        return proc

    def running(self, name):
        p = self.procs.get(name)
        return p is not None and p.poll() is None

    # ── the widgets ───────────────────────────────────────────────────────────
    def show(self, widget, on=True):
        if widget not in WIDGETS:
            raise KeyError(widget)
        if on:
            if not self.running(widget):
                self.spawn(widget, self.command(f"{widget}.qml", widget))
                if self.store is not None:
                    behind = self.store.get(widget)[1].get("behindIcons") is True
                    if behind:
                        threading.Thread(target=self.behind_icons, args=(widget,), daemon=True).start()
        else:
            self.stop(widget)
        if self.store is not None:
            self.store.update(widget, {"shown": bool(on)})

    def stop(self, name):
        with self.lock:
            p = self.procs.pop(name, None)
        if p is None or p.poll() is not None:
            return
        p.terminate()
        try:
            p.wait(timeout=3)
        except subprocess.TimeoutExpired:
            p.kill()

    def settings(self, widget):
        name = f"settings-{widget}"
        if self.running(name):
            return
        self.spawn(name, self.command("settings.qml", widget, transparent=False))

    def tray(self):
        if not self.running("tray"):
            self.spawn("tray", self.command("tray.qml", "tray", transparent=False, widgets=True))

    def start_shown(self):
        """At launch: every widget whose `shown` setting is on, and the tray."""
        for w in WIDGETS:
            try:
                shown = self.store.get(w)[1].get("shown", True) if self.store is not None else True
            except KeyError:
                shown = True
            if shown:
                try:
                    self.show(w, True)
                except RuntimeError as e:
                    print(f"plaintop: {e}", file=sys.stderr, flush=True)
                    return
        try:
            self.tray()
        except RuntimeError:
            pass

    def quit(self):
        self.quitting = True
        for name in list(self.procs):
            self.stop(name)

    # ── /ui ───────────────────────────────────────────────────────────────────
    def status(self):
        return {"qml": self.qml, "language": self.lang,
                "running": {n: p.pid for n, p in self.procs.items() if p.poll() is None}}

    def handle(self, req):
        req = req or {}
        if "show" in req:
            self.show(str(req["show"]), req.get("on", True) is True)
        elif "settings" in req:
            self.settings(str(req["settings"]))
        elif "behind" in req:
            if req.get("on", True) is True:
                self.behind_icons(str(req["behind"]))
            else:
                self.unparent(str(req["behind"]))
        elif req.get("quit") is True:
            self.quit()
        elif req.get("restart") is not None:
            w = str(req["restart"])
            self.stop(w)
            self.show(w, True)
        else:
            return {"error": "unknown request"}
        return {"ok": True, **self.status()}

    # ── behind the desktop icons ──────────────────────────────────────────────
    # The desktop is Progman; told 0x052C it spawns a WorkerW behind the icon view
    # (SHELLDLL_DefView), and a window parented under that WorkerW draws between the
    # wallpaper and the icons. On Windows 11 24H2 the WorkerW became a child of Progman
    # rather than its sibling, so both places are searched. Nothing here is verified on a
    # desktop yet: the user's check — win/README.md.
    def window_of(self, pid):
        if os.name != "nt":
            return 0
        user32 = ctypes.windll.user32
        found = []
        proto = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)

        def each(hwnd, _):
            owner = ctypes.c_ulong()
            user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
            if owner.value == pid and user32.IsWindowVisible(hwnd):
                found.append(hwnd)
            return True
        user32.EnumWindows(proto(each), 0)
        return found[0] if found else 0

    def workerw(self):
        if os.name != "nt":
            return 0
        user32 = ctypes.windll.user32
        progman = user32.FindWindowW("Progman", None)
        if not progman:
            return 0
        result = ctypes.c_ulong()
        user32.SendMessageTimeoutW(progman, 0x052C, 0, 0, 0, 1000, ctypes.byref(result))
        # The sibling arrangement: the WorkerW right after the window holding the icons.
        hwnd = 0
        proto = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
        holder = []

        def each(h, _):
            if user32.FindWindowExW(h, None, "SHELLDLL_DefView", None):
                holder.append(user32.FindWindowExW(None, h, "WorkerW", None))
            return True
        user32.EnumWindows(proto(each), 0)
        if holder and holder[0]:
            hwnd = holder[0]
        if not hwnd:
            # The 24H2 arrangement: a WorkerW inside Progman.
            hwnd = user32.FindWindowExW(progman, None, "WorkerW", None)
        return hwnd or 0

    def behind_icons(self, widget):
        p = self.procs.get(widget)
        if p is None or os.name != "nt":
            return False
        hwnd = 0
        for _ in range(50):                 # the window appears a moment after the process
            hwnd = self.window_of(p.pid)
            if hwnd:
                break
            time.sleep(0.1)
        target = self.workerw()
        if not hwnd or not target:
            print(f"plaintop: cannot put {widget} behind the icons (window {hwnd}, WorkerW {target})",
                  file=sys.stderr, flush=True)
            return False
        ctypes.windll.user32.SetParent(hwnd, target)
        return True

    def unparent(self, widget):
        p = self.procs.get(widget)
        if p is None or os.name != "nt":
            return False
        hwnd = self.window_of(p.pid)
        if hwnd:
            ctypes.windll.user32.SetParent(hwnd, None)
        return bool(hwnd)
