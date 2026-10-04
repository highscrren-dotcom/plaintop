#!/usr/bin/env python3
"""Stand for four modules of the Windows service, win/service/: the player's mapping of
SMTC sessions to the fields PlayerView.qml reads (through a fake backend — WinRT itself
runs only on Windows), the bridge that runs notes.py inside the process, the holidays from
the `holidays` package, and the time zones.

    python3 tests/win_media.py

No WinRT, no HTTP, no network: the modules are imported by path and called. Everything
notes.py writes goes to a temporary directory through XDG_CONFIG_HOME, XDG_CACHE_HOME and
XDG_DATA_HOME, so the real accounts and notes are never touched — on Windows too, where
the XDG variables win over %APPDATA%. Needs the `holidays` package, and on Windows `tzdata`.
"""
import base64
import contextlib
import datetime as dt
import importlib.util
import io
import json
import os
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TMP = tempfile.mkdtemp(prefix="plaintop-win-test-")
for var in ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME"):
    os.environ[var] = TMP

# A Windows console, or a pipe on a Windows runner, is not UTF-8 by default and the ✓ would
# be the first thing to fail.
for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

sys.dont_write_bytecode = True


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "win" / "service" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


player = load("player_win")
bridge = load("notes_bridge")
holidays_win = load("holidays_win")
timezones = load("timezones")

passed = 0


def ok(cond, what):
    global passed
    if not cond:
        print("  ✗ " + what)
        sys.exit(1)
    passed += 1


# ── The player ────────────────────────────────────────────────────────────────
class Fake:
    """A backend as player_win expects one: the sessions as the SMTC would hand them over,
    the current one by id, and a record of the commands it was given."""
    name = "fake"

    def __init__(self, sessions, current=None):
        self.list = sessions
        self.current = current
        self.calls = []
        self.reads = 0

    def sessions(self):
        self.reads += 1
        return [dict(s) for s in self.list]

    def current_id(self):
        return self.current

    def command(self, session_id, name):
        self.calls.append((session_id, name))
        return any(s["id"] == session_id for s in self.list)


NOW = dt.datetime(2026, 10, 4, 12, 0, 0, tzinfo=dt.timezone.utc)
SPOTIFY = "SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify"


def session(sid, status, position=42, length=213, rate=1.0, updated=NOW - dt.timedelta(seconds=10), **flags):
    s = {"id": sid, "title": "Track", "artist": "Artist", "album": "Album", "status": status,
         "rate": rate, "position": dt.timedelta(seconds=position), "start": dt.timedelta(0),
         "end": dt.timedelta(seconds=length), "updated": updated,
         "next": True, "previous": True, "play": False, "pause": True}
    s.update(flags)
    return s


def test_player():
    player.clock = lambda: NOW
    # No backend at all: the Linux answer, and what Windows says without winsdk.
    player.set_backend(None)
    if player.control_module() is None:
        ok(player.snapshot() == {"players": [], "current": -1, "backend": "none"}, "no backend: no players, current −1: " + repr(player.snapshot()))
        ok(player.command(SPOTIFY, "Next") is False, "no backend: a command is refused")

    fake = Fake([session(SPOTIFY, 4), session("chrome.exe", 5, position=100, length=0, next=False)], current="chrome.exe")
    player.set_backend(fake)
    snap = player.snapshot()
    ok(snap["backend"] == "fake" and len(snap["players"]) == 2, "two sessions through the fake: " + repr(snap))
    ok(set(snap["players"][0]) == {"id", "identity", "desktopEntry", "track", "artist", "album", "length", "position",
                                   "rate", "playbackStatus", "canGoNext", "canGoPrevious", "canPlay", "canPause"},
       "exactly the /player fields: " + repr(sorted(snap["players"][0])))
    sp, ch = snap["players"]
    ok(sp["id"] == SPOTIFY and sp["identity"] == "Spotify" and sp["desktopEntry"] == SPOTIFY.lower(), "a packaged AUMID: the entry point is the name: " + repr(sp))
    ok(ch["id"] == "chrome.exe" and ch["identity"] == "chrome" and ch["desktopEntry"] == "chrome.exe", "an executable's AUMID: the name without .exe: " + repr(ch))
    ok(sp["track"] == "Track" and sp["artist"] == "Artist" and sp["album"] == "Album", "title, artist and album travel as track, artist, album")
    ok(sp["playbackStatus"] == 3 and ch["playbackStatus"] == 2, "PLAYING → 3, PAUSED → 2")
    ok(sp["length"] == 213000000, "the length in microseconds: " + repr(sp["length"]))
    # 42 s reported ten seconds ago at rate 1: 52 s now. Paused: as reported, and no length.
    ok(sp["position"] == 52000000, "a playing position is counted on from last_updated_time: " + repr(sp["position"]))
    ok(ch["position"] == 100000000 and ch["length"] == 0, "a paused one stays where it was reported; no end time is length 0: " + repr(ch))
    ok(sp["rate"] == 1.0 and sp["canGoNext"] and sp["canGoPrevious"] and not sp["canPlay"] and sp["canPause"], "the flags as given")
    ok(not ch["canGoNext"], "a flag the session denies")
    ok(snap["current"] == 1, "current is the index of the manager's current session: " + repr(snap["current"]))

    # Every status, the rate, the clamp, the odd timestamps.
    rows = [session("a.exe", 3), session("b.exe", 0), session("c.exe", 1), session("d.exe", 2)]
    fake = Fake(rows, current="nobody.exe")
    player.set_backend(fake)
    snap = player.snapshot()
    ok([p["playbackStatus"] for p in snap["players"]] == [1, 1, 1, 0], "STOPPED, CLOSED, OPENED → 1, CHANGING → 0: " + repr([p["playbackStatus"] for p in snap["players"]]))
    ok(snap["current"] == -1, "a current id no session has: −1")
    fast = session("fast.exe", 4, rate=2.0)
    clamp = session("clamp.exe", 4, position=205, length=213)
    none_rate = session("norate.exe", 4, rate=None, updated=None)
    stale = session("stale.exe", 4, updated=dt.datetime(1601, 1, 1, tzinfo=dt.timezone.utc))
    naive = session("naive.exe", 4, updated=(NOW - dt.timedelta(seconds=5)).replace(tzinfo=None))
    offset = session("offset.exe", 5, position=50, start=dt.timedelta(seconds=20), length=120)
    player.set_backend(Fake([fast, clamp, none_rate, stale, naive, offset]))
    ps = {p["id"]: p for p in player.snapshot()["players"]}
    ok(ps["fast.exe"]["position"] == 62000000 and ps["fast.exe"]["rate"] == 2.0, "the rate scales the extrapolation: " + repr(ps["fast.exe"]["position"]))
    ok(ps["clamp.exe"]["position"] == 213000000, "never past the end: " + repr(ps["clamp.exe"]["position"]))
    ok(ps["norate.exe"]["rate"] == 1.0 and ps["norate.exe"]["position"] == 42000000, "no rate is 1.0; no timestamp, no extrapolation: " + repr(ps["norate.exe"]))
    ok(ps["stale.exe"]["position"] == 42000000, "a 1601 timestamp (never updated) is not extrapolated from: " + repr(ps["stale.exe"]["position"]))
    ok(ps["naive.exe"]["position"] == 47000000, "a naive timestamp is taken as UTC: " + repr(ps["naive.exe"]["position"]))
    ok(ps["offset.exe"]["position"] == 30000000 and ps["offset.exe"]["length"] == 100000000, "position and length are relative to start_time: " + repr(ps["offset.exe"]))

    # Identity from more AUMID shapes.
    ok(player.identity("Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic") == "ZuneMusic", "a dotted entry point: its last part")
    ok(player.identity("Publisher.Player_abc123!App") == "Player", "the generic App entry: named after the package")
    ok(player.identity("C:\\Program Files\\VLC\\vlc.exe") == "vlc", "a path: the executable")
    ok(player.identity("org.videolan.VLC") == "VLC", "a reverse-DNS name: its last part")
    ok(player.identity("Spotify.exe") == "Spotify" and player.identity("") == "", "the plain executable, and nothing")

    # The cache: one reading serves REFRESH seconds; a command, or the time, forces the next.
    fake = Fake([session("a.exe", 4)])
    player.set_backend(fake)
    player.snapshot()
    player.snapshot()
    ok(fake.reads == 1, "two snapshots within 500 ms read the backend once: " + repr(fake.reads))
    ok(player.command("a.exe", "Next") is True and fake.calls == [("a.exe", "Next")], "a command reaches the session and answers True: " + repr(fake.calls))
    player.snapshot()
    ok(fake.reads == 2, "after a command the next snapshot reads anew: " + repr(fake.reads))
    time.sleep(player.REFRESH + 0.1)
    player.snapshot()
    ok(fake.reads == 3, "after REFRESH the next snapshot reads anew: " + repr(fake.reads))
    ok(player.command("nobody.exe", "PlayPause") is False and fake.calls[-1] == ("nobody.exe", "PlayPause"), "a command for a session nobody has: the backend says False")
    seen = len(fake.calls)
    ok(player.command("a.exe", "Stop") is False and len(fake.calls) == seen, "a command MPRIS has but the protocol does not: refused before the backend")
    ok(player.command("a.exe", "Previous") and player.command("a.exe", "PlayPause") and player.command("a.exe", "Position"), "the four commands dispatch")
    ok([c[1] for c in fake.calls if c[0] == "a.exe"] == ["Next", "Previous", "PlayPause", "Position"], "in order: " + repr(fake.calls))

    class Broken:
        def sessions(self):
            raise RuntimeError("the SMTC went away")

        def current_id(self):
            return None

        def command(self, *a):
            raise RuntimeError("no")

    player.set_backend(Broken())
    with contextlib.redirect_stderr(io.StringIO()) as err:
        snap = player.snapshot()
        taken = player.command("x", "Next")
    ok(snap["players"] == [] and snap["current"] == -1 and taken is False and "SMTC went away" in err.getvalue(), "a failing backend: empty, False, a line on stderr")
    player.set_backend(None)
    print("  ✓ player_win: the SMTC sessions as the fields the view reads")


# ── The notes bridge ──────────────────────────────────────────────────────────
def test_notes_bridge():
    ok(bridge.path() == ROOT / "calendar" / "package" / "contents" / "code" / "notes.py", "the script is found from the repository: " + str(bridge.path()))
    os.environ["PLAINTOP_NOTES"] = str(Path(TMP) / "elsewhere" / "notes.py")
    ok(bridge.path() == Path(TMP) / "elsewhere" / "notes.py", "PLAINTOP_NOTES names a packaged copy")
    del os.environ["PLAINTOP_NOTES"]

    text, code = bridge.run(["dump", "--upcoming", "2"])
    ok(code == 0 and isinstance(text, str), "dump: exit 0 with text: " + repr((code, text[:60])))
    doc = json.loads(text)
    ok("days" in doc and "upcoming" in doc and isinstance(doc["days"], dict), "…the JSON document with days and upcoming: " + repr(sorted(doc)))
    ok(bridge._notes is not None and bridge.load() is bridge._notes, "the script is loaded once")
    ok(str(bridge._notes.CONFIG_DIR).startswith(TMP) and str(bridge._notes.LOCAL_DIR).startswith(TMP), "XDG_* won: everything under the temporary directory: " + str(bridge._notes.LOCAL_DIR))

    day = (dt.date.today() + dt.timedelta(days=3)).isoformat()
    note = "Купить хлеб\nи молоко"
    text, code = bridge.run(["set", "local", day, base64.b64encode(note.encode("utf-8")).decode("ascii")])
    ok(code == 0, "set: exit 0: " + text[:200])
    text, code = bridge.run(["dump", "--from", day, "--to", day])
    doc = json.loads(text)
    mine = [e for e in doc["days"].get(day, []) if e.get("summary") == "Купить хлеб"]
    ok(len(mine) == 1 and mine[0]["own"], "…and dump shows the note, text decoded from base64: " + repr(doc["days"].get(day)))
    ok((Path(TMP) / "plaincalendar" / "notes").is_dir() and any((Path(TMP) / "plaincalendar" / "notes").glob("*.ics")), "the vdir has the .ics file")
    bridge.run(["delete", "local", day])

    # Argparse's exit and the script's own error line both come back as codes, not raises.
    with contextlib.redirect_stderr(io.StringIO()):
        text, code = bridge.run(["no-such-command"])
    ok(code == 2 and text == "", "a bad command: argparse's exit code 2, nothing on stdout")
    text, code = bridge.run(["set", "local", "not-a-date", "eA=="])
    ok(code == 1 and json.loads(text)["ok"] is False, "a bad date: the script's own error document and exit 1: " + text.strip())
    ok(sys.stdout is not None and not isinstance(sys.stdout, io.StringIO), "stdout is given back after every call")

    # Two threads at once: the lock makes each capture its own output.
    results = []

    def worker():
        for _ in range(5):
            results.append(bridge.run(["dump", "--upcoming", "2"]))

    threads = [threading.Thread(target=worker) for _ in range(2)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    docs = []
    for text, code in results:
        ok(code == 0, "a concurrent call exits 0")
        docs.append(json.loads(text))
    ok(len(docs) == 10 and all("days" in d for d in docs), "ten concurrent calls, ten whole documents")
    print("  ✓ notes_bridge: notes.py in the process, one call at a time")


# ── Holidays ──────────────────────────────────────────────────────────────────
def test_holidays():
    ok(holidays_win.holidays is not None, "the holidays package is installed (pip install holidays)")
    doc = holidays_win.month(["DE-BY", "RU", "XX", "DE-ZZ"], 2026, 10, "de")
    ok(set(doc) == {"days", "unknown"}, "the /holidays shape: " + repr(sorted(doc)))
    ok(doc["unknown"] == ["XX", "DE-ZZ"], "unknown codes are listed, a country's and a subdivision's: " + repr(doc["unknown"]))
    unity = doc["days"].get("2026-10-03", [])
    ok({"title": "Tag der Deutschen Einheit", "public": True} in unity, "DE-BY, October 2026: the 3rd is Tag der Deutschen Einheit, a day off: " + repr(unity))
    ok(all(k.startswith("2026-10-") for k in doc["days"]), "only the month's days: " + repr(sorted(doc["days"])))
    ok(all(isinstance(e["public"], bool) and e["title"] for day in doc["days"].values() for e in day), "every entry has a title and a boolean public")
    titles = [e["title"] for day in doc["days"].values() for e in day]
    ok(len(titles) == len({(k, e["title"]) for k, day in doc["days"].items() for e in day}), "a title once per day")

    doc = holidays_win.month(["RU"], 2026, 11, "ru")
    ok(doc["days"].get("2026-11-04") == [{"title": "День народного единства", "public": True}], "RU, November 2026: the 4th is a day off, named in Russian: " + repr(doc["days"].get("2026-11-04")))
    ok(doc["unknown"] == [], "nothing unknown")
    doc = holidays_win.month(["RU"], 2026, 11, "en")
    ok(doc["days"].get("2026-11-04") == [{"title": "Unity Day", "public": True}], "…and in English when asked: " + repr(doc["days"].get("2026-11-04")))
    doc = holidays_win.month(["RU"], 2026, 11, "xx")
    ok(doc["days"].get("2026-11-04", [{}])[0].get("title") == "День народного единства", "a language the country lacks: its own, not the environment's")

    # The other categories: Bavaria's school holidays are not days off; Allerheiligen is.
    doc = holidays_win.month(["DE-BY"], 2026, 11, "de")
    ok({"title": "Allerheiligen", "public": True} in doc["days"].get("2026-11-01", []), "Allerheiligen on the 1st, a day off in Bavaria: " + repr(doc["days"].get("2026-11-01")))
    ok({"title": "Herbstferien", "public": False} in doc["days"].get("2026-11-03", []), "Herbstferien on the 3rd, not a day off: " + repr(doc["days"].get("2026-11-03")))
    doc = holidays_win.month(["DE"], 2026, 11, "de")
    ok("2026-11-01" not in doc["days"] or {"title": "Allerheiligen", "public": True} not in doc["days"]["2026-11-01"], "without the subdivision Allerheiligen is no day off")
    doc = holidays_win.month(["US"], 2026, 11, "en")
    nov = doc["days"]
    ok(any(e["title"] == "Thanksgiving Day" and e["public"] for e in nov.get("2026-11-26", [])), "US: Thanksgiving on the 26th: " + repr(nov.get("2026-11-26")))
    oct_ = holidays_win.month(["US"], 2026, 10, "en")["days"]
    ok({"title": "Halloween", "public": False} in oct_.get("2026-10-31", []) and all(e["public"] for day in nov.values() for e in day),
       "US: Halloween is an observance, public false; November has days off only: " + repr(oct_.get("2026-10-31")))
    both = holidays_win.month(["DE-BY", "DE"], 2026, 10, "de")["days"]["2026-10-03"]
    ok(both == [{"title": "Tag der Deutschen Einheit", "public": True}], "two regions naming the same day: one entry")
    ok(holidays_win.month([], 2026, 10, "de") == {"days": {}, "unknown": []}, "no regions: nothing")
    ok(holidays_win.month(["de-by", " RU "], 2026, 10, "de")["unknown"] == [], "codes are case- and space-insensitive")

    regions = holidays_win.regions("de")
    ok(len(regions) >= 200, f"{len(regions)} countries listed")
    de = next(r for r in regions if r["code"] == "DE")
    ok(set(de) == {"code", "name", "subdivisions", "languages"} and "BY" in de["subdivisions"] and "de" in de["languages"], "DE with its Länder and languages: " + repr(de)[:160])
    ok(de["name"] in ("Germany", "Deutschland"), "a country name, English unless Babel translates it: " + de["name"])
    us = next(r for r in regions if r["code"] == "US")
    ok(us["name"] in ("United States", "Vereinigte Staaten") and "CA" in us["subdivisions"], "United States with its states")
    ok(all(r["code"] == r["code"].upper() and len(r["code"]) == 2 for r in regions), "ISO alpha-2 codes, no aliases")

    # The comparison tool: a known plan maps to a code and reports counts.
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        matched, total = holidays_win.compare(["ru_ru"], 2026)
    ok(total >= 8 and matched >= 8, f"ru_ru: {matched} of {total} day-off names match HolidayKinds.js")
    ok(holidays_win.plan_to_region("us_en-us") == ("US", "", "en_US") and holidays_win.plan_to_region("holiday_de-by_de") == ("DE", "BY", "de"), "plan names map to codes and languages")
    print("  ✓ holidays_win: the package's days off and observances as the calendar's days")


# ── Time zones ────────────────────────────────────────────────────────────────
def test_timezones():
    berlin = timezones.info("Europe/Berlin")
    ok(set(berlin) == {"zone", "offset", "city"}, "the /time shape: " + repr(berlin))
    ok(berlin["zone"] == "Europe/Berlin" and berlin["offset"] in (3600, 7200) and berlin["city"] == "Berlin",
       "Europe/Berlin: +1 or +2 hours, city Berlin (no tzdata? pip install tzdata): " + repr(berlin))
    yek = timezones.info("Asia/Yekaterinburg")
    ok(yek["offset"] == 18000 and yek["city"] == "Yekaterinburg", "Asia/Yekaterinburg: +5 hours, the city: " + repr(yek))
    ba = timezones.info("America/Argentina/Buenos_Aires")
    ok(ba["city"] == "Buenos Aires" and ba["offset"] == -10800, "the last part, underscores as spaces: " + repr(ba))
    unknown = timezones.info("Nowhere/Town")
    ok(unknown["zone"] == "Nowhere/Town" and unknown["offset"] == timezones.local_offset() and unknown["city"] == "", "an unknown zone: the machine's offset, no city: " + repr(unknown))
    ok(timezones.info("../etc/passwd")["city"] == "" and timezones.info("")["city"] == "", "a malformed or empty name degrades the same way")
    ok(timezones.info("UTC") == {"zone": "UTC", "offset": 0, "city": ""} and timezones.info("Etc/GMT+5")["offset"] == -18000 and timezones.info("Etc/GMT+5")["city"] == "", "UTC and Etc/ zones: an offset, no city")
    local = timezones.info("Local")
    ok(local["zone"] == "Local" and isinstance(local["offset"], int) and isinstance(local["city"], str), "Local answers without raising: " + repr(local))
    ok(local["offset"] == timezones.local_offset() or timezones.tzlocal is not None, "…with the machine's offset")
    print("  ✓ timezones: offsets and cities for the weather" + (" (tzlocal: " + repr(timezones.local_name()) + ")" if timezones.tzlocal else " (no tzlocal: Local names no zone)"))


if __name__ == "__main__":
    test_player()
    test_notes_bridge()
    test_holidays()
    test_timezones()
    print(f"  ✓ win/service: {passed} checks passed")
