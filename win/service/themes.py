"""The palettes, applied on Windows: palettes/<name>.json (the same files install.sh
--palette writes into the plasmoids) → the widgets' ini through the settings store.

A palette maps each widget's plugin id to the colour keys of its main.xml, with an
optional "about" block (title, note). list_themes() reads them all for the menus;
apply(store, name) writes one into every widget's settings — the hosts pick the change
up on their next settings poll, within a second. "stock" is the defaults of the schema,
which is main.xml itself, so it cannot drift. Every key is checked against the store's
schema before anything is written, as palette.py does on Plasma: a misspelt key would sit
in the ini doing nothing.
"""
import json
import re
from pathlib import Path

import paths

PLUGINS = {"org.s1dd1.plaintop": "monitor", "org.s1dd1.plainplayer": "player",
           "org.s1dd1.plainweather": "weather", "org.s1dd1.plainspectrum": "spectrum",
           "org.s1dd1.plaincalendar": "calendar"}
COLOUR_KEYS = {"monitor": ["colorFg", "colorAccent", "colorDim", "colorValue", "colorPaper"],
               "player": ["colorFg", "colorAccent", "colorDim"],
               "weather": ["colorFg", "colorAccent", "colorDim"],
               "spectrum": ["color", "colorHigh", "opacityPercent", "playerColorFg", "playerColorAccent", "playerColorDim"],
               "calendar": ["colorFg", "colorAccent", "colorDim", "colorToday", "colorNote", "colorPaper", "colorHoliday"]}
COLOUR = re.compile(r"^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$")
NAME = re.compile(r"^[a-z0-9][a-z0-9-]*$")
ABOUT = "about"


class BadPalette(ValueError):
    pass


def directory():
    return paths.first(paths.root() / "palettes", Path(__file__).resolve().parent / "palettes")


def names():
    return sorted(p.stem for p in directory().glob("*.json") if NAME.match(p.stem))


def title_of(name, about):
    t = (about or {}).get("title") if isinstance(about, dict) else None
    return str(t) if t else name.replace("-", " ").capitalize()


def load(name, schema):
    """{widget: {key: value}} of a palette, checked against the store's schema
    ({widget: {key: (type, default)}}); "stock" is the schema's defaults."""
    if name == "stock":
        return {w: {k: schema[w][k][1] for k in keys if k in schema.get(w, {})} for w, keys in COLOUR_KEYS.items()}, None
    if not NAME.match(str(name)):
        raise BadPalette(f"not a palette name: {name!r}")
    path = directory() / f"{name}.json"
    if not path.is_file():
        raise BadPalette(f"no palette {name}")
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise BadPalette(f"{path.name}: {e}") from None
    if not isinstance(raw, dict):
        raise BadPalette(f"{path.name}: not an object")
    about = raw.get(ABOUT)
    out = {}
    for plugin, values in raw.items():
        if plugin == ABOUT:
            continue
        widget = PLUGINS.get(plugin)
        if widget is None:
            raise BadPalette(f"{name}: unknown widget {plugin}")
        if not isinstance(values, dict):
            raise BadPalette(f"{name}: {plugin} is not an object")
        out[widget] = {}
        for key, value in values.items():
            if key not in COLOUR_KEYS[widget] or key not in schema.get(widget, {}):
                raise BadPalette(f"{name}: {widget} has no palette key {key}")
            kind, default = schema[widget][key]
            if kind == "Int":
                if not isinstance(value, int) or not 0 <= value <= 100:
                    raise BadPalette(f"{name}: {widget} {key} must be a number 0–100")
            elif not (COLOUR.match(str(value)) or (value == "" and default == "")):
                raise BadPalette(f"{name}: {widget} {key} is not a colour: {value!r}")
            out[widget][key] = value
    return out, about


def swatch(values):
    """Four colours for a menu: the monitor's fg, accent, dim, value — the common ones."""
    m = values.get("monitor") or values.get("player") or {}
    return {k: m.get(key, "") for k, key in (("fg", "colorFg"), ("accent", "colorAccent"),
                                            ("dim", "colorDim"), ("value", "colorValue"))}


def list_themes(schema):
    """[{"name", "title", "note", "swatch"}], stock first, then the files by name; a file
    that does not load is listed with its error instead of a swatch."""
    out = []
    for name in ["stock"] + names():
        try:
            values, about = load(name, schema)
        except BadPalette as e:
            out.append({"name": name, "title": title_of(name, None), "note": "", "error": str(e)})
            continue
        out.append({"name": name, "title": "Stock" if name == "stock" else title_of(name, about),
                    "note": str((about or {}).get("note", "")) if isinstance(about, dict) else "",
                    "swatch": swatch(values)})
    return out


def current(store):
    """The palette whose every key the settings carry now, or ""."""
    schema = {w: store.schema[w] for w in store.widgets()}
    have = {w: store.get(w)[1] for w in store.widgets()}
    for name in ["stock"] + names():
        try:
            values, _ = load(name, schema)
        except BadPalette:
            continue
        if all(have.get(w, {}).get(k) == v for w, kv in values.items() for k, v in kv.items()):
            return name
    return ""


def apply(store, name):
    """The palette into every widget's settings; {widget: stamp} of what was written."""
    schema = {w: store.schema[w] for w in store.widgets()}
    values, _ = load(name, schema)
    return {w: store.update(w, kv) for w, kv in values.items() if kv}
