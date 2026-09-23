#!/usr/bin/env python3
"""Refresh the translation templates and catalogs from the sources.

For developers and translators, not for the install: it needs gettext's xgettext,
msgmerge and msginit. The install only compiles what is committed here (build.py).

    python3 po/extract.py            # rebuild po/<domain>.pot, merge into every language
    python3 po/extract.py --init uk  # start a new language from the templates

Strings are taken from tracked files only: the QML copies install.sh drops into the
packages are gitignored, and extracting them would list every string twice. The block
names, hints and parameter names in schema/blocks.json are UI text too, but no call site
holds them as literals — they are added here with the contexts the UI looks them up by.
"""
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

PO = Path(__file__).resolve().parent
REPO = PO.parent
BUGS = "https://github.com/highscrren-dotcom/plaintop/issues"

KEYWORDS = ["-ki18n:1", "-ki18nc:1c,2", "-ki18np:1,2", "-ki18ncp:1c,2,3"]

DOMAINS = {
    "plasma_applet_org.s1dd1.plaintop": {
        "sources": ["monitor/shared", "monitor/window", "monitor/package/contents"],
        "python": ["monitor/window/setup.py"],
        "schema": True,
    },
    # player/shared is listed under two domains on purpose: the visualizer draws the
    # player's view inside its own package, where i18n() resolves to the visualizer's
    # domain — so its strings must exist in both catalogs.
    "plasma_applet_org.s1dd1.plainspectrum": {
        "sources": ["spectrum/shared", "spectrum/window", "spectrum/package/contents", "player/shared"],
        "python": ["spectrum/window/setup.py"],
        "schema": False,
    },
    "plasma_applet_org.s1dd1.plainplayer": {
        "sources": ["player/shared", "player/package/contents"],
        "schema": False,
    },
    "plasma_applet_org.s1dd1.plainweather": {
        "sources": ["weather/package/contents"],
        "schema": False,
    },
}

# Must match the contexts the editors pass when they translate vocabulary text.
SCHEMA_CONTEXT = {
    "name": "schema: block name",
    "hint": "schema: block hint",
    "param": "schema: parameter name",
}


def tracked(dirs):
    out = subprocess.run(["git", "ls-files", "--", *dirs], cwd=REPO, check=True,
                         capture_output=True, text=True).stdout.split()
    return [f for f in out if f.endswith((".qml", ".js"))]


def schema_calls():
    """blocks.json as i18nc() calls, so xgettext extracts it like any other source."""
    vocab = json.loads((REPO / "schema/blocks.json").read_text(encoding="utf-8"))
    calls = []
    for key, block in vocab.items():
        if key.startswith("_"):
            continue
        calls.append((SCHEMA_CONTEXT["name"], block["name"]))
        if block.get("hint"):
            calls.append((SCHEMA_CONTEXT["hint"], block["hint"]))
        for param in block.get("params", {}).values():
            calls.append((SCHEMA_CONTEXT["param"], param["name"]))
    return "".join(f"i18nc({json.dumps(c)}, {json.dumps(t, ensure_ascii=False)});\n"
                   for c, t in calls)


# setup.py marks its .desktop texts with N_(context, text); the bare -k drops Python's
# default keywords, so a throwaway `_` in a loop is never taken for a message.
PY_KEYWORDS = ["-k", "-kN_:1c,2"]


def xgettext(files, cwd, out, lang="JavaScript", keywords=KEYWORDS):
    subprocess.run(["xgettext", "-L", lang, "--from-code=UTF-8", *keywords,
                    "--package-name=plaintop", f"--msgid-bugs-address={BUGS}",
                    "-o", str(out), *files], cwd=cwd, check=True)


def kde_format(pot):
    """xgettext flags "%1d" as javascript-format, which it is not: ki18n's placeholders
    are %1…%99. Entries that have them get kde-format instead, so `msgfmt --check` in
    build.py rejects a translation that drops or invents one."""
    entries = pot.read_text(encoding="utf-8").split("\n\n")
    out = []
    for entry in entries:
        lines = [l for l in entry.split("\n") if not l.startswith("#,")]
        flags = [f.strip() for l in entry.split("\n") if l.startswith("#,")
                 for f in l[2:].split(",")]
        flags = [f for f in flags if f and not f.endswith("javascript-format")]
        text = "\n".join(l for l in lines if l.startswith(("msgid", '"')))
        if re.search(r"%\d", text):
            flags.append("kde-format")
        if flags:
            # Flags go after the comments and "#:" locations, before msgctxt/msgid.
            at = next(i for i, l in enumerate(lines) if not l.startswith("#"))
            lines.insert(at, "#, " + ", ".join(flags))
        out.append("\n".join(lines))
    pot.write_text("\n\n".join(out), encoding="utf-8")


def same_but_date(a, b):
    """True when two templates differ at most in POT-Creation-Date, which xgettext
    rewrites on every run — a diff of nothing but a timestamp is noise."""
    def strip(t):
        return [l for l in t.splitlines() if not l.startswith('"POT-Creation-Date:')]
    return strip(a) == strip(b)


def template(domain, spec):
    pot = PO / f"{domain}.pot"
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        parts = [tmp / "code.pot"]
        xgettext(tracked(spec["sources"]), REPO, parts[0])
        if spec.get("python"):
            parts.append(tmp / "python.pot")
            xgettext(spec["python"], REPO, parts[-1], "Python", PY_KEYWORDS)
        if spec["schema"]:
            # A path that reads as what it is in the template's "#:" location lines.
            src = tmp / "schema" / "blocks.json"
            src.parent.mkdir()
            src.write_text(schema_calls(), encoding="utf-8")
            parts.append(tmp / "schema.pot")
            xgettext(["schema/blocks.json"], tmp, parts[-1])
        fresh = tmp / "all.pot"
        subprocess.run(["msgcat", "--use-first", "-o", str(fresh), *map(str, parts)], check=True)
        kde_format(fresh)
        text = fresh.read_text(encoding="utf-8")
        if not pot.exists() or not same_but_date(pot.read_text(encoding="utf-8"), text):
            pot.write_text(text, encoding="utf-8")
    return pot


def main():
    init = sys.argv[2] if len(sys.argv) == 3 and sys.argv[1] == "--init" else None
    for domain, spec in DOMAINS.items():
        pot = template(domain, spec)
        print(f"  ✓ {pot.relative_to(REPO)}")
        if init:
            po = PO / init / f"{domain}.po"
            po.parent.mkdir(exist_ok=True)
            subprocess.run(["msginit", "--no-translator", "-l", init, "-i", str(pot),
                            "-o", str(po)], check=True)
        # A new domain starts with an empty catalog in every language the project already
        # has: the languages are the project's, not one widget's, and msgmerge below only
        # updates what exists.
        for lang in sorted(p.name for p in PO.iterdir() if p.is_dir() and any(p.glob("*.po"))):
            po = PO / lang / f"{domain}.po"
            if not po.exists():
                subprocess.run(["msginit", "--no-translator", "-l", lang, "-i", str(pot),
                                "-o", str(po)], check=True)
        for po in sorted(PO.glob(f"*/{domain}.po")):
            subprocess.run(["msgmerge", "--quiet", "--update", "--backup=none",
                            str(po), str(pot)], check=True)
            print(f"  ✓ {po.relative_to(REPO)}")


if __name__ == "__main__":
    main()
