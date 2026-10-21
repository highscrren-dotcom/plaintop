"""Where the service's files are, in both layouts it runs from.

From the repository the service is win/service/*.py and everything else sits where git
keeps it: spectrum/relay.py, calendar/package/contents/code/notes.py, each widget's
package/contents/config/main.xml, the hosts in win/host/. Frozen by PyInstaller
(win/package.py) it is plaintop.exe with its modules in _internal/, and the packager lays
the rest out beside the exe: spectrum/relay.py, calendar/notes.py, service/config/<w>.xml,
service/sounds/, host/, qt/bin/qml.exe. The first run of that zip looked for
C:\\spectrum\\relay.py — the modules' __file__ is two levels deeper than in the tree — so
every path now comes from here, and PLAINTOP_ROOT names a root by hand for a stand.
"""
import os
import sys
from pathlib import Path

WIDGETS = ("monitor", "spectrum", "player", "weather", "calendar")


def frozen():
    return bool(getattr(sys, "frozen", False))


def root():
    env = os.environ.get("PLAINTOP_ROOT")
    if env:
        return Path(env).resolve()
    if frozen():
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[2]


def first(*candidates):
    for c in candidates:
        if c.exists():
            return c
    return candidates[0]


def host_dir():
    return first(root() / "win" / "host", root() / "host")


def relay_py():
    return root() / "spectrum" / "relay.py"


def notes_py():
    env = os.environ.get("PLAINTOP_NOTES")
    if env:
        return Path(env)
    return first(root() / "calendar" / "package" / "contents" / "code" / "notes.py",
                 root() / "calendar" / "notes.py")


def kcfg(widget):
    return first(root() / widget / "package" / "contents" / "config" / "main.xml",
                 root() / "service" / "config" / f"{widget}.xml",
                 Path(__file__).resolve().parent / "config" / f"{widget}.xml")


def sounds_dir():
    return first(root() / "calendar" / "package" / "contents" / "sounds",
                 root() / "service" / "sounds",
                 Path(__file__).resolve().parent / "sounds")


def qt_bin():
    """The qml tool beside a packaged service: <root>/qt/bin."""
    return root() / "qt" / "bin"
