#!/usr/bin/env python3
"""Stand for calendar/package/contents/code/notes.py: the iCalendar parser and the
recurrence rules on samples shaped like what Google, Yandex and iCloud hand out, the
local vdir, the JSON document, and the CalDAV client against a small fake server that
speaks PROPFIND, REPORT, PUT and DELETE with etags, Basic auth and a redirect.

    python3 tests/notes.py          # or ./install.sh --check-notes

Everything runs in a temporary directory: XDG_CONFIG_HOME, XDG_CACHE_HOME and
XDG_DATA_HOME point there, so the real accounts and notes are never touched.
"""
import base64
import datetime as dt
import http.server
import importlib.util
import io
import json
import os
import sys
import tempfile
import threading
import contextlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TMP = tempfile.mkdtemp(prefix="plaincalendar-test-")
for var in ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME"):
    os.environ[var] = TMP

# No __pycache__ beside notes.py: the package directory is what --pack zips.
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("notes", ROOT / "calendar/package/contents/code/notes.py")
notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notes)

passed = 0


def ok(cond, what):
    global passed
    if not cond:
        print("  ✗ " + what)
        sys.exit(1)
    passed += 1


def run(*argv):
    """notes.py's main with argv, its stdout parsed as JSON."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = notes.main(list(argv))
    text = out.getvalue()
    try:
        return code, json.loads(text.strip().splitlines()[-1]) if text.strip() else None
    except json.JSONDecodeError:
        return code, text


# ── iCalendar samples ─────────────────────────────────────────────────────────
GOOGLE = """BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Google Inc//Google Calendar 70.9054//EN
BEGIN:VTIMEZONE
TZID:Europe/Moscow
END:VTIMEZONE
BEGIN:VEVENT
DTSTART;TZID=Europe/Moscow:20261009T140000
DTEND;TZID=Europe/Moscow:20261009T150000
UID:abc123@google.com
SUMMARY:Стоматолог\\, зуб
DESCRIPTION:Взять карту\\nи полис
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20261012
DTEND;VALUE=DATE:20261015
UID:trip@google.com
SUMMARY:Поездка
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:19900315
DTEND;VALUE=DATE:19900316
RRULE:FREQ=YEARLY
UID:bday@google.com
SUMMARY:ДР Маши
END:VEVENT
BEGIN:VEVENT
DTSTART:20261005T070000Z
DTEND:20261005T073000Z
RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261130T000000Z
EXDATE:20261012T070000Z
UID:standup@google.com
SUMMARY:Стендап
END:VEVENT
END:VCALENDAR
"""

YANDEX_TODO = """BEGIN:VCALENDAR
BEGIN:VTODO
UID:todo-1
SUMMARY:Купить фильтр
DUE;VALUE=DATE:20261010
STATUS:NEEDS-ACTION
END:VTODO
BEGIN:VTODO
UID:todo-2
SUMMARY:Сделано
DUE;VALUE=DATE:20261010
STATUS:COMPLETED
END:VTODO
BEGIN:VTODO
UID:todo-3
SUMMARY:Без даты
END:VTODO
END:VCALENDAR
"""

FOLDED = ("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:fold\r\nDTSTART;VALUE=DATE:20261020\r\n"
          "SUMMARY:A very long summary that the sender folded at seventy-five octets as the s\r\n"
          " tandard says\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")

MONTHLY = """BEGIN:VCALENDAR
BEGIN:VEVENT
UID:m1
DTSTART;VALUE=DATE:20260112
RRULE:FREQ=MONTHLY;BYDAY=2MO;COUNT=12
SUMMARY:Второй понедельник
END:VEVENT
BEGIN:VEVENT
UID:m2
DTSTART;VALUE=DATE:20260131
RRULE:FREQ=MONTHLY;BYMONTHDAY=-1
SUMMARY:Последний день
END:VEVENT
BEGIN:VEVENT
UID:d1
DTSTART;VALUE=DATE:20261001
RRULE:FREQ=DAILY;INTERVAL=3;COUNT=4
SUMMARY:Каждые три дня
END:VEVENT
END:VCALENDAR
"""


def test_parsing():
    es = {e["uid"]: e for e in notes.parse_ics(GOOGLE)}
    ok(len(es) == 4, "four events parsed")
    e = es["abc123@google.com"]
    ok(e["summary"] == "Стоматолог, зуб" and e["description"] == "Взять карту\nи полис", "escapes undone: " + repr(e))
    local = (dt.datetime(2026, 10, 9, 14, 0, tzinfo=notes.ZoneInfo("Europe/Moscow")).astimezone())
    ok(e["start"] == local.date().isoformat() and e["time"] == local.strftime("%H:%M"), "TZID converted to local: " + repr(e))
    trip = es["trip@google.com"]
    ok(trip["span"] == 3 and trip["time"] == "", "an all-day event of three days: " + repr(trip))
    ok(es["bday@google.com"]["rrule"]["FREQ"] == "YEARLY", "the rule kept")
    standup = es["standup@google.com"]
    utc = dt.datetime(2026, 10, 5, 7, 0, tzinfo=dt.timezone.utc).astimezone()
    ok(standup["time"] == utc.strftime("%H:%M") and standup["exdates"] == [utc.date().isoformat() if False else dt.datetime(2026, 10, 12, 7, 0, tzinfo=dt.timezone.utc).astimezone().date().isoformat()], "Z times to local, EXDATE kept: " + repr(standup))
    todos = notes.parse_ics(YANDEX_TODO)
    ok([t["uid"] for t in todos] == ["todo-1", "todo-2"], "todos with a due date, the undated one dropped: " + repr(todos))
    ok(todos[0]["kind"] == "todo" and not todos[0]["done"] and todos[1]["done"], "done comes from STATUS")
    f = notes.parse_ics(FOLDED)[0]
    ok(f["summary"].endswith("as the standard says"), "folded lines joined: " + f["summary"])
    print("  ✓ parsing")


def test_rules():
    es = {e["uid"]: e for e in notes.parse_ics(GOOGLE)}
    lo, hi = dt.date(2026, 10, 1), dt.date(2026, 11, 30)
    ok(notes.occurrences(es["bday@google.com"], dt.date(2026, 1, 1), dt.date(2026, 12, 31)) == [dt.date(2026, 3, 15)], "a yearly birthday")
    stand = [d.isoformat() for d in notes.occurrences(es["standup@google.com"], lo, hi)]
    ok("2026-10-05" in stand and "2026-10-07" in stand and "2026-10-12" not in stand and "2026-10-14" in stand, "weekly MO,WE with an EXDATE: " + repr(stand[:6]))
    ok(all(d <= "2026-11-30" for d in stand) and "2026-11-30" in stand, "UNTIL inclusive: " + stand[-1])
    trip = notes.occurrences(es["trip@google.com"], dt.date(2026, 10, 13), dt.date(2026, 10, 13))
    ok(trip == [dt.date(2026, 10, 12)], "a multi-day event overlapping the window: " + repr(trip))
    ms = {e["uid"]: e for e in notes.parse_ics(MONTHLY)}
    second = [d.isoformat() for d in notes.occurrences(ms["m1"], dt.date(2026, 1, 1), dt.date(2027, 12, 31))]
    ok(second[:3] == ["2026-01-12", "2026-02-09", "2026-03-09"] and len(second) == 12, "the second Monday, twelve times: " + repr(second))
    last = [d.isoformat() for d in notes.occurrences(ms["m2"], dt.date(2026, 2, 1), dt.date(2026, 4, 30))]
    ok(last == ["2026-02-28", "2026-03-31", "2026-04-30"], "the last day of the month: " + repr(last))
    every3 = [d.isoformat() for d in notes.occurrences(ms["d1"], dt.date(2026, 9, 1), dt.date(2026, 12, 31))]
    ok(every3 == ["2026-10-01", "2026-10-04", "2026-10-07", "2026-10-10"], "daily with an interval and a count: " + repr(every3))
    print("  ✓ recurrence rules")


def test_own_ics():
    text = "Стоматолог 14:00\nвзять карту; и полис, да\nвторая строка"
    ics = notes.own_ics("2026-10-09", text)
    ok("DTSTART;VALUE=DATE:20261009" in ics and "DTEND;VALUE=DATE:20261010" in ics, "an all-day event")
    flat = "\n".join(notes.unfold(ics))      # Cyrillic folds early: 74 octets is 37 letters
    ok("SUMMARY:Стоматолог 14:00" in flat and "DESCRIPTION:взять карту\\; и полис\\, да\\nвторая строка" in flat, "escapes applied: " + flat)
    ok(all(len(l.encode("utf-8")) <= 75 for l in ics.split("\r\n")), "folded at 75 octets")
    back = notes.parse_ics(ics)[0]
    ok(back["summary"] == "Стоматолог 14:00" and back["description"] == "взять карту; и полис, да\nвторая строка", "round trip: " + repr(back))
    ok(notes.is_own(back) and back["span"] == 1, "recognised as the widget's own")
    print("  ✓ the widget's own note as iCalendar")


def test_local_and_build():
    code, doc = run("set", "local", "2026-10-09", base64.b64encode("Заметка\nподробности".encode()).decode())
    ok(code == 0 and "2026-10-09" in doc["days"], "a local note lands in the document: " + repr(doc.get("days")))
    item = doc["days"]["2026-10-09"][0]
    ok(item["own"] and item["account"] == "local" and item["summary"] == "Заметка" and item["description"] == "подробности", repr(item))
    files = list((Path(TMP) / "plaincalendar" / "notes").glob("*.ics"))
    ok(len(files) == 1 and files[0].name.startswith("plaincalendar-2026-10-09@"), "one .ics in the vdir: " + repr(files))
    code, doc = run("set", "local", "2026-10-09", base64.b64encode("Переписано".encode()).decode())
    ok(doc["days"]["2026-10-09"][0]["summary"] == "Переписано" and len(list((Path(TMP) / "plaincalendar" / "notes").glob("*.ics"))) == 1, "rewritten in place")
    code, doc = run("delete", "local", "2026-10-09")
    ok("2026-10-09" not in doc["days"] and not list((Path(TMP) / "plaincalendar" / "notes").glob("*.ics")), "deleted")
    code, doc = run("set", "local", "2026-13-40", base64.b64encode(b"x").decode())
    ok(code == 1 and doc["ok"] is False, "a bad date is refused: " + repr(doc))
    # Upcoming: from today on, done todos left out, limited.
    today = dt.date.today()
    for i, text in enumerate(["позавчера", "сегодня", "завтра", "через неделю"]):
        day = today + dt.timedelta(days=[-2, 0, 1, 7][i])
        run("set", "local", day.isoformat(), base64.b64encode(text.encode()).decode())
    code, doc = run("dump", "--upcoming", "2")
    ok([u["summary"] for u in doc["upcoming"]] == ["сегодня", "завтра"], "upcoming from today, limited: " + repr(doc["upcoming"]))
    ok(doc["accounts"][0]["id"] == "local" and doc["accounts"][0]["ok"], "the local account is always there")
    for i in [-2, 0, 1, 7]:
        run("delete", "local", (today + dt.timedelta(days=i)).isoformat())
    print("  ✓ the local vdir and the document")


# ── A fake CalDAV server ──────────────────────────────────────────────────────
class Store:
    def __init__(self):
        self.items = {}          # href → (etag, ics)
        self.n = 0
        self.log = []

    def etag(self):
        self.n += 1
        return f'"e{self.n}"'


STORE = Store()
USER, PASSWORD = "login", "app-pass"


class Handler(http.server.BaseHTTPRequestHandler):
    def authed(self):
        expect = "Basic " + base64.b64encode(f"{USER}:{PASSWORD}".encode()).decode()
        if self.headers.get("Authorization") != expect:
            self.send_response(401)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return False
        return True

    def body(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        return self.rfile.read(n).decode("utf-8") if n else ""

    def reply(self, status, text, headers=None):
        data = text.encode("utf-8")
        self.send_response(status)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Type", "application/xml; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_PROPFIND(self):
        if not self.authed():
            return
        STORE.log.append(("PROPFIND", self.path, self.headers.get("Depth")))
        b = self.body()
        if self.path == "/":
            # The principal lives behind a redirect, as iCloud's does.
            self.reply(207, '<d:multistatus xmlns:d="DAV:"><d:response><d:href>/</d:href><d:propstat><d:prop>'
                            '<d:current-user-principal><d:href>/principals/old/</d:href></d:current-user-principal>'
                            '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>')
        elif self.path == "/principals/old/":
            self.send_response(301)
            self.send_header("Location", "/principals/users/login/")
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif self.path == "/principals/users/login/":
            ok("calendar-home-set" in b, "the principal is asked for its home")
            self.reply(207, '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response>'
                            '<d:href>/principals/users/login/</d:href><d:propstat><d:prop>'
                            '<c:calendar-home-set><d:href>/calendars/login/</d:href></c:calendar-home-set>'
                            '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>')
        elif self.path == "/calendars/login/":
            ok(self.headers.get("Depth") == "1", "the home is listed at depth 1")
            self.reply(207, '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
                            '<d:response><d:href>/calendars/login/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype>'
                            '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>'
                            '<d:response><d:href>/calendars/login/tasks/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/><c:calendar/></d:resourcetype>'
                            '<d:displayname>Задачи</d:displayname><c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set>'
                            '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>'
                            '<d:response><d:href>/calendars/login/events-default/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/><c:calendar/></d:resourcetype>'
                            '<d:displayname>Мои события</d:displayname><c:supported-calendar-component-set><c:comp name="VEVENT"/><c:comp name="VTODO"/></c:supported-calendar-component-set>'
                            '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>')
        else:
            self.reply(404, "")

    def do_REPORT(self):
        if not self.authed():
            return
        b = self.body()
        STORE.log.append(("REPORT", self.path, "VTODO" if 'name="VTODO"' in b else "VEVENT", "time-range" in b))
        comp = "VTODO" if 'name="VTODO"' in b else "VEVENT"
        parts = []
        for href, (etag, ics) in STORE.items.items():
            if href.startswith(self.path) and f"BEGIN:{comp}" in ics:
                data = ics.replace("&", "&amp;").replace("<", "&lt;")
                parts.append(f'<d:response><d:href>{href}</d:href><d:propstat><d:prop><d:getetag>{etag}</d:getetag>'
                             f'<c:calendar-data>{data}</c:calendar-data></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>')
        self.reply(207, '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">' + "".join(parts) + '</d:multistatus>')

    def do_PUT(self):
        if not self.authed():
            return
        b = self.body()
        STORE.log.append(("PUT", self.path, self.headers.get("If-Match"), self.headers.get("If-None-Match")))
        existing = STORE.items.get(self.path)
        if existing and self.headers.get("If-None-Match") == "*":
            self.reply(412, ""); return
        if existing and self.headers.get("If-Match") and self.headers.get("If-Match") != existing[0]:
            self.reply(412, ""); return
        etag = STORE.etag()
        STORE.items[self.path] = (etag, b)
        self.reply(201 if not existing else 204, "", {"ETag": etag})

    def do_DELETE(self):
        if not self.authed():
            return
        STORE.log.append(("DELETE", self.path, self.headers.get("If-Match")))
        STORE.items.pop(self.path, None)
        self.reply(204, "")

    def do_GET(self):
        if self.path == "/feed.ics":
            self.reply(200, GOOGLE)
        else:
            self.reply(404, "")

    def log_message(self, *args):
        pass


def test_caldav():
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{port}/"
    STORE.items["/calendars/login/events-default/google-like.ics"] = ('"e0"', GOOGLE)
    STORE.items["/calendars/login/events-default/todos.ics"] = ('"t0"', YANDEX_TODO)

    acc = {"id": "yandex", "name": "Яндекс", "kind": "caldav", "url": base, "user": USER, "password": PASSWORD, "calendar": ""}
    code, listed = run("account-save", base64.b64encode(json.dumps(acc).encode()).decode())
    ok(code == 0 and listed[0]["id"] == "yandex" and "password" not in listed[0] and listed[0]["has_password"], "saved without leaking the secret: " + repr(listed))
    ok(oct(os.stat(Path(TMP) / "plaincalendar" / "accounts.json").st_mode & 0o777) == "0o600", "accounts.json is mode 600")

    code, found = run("check", "yandex")
    ok(code == 0 and found["ok"] and [c["name"] for c in found["calendars"]] == ["Задачи", "Мои события"], "discovery through the redirect: " + repr(found))
    ok(found["calendars"][1]["href"] == base + "calendars/login/events-default/", "hrefs made absolute: " + found["calendars"][1]["href"])

    code, doc = run("sync", "--from", "2026-10-01", "--to", "2026-11-30", "--force")
    ok(code == 0 and doc["accounts"][1]["ok"] and not doc["accounts"][1]["error"], "the account synced: " + repr(doc["accounts"]))
    ok(any(x["summary"] == "Купить фильтр" and x["kind"] == "todo" for x in doc["days"].get("2026-10-10", [])), "a todo on its due day: " + repr(doc["days"].get("2026-10-10")))
    ok([x["summary"] for x in doc["days"].get("2026-10-13", [])] == ["Поездка"], "the trip spans its days: " + repr(doc["days"].get("2026-10-13")))
    reports = [l for l in STORE.log if l[0] == "REPORT"]
    ok(any(l[2] == "VEVENT" and l[3] for l in reports) and any(l[2] == "VTODO" and not l[3] for l in reports), "events by time range, todos without: " + repr(reports))
    ok(("PROPFIND", "/principals/old/", "0") in STORE.log and ("PROPFIND", "/principals/users/login/", "0") in STORE.log, "the redirect was followed with PROPFIND, not GET")

    # The widget's note goes to the server as a PUT, then the server's copy is read back.
    code, doc = run("set", "yandex", "2026-10-20", base64.b64encode("Встреча\nв офисе".encode()).decode())
    puts = [l for l in STORE.log if l[0] == "PUT"]
    ok(code == 0 and len(puts) == 1 and puts[0][3] == "*" and puts[0][1].endswith("/plaincalendar-2026-10-20@" + (notes.socket.gethostname() or "host") + ".ics"), "created with If-None-Match: " + repr(puts))
    code, doc = run("dump", "--from", "2026-10-01", "--to", "2026-11-30")
    mine = [x for x in doc["days"].get("2026-10-20", []) if x["own"]]
    ok(len(mine) == 1 and mine[0]["account"] == "yandex" and mine[0]["summary"] == "Встреча", "read back from the server: " + repr(mine))
    code, doc = run("set", "yandex", "2026-10-20", base64.b64encode("Встреча перенесена".encode()).decode())
    puts = [l for l in STORE.log if l[0] == "PUT"]
    ok(len(puts) == 2 and puts[1][2] == '"e1"', "updated with If-Match on the etag: " + repr(puts[1]))
    code, doc = run("delete", "yandex", "2026-10-20")
    dels = [l for l in STORE.log if l[0] == "DELETE"]
    ok(len(dels) == 1 and dels[0][2] == '"e2"' and not [x for x in doc["days"].get("2026-10-20", []) if x["own"]], "deleted on the server: " + repr(dels))

    # A wrong password: the account reports the error, the rest of the document stands.
    acc["password"] = "wrong"
    run("account-save", base64.b64encode(json.dumps(acc).encode()).decode())
    code, doc = run("sync", "--force")
    ok(code == 0 and "401" in doc["accounts"][1]["error"] and doc["accounts"][0]["ok"], "401 reported per account: " + repr(doc["accounts"][1]))
    acc["password"] = ""     # an empty secret keeps the stored one
    run("account-save", base64.b64encode(json.dumps(acc).encode()).decode())
    stored = json.loads((Path(TMP) / "plaincalendar" / "accounts.json").read_text())
    ok(stored[0]["password"] == "wrong", "an empty password in the form keeps the stored one")

    # A read-only ICS link.
    feed = {"id": "feed", "name": "Лента", "kind": "ics", "url": base + "feed.ics"}
    run("account-save", base64.b64encode(json.dumps(feed).encode()).decode())
    code, found = run("check", "feed")
    ok(found["ok"] and found["entries"] == 4, "the feed is reachable: " + repr(found))
    code, doc = run("sync", "--from", "2026-10-01", "--to", "2026-11-30", "--force")
    ok(any(x["account"] == "feed" and x["summary"] == "Стендап" for x in doc["days"].get("2026-10-07", [])), "feed entries shown: " + repr(doc["days"].get("2026-10-07")))
    code, doc = run("set", "feed", "2026-10-21", base64.b64encode(b"x").decode())
    ok(code == 1 and "read-only" in doc["error"], "writing to a feed is refused")
    code, listed = run("account-remove", "feed")
    ok([a["id"] for a in listed] == ["yandex"], "removed")
    srv.shutdown()
    print("  ✓ CalDAV against the fake server")


if __name__ == "__main__":
    test_parsing()
    test_rules()
    test_own_ics()
    test_local_and_build()
    test_caldav()
    print(f"  ✓ notes.py: {passed} checks passed")
