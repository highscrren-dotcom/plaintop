#!/usr/bin/env python3
"""Colour palettes for the five widgets: put one on the desktop, or keep the current one.

A palette is palettes/<name>.json: each widget's plugin id mapped to its colour keys, the
same keys its settings dialog writes. "stock" is not a file: it is read from the widgets'
main.xml, so it cannot drift from the defaults.

    python3 palettes/palette.py apply NAME   # write into every instance on every desktop
    python3 palettes/palette.py save NAME    # the desktop's current colours → palettes/NAME.json
    python3 palettes/palette.py list
    python3 palettes/palette.py check    # the keys against main.xml, every file loads (CI)

install.sh wraps them as --palette NAME and --palette-save NAME. With two instances of one
widget, save keeps the first one's colours.
"""
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent

# The keys a palette may set. Checked against main.xml before anything is written:
# writeConfig takes any name, and a misspelt key would sit in the config doing nothing.
KEYS = {
    "org.s1dd1.plaintop": ("monitor/package", ["colorFg", "colorAccent", "colorDim", "colorValue", "colorPaper"]),
    "org.s1dd1.plainplayer": ("player/package", ["colorFg", "colorAccent", "colorDim"]),
    "org.s1dd1.plainweather": ("weather/package", ["colorFg", "colorAccent", "colorDim"]),
    "org.s1dd1.plainspectrum": ("spectrum/package", ["color", "colorHigh", "opacityPercent",
                                                     "playerColorFg", "playerColorAccent",
                                                     "playerColorDim"]),
    "org.s1dd1.plaincalendar": ("calendar/package", ["colorFg", "colorAccent", "colorDim", "colorToday",
                                                       "colorNote", "colorPaper", "colorHoliday"]),
}
COLOUR = re.compile(r"^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$")
KCFG = "{http://www.kde.org/standards/kcfg/1.0}"


def fail(message):
    print(f"  ✗ {message}")
    sys.exit(1)


def defaults():
    """Every palette key of every widget with its type and default, from main.xml."""
    out = {}
    for plugin, (package, keys) in KEYS.items():
        root = ET.parse(REPO / package / "contents/config/main.xml").getroot()
        entries = {e.get("name"): e for e in root.iter(KCFG + "entry")}
        out[plugin] = {}
        for key in keys:
            if key not in entries:
                fail(f"{plugin}: no key {key} in its main.xml — the list in palette.py is stale")
            e = entries[key]
            text = e.findtext(KCFG + "default") or ""
            out[plugin][key] = int(text) if e.get("type") == "Int" else text
    return out


def load(name, stock):
    if name == "stock":
        return stock
    path = HERE / f"{name}.json"
    if not path.is_file():
        fail(f"no palette {path.relative_to(REPO)}; there are: {', '.join(names())}")
    try:
        palette = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        fail(f"{path.relative_to(REPO)}: {e}")
    for plugin, values in palette.items():
        if plugin not in stock:
            fail(f"{name}: unknown widget {plugin}")
        for key, value in values.items():
            if key not in stock[plugin]:
                fail(f"{name}: {plugin} has no palette key {key}")
            if isinstance(stock[plugin][key], int):
                if not isinstance(value, int) or not 0 <= value <= 100:
                    fail(f"{name}: {plugin} {key} must be a number 0–100, not {value!r}")
            elif not (COLOUR.match(str(value)) or (value == "" and stock[plugin][key] == "")):
                fail(f"{name}: {plugin} {key} is not a colour: {value!r}")
    return palette


def names():
    return ["stock"] + sorted(p.stem for p in HERE.glob("*.json"))


def shell(script):
    try:
        return subprocess.run(["qdbus6", "org.kde.plasmashell", "/PlasmaShell",
                               "org.kde.PlasmaShell.evaluateScript", script],
                              capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as e:
        fail(f"plasmashell did not take the script: {e}")


def apply(name):
    palette = load(name, defaults())
    done = shell("""
var P = %s;
var out = [], ds = desktops();
for (var i = 0; i < ds.length; i++) {
    var ws = ds[i].widgets();
    for (var j = 0; j < ws.length; j++) {
        var w = ws[j], values = P[w.type];
        if (!values) continue;
        w.currentConfigGroup = ["General"];
        for (var k in values) w.writeConfig(k, values[k]);
        w.reloadConfig();
        out.push(w.type);
    }
}
print(out.join(" "));""" % json.dumps(palette))
    if not done:
        fail("none of the widgets is on the desktop")
    print(f"  ✓ palette {name} — {done.replace('org.s1dd1.', '')}")


def save(name):
    if name == "stock" or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name):
        fail("a palette name is lowercase letters, digits and hyphens, and not \"stock\"")
    out = shell("""
var D = %s;
var out = {}, ds = desktops();
for (var i = 0; i < ds.length; i++) {
    var ws = ds[i].widgets();
    for (var j = 0; j < ws.length; j++) {
        var w = ws[j], keys = D[w.type];
        if (!keys || out[w.type]) continue;
        w.currentConfigGroup = ["General"];
        var v = {};
        for (var k in keys) v[k] = w.readConfig(k, keys[k]);
        out[w.type] = v;
    }
}
print(JSON.stringify(out));""" % json.dumps(defaults()))
    palette = json.loads(out or "{}")
    if not palette:
        fail("none of the widgets is on the desktop")
    ordered = {p: palette[p] for p in KEYS if p in palette}
    path = HERE / f"{name}.json"
    path.write_text(json.dumps(ordered, indent=2) + "\n")
    print(f"  ✓ {path.relative_to(REPO)} — {', '.join(p.replace('org.s1dd1.', '') for p in ordered)}")


if __name__ == "__main__":
    command, arg = (sys.argv[1:] + ["", ""])[:2]
    if command == "list":
        print("  " + "  ".join(names()))
    elif command in ("apply", "save") and arg:
        {"apply": apply, "save": save}[command](arg)
    elif command == "check":
        # For the CI: every key of KEYS exists in its main.xml, every palette file loads
        # against the stock one — the same checks apply makes, with nothing written.
        stock = defaults()
        for name in names():
            load(name, stock)
        print(f"  ✓ palette keys match main.xml; {len(names())} palettes load: {', '.join(names())}")
    else:
        fail(f"usage: palette.py apply NAME | save NAME | list | check; palettes: {', '.join(names())}")
