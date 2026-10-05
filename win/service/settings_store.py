"""The settings of the five widgets, owned by the service.

Why the service and not the hosts: QML cannot write a file, and two writers on one file —
a settings window and a widget — is the mistake this project paid for once already
(decision 5). So the settings window posts here, the widget host polls here, and this
module is the only thing that touches the files.

The keys and the defaults are the plasmoids' own `config/main.xml` (kcfg): read at start,
so a key added to a widget's settings on Plasma exists here without a second list. On top
of them the window keys a plasmoid never had — where the window stands, which screen,
whether it is shown, whether it sits behind the desktop icons — and a few Windows
defaults where the Plasma default names a Linux program.

Storage: one ini file per widget, `%APPDATA%\\plaintop\\<widget>.ini` (or
`$XDG_CONFIG_HOME/plaintop` elsewhere), a `[General]` section with the same key names, so
a person may edit it; the file is re-read when its modification time changes.
"""
import configparser
import os
import threading
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import paths

WIDGETS = ("monitor", "spectrum", "player", "weather", "calendar")
KCFG = "{http://www.kde.org/standards/kcfg/1.0}"

# The window keys, with their types and defaults.
WINDOW_KEYS = {
    "shown": ("Bool", True),        # the tray's checkbox: whether the host runs
    "winX": ("Int", 60),
    "winY": ("Int", 60),
    "screen": ("Int", 0),
    "behindIcons": ("Bool", False),  # parented under the wallpaper's WorkerW (experimental)
    # Qt Quick's software backend: the window is then a layered window painted with
    # per-pixel alpha, and Windows passes the mouse through its transparent pixels — the
    # candidate for a partial click-through without C++ (docs/research/windows-widgets.ru.md).
    "softwareRender": ("Bool", False),
}

# Where the Plasma default names something Windows has not.
WINDOWS_DEFAULTS = {
    "monitor": {
        # The active lines run Linux commands (kill, systemctl, konsole): off until the
        # service translates them — win/PROTOCOL.md.
        "actions": False,
        "terminal": "wt",
        "editor": "notepad",
    },
    "spectrum": {"winX": 700, "winY": 120},
    "player": {"winX": 60, "winY": 1040},
    "weather": {"winX": 600, "winY": 60},
    # holidayRegions has no entry in main.xml: on Plasma the regions live in KHolidays'
    # own file; here they are a setting, "DE,DE-BY" (win/host/calendar/Holidays.qml).
    "calendar": {"winX": 1200, "winY": 60, "holidayRegions": ""},
}


def config_dir():
    if os.name == "nt":
        base = Path(os.environ.get("APPDATA") or (Path.home() / "AppData" / "Roaming"))
    else:
        base = Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))
    return base / "plaintop"


def kcfg_paths(repo_root):
    """Each widget's main.xml: in the repository, or copied beside the service by the
    packager as service/config/<widget>.xml (paths.py knows both layouts)."""
    out = {}
    for w in WIDGETS:
        for candidate in (Path(repo_root) / w / "package" / "contents" / "config" / "main.xml", paths.kcfg(w)):
            if candidate.is_file():
                out[w] = candidate
                break
    return out


def parse_kcfg(path):
    """{key: (type, default)} from a kcfg file: Bool, Int, Double, String; a missing
    <default> is the type's empty value."""
    root = ET.parse(path).getroot()
    out = {}
    for entry in root.iter(KCFG + "entry"):
        name, kind = entry.get("name"), entry.get("type", "String")
        d = entry.find(KCFG + "default")
        text = d.text if (d is not None and d.text is not None) else ""
        out[name] = (kind, convert(kind, text))
    return out


def convert(kind, text):
    """A stored string as the kcfg type says; a value that does not parse keeps the
    type's zero rather than raising, as KConfig does."""
    if isinstance(text, bool) or text is None:
        return text
    s = str(text).strip()
    if kind == "Bool":
        if isinstance(text, (int, float)):
            return bool(text)
        return s.lower() in ("true", "1", "yes", "on")
    if kind == "Int":
        try:
            return int(float(s))
        except ValueError:
            return 0
    if kind == "Double":
        try:
            return float(s)
        except ValueError:
            return 0.0
    return str(text)


def to_text(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


class Store:
    def __init__(self, repo_root=None, directory=None):
        self.repo_root = Path(repo_root) if repo_root else paths.root()
        self.dir = Path(directory) if directory else config_dir()
        self.lock = threading.Lock()
        self.schema = {}                  # widget → {key: (type, default)}
        self.values = {}                  # widget → {key: value}
        self.stamps = {w: 1 for w in WIDGETS}
        self.mtimes = {}
        for w, path in kcfg_paths(self.repo_root).items():
            self.schema[w] = parse_kcfg(path)
        for w in WIDGETS:
            schema = self.schema.setdefault(w, {})
            for k, (kind, default) in WINDOW_KEYS.items():
                schema[k] = (kind, default)
            for k, v in WINDOWS_DEFAULTS.get(w, {}).items():
                kind = schema[k][0] if k in schema else ("Bool" if isinstance(v, bool) else "Int" if isinstance(v, int) else "String")
                schema[k] = (kind, v)
            self.values[w] = {k: d for k, (kind, d) in schema.items()}
            self._read(w)

    def widgets(self):
        return [w for w in WIDGETS if w in self.schema]

    def path(self, widget):
        return self.dir / f"{widget}.ini"

    def _read(self, widget):
        p = self.path(widget)
        if not p.is_file():
            self.mtimes[widget] = None
            return False
        try:
            mtime = p.stat().st_mtime
            cp = configparser.ConfigParser(interpolation=None)
            cp.optionxform = str          # keys are case-sensitive, as in main.xml
            cp.read(p, encoding="utf-8")
        except (OSError, configparser.Error):
            return False
        if cp.has_section("General"):
            schema = self.schema[widget]
            for k, text in cp.items("General"):
                kind = schema[k][0] if k in schema else "String"
                self.values[widget][k] = convert(kind, text)
        self.mtimes[widget] = mtime
        return True

    def _write(self, widget):
        self.dir.mkdir(parents=True, exist_ok=True)
        cp = configparser.ConfigParser(interpolation=None)
        cp.optionxform = str
        cp.add_section("General")
        for k, v in self.values[widget].items():
            cp.set("General", k, to_text(v))
        tmp = self.path(widget).with_suffix(".ini.tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            cp.write(f)
        os.replace(tmp, self.path(widget))
        self.mtimes[widget] = self.path(widget).stat().st_mtime

    def _refresh(self, widget):
        """Pick up a file edited by hand: a changed modification time means re-read."""
        p = self.path(widget)
        try:
            mtime = p.stat().st_mtime if p.is_file() else None
        except OSError:
            return
        if mtime != self.mtimes.get(widget):
            if self._read(widget):
                self.stamps[widget] += 1

    def get(self, widget):
        if widget not in self.schema:
            raise KeyError(widget)
        with self.lock:
            self._refresh(widget)
            return self.stamps[widget], dict(self.values[widget])

    def update(self, widget, mapping):
        if widget not in self.schema:
            raise KeyError(widget)
        with self.lock:
            self._refresh(widget)
            changed = False
            for k, v in (mapping or {}).items():
                kind = self.schema[widget][k][0] if k in self.schema[widget] else None
                value = convert(kind, v) if kind else v
                if self.values[widget].get(k) != value:
                    self.values[widget][k] = value
                    changed = True
            if changed:
                self.stamps[widget] += 1
                self._write(widget)
            return self.stamps[widget]

    def types(self, widget):
        return {k: kind for k, (kind, _) in self.schema[widget].items()}


if __name__ == "__main__":
    import json
    import sys
    s = Store()
    for w in s.widgets():
        stamp, v = s.get(w)
        print(w, stamp, len(v), "keys; ini:", s.path(w))
    if len(sys.argv) > 1:
        print(json.dumps(s.get(sys.argv[1])[1], ensure_ascii=False, indent=1))
