#!/usr/bin/env python3
"""Which holidays are days off — the generator, for plaincalendar.

The widget takes the holidays from Plasma's own calendar plugin ("holidaysevents", built on
KHolidays): 170 regions, the ones chosen in the shared file the digital clock uses too. The
plugin hands over every entry of a region's plan alike — a day off, a professional day, a
name day — with nothing to tell them apart. The plans do say it: each line is

    "Name"   public religious on december 25

and `public` marks a day off. This script reads every plan out of the KHolidays library and
writes package/contents/ui/HolidayKinds.js (committed, not built at install time): the names
that are a day off somewhere, and the names that are only name days. Run it from the
repository root after a KHolidays update and commit the file:

    python3 calendar/holidays.py

The plans live in the library as Qt resources (qrc:/org.kde.kholidays/plan2/holiday_<code>),
not as files, so they are read through a throwaway QML host that may read them
(QML_XHR_ALLOW_FILE_READ=1) — /usr/lib/qt6/bin/qml, or $QML. Standard library otherwise;
the output is sorted, so a second run changes nothing.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "package", "contents", "ui", "HolidayKinds.js")
QML = os.environ.get("QML", "/usr/lib/qt6/bin/qml")

DUMP = """import QtQuick
import org.kde.kholidays as KH
QtObject {
    property var m: KH.HolidayRegionsModel { id: mdl }
    Component.onCompleted: {
        for (let i = 0; i < mdl.rowCount(); ++i) {
            const code = mdl.data(mdl.index(i, 0), 257)
            const x = new XMLHttpRequest()
            x.open("GET", "qrc:/org.kde.kholidays/plan2/holiday_" + code, false)
            x.send()
            console.log("@@FILE " + code + "\\n" + x.responseText)
        }
        Qt.quit()
    }
}
"""
# "Name" types on … — the types before "on"; a few lines name a second, short form first.
LINE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s+((?:[a-z]+\s+)*?)on\b')


def plans():
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "dump.qml")
        with open(path, "w") as f:
            f.write(DUMP)
        env = dict(os.environ, QML_XHR_ALLOW_FILE_READ="1", QT_QPA_PLATFORM="offscreen",
                   QT_FORCE_STDERR_LOGGING="1", XDG_CONFIG_HOME=tmp)
        out = subprocess.run([QML, path], capture_output=True, text=True, env=env, timeout=120)
    text = out.stdout + out.stderr
    files = {}
    for chunk in text.split("@@FILE ")[1:]:
        code, _, body = chunk.partition("\n")
        files[code.strip()] = body
    return files


def main():
    files = plans()
    if len(files) < 50:
        sys.exit(f"  ✗ only {len(files)} plans read — is {QML} the Qt 6 qml host, and KHolidays installed?")
    public, nameday, other = set(), set(), set()
    for body in files.values():
        for line in body.splitlines():
            m = LINE.match(line)
            if not m:
                continue
            name = m.group(1).replace('\\"', '"')
            kinds = m.group(2).split()
            if "public" in kinds:
                public.add(name)
            elif kinds and set(kinds) <= {"nameday"}:
                nameday.add(name)
            else:
                other.add(name)
    nameday -= public | other
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(".pragma library\n")
        f.write("// Made by calendar/holidays.py from the KHolidays plans — do not edit by hand.\n")
        f.write("// PUBLIC: names that are a day off in some region; NAMEDAY: names that are only\n")
        f.write("// name days. The calendar plugin gives the names alone, as the plans spell them.\n")
        f.write("var PUBLIC = " + json.dumps(sorted(public), ensure_ascii=False) + "\n")
        f.write("var NAMEDAY = " + json.dumps(sorted(nameday), ensure_ascii=False) + "\n")
    print(f"  ✓ {len(files)} regions: {len(public)} days off, {len(nameday)} name days → {os.path.relpath(OUT)}")


if __name__ == "__main__":
    main()
