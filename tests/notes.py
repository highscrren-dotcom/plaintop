#!/usr/bin/env python3
"""Stand for calendar/package/contents/code/notes.py: the iCalendar parser and the
recurrence rules on samples shaped like what Google, Yandex and iCloud hand out, the
local vdir, the JSON document, and the CalDAV client against a small fake server that
speaks PROPFIND, REPORT, PUT and DELETE with etags, Basic auth and a redirect; the
reminders — VALARM in and out, the timed and the "!" notes, the schedule, ack, snooze,
claim and completing a task on the server.

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
    # Several notes a day: "new" gets a fresh uid; --uid edits or deletes that one only.
    b64 = lambda t: base64.b64encode(t.encode()).decode()
    mine = lambda d: [e for e in d["days"].get("2026-10-11", []) if e["own"]]
    run("set", "local", "2026-10-11", b64("10:00 Первая"))
    code, doc = run("set", "local", "2026-10-11", b64("15:00 Вторая"), "--uid", "new")
    ok(code == 0 and len(mine(doc)) == 2 and len({e["uid"] for e in mine(doc)}) == 2, "two notes on one day: " + repr([e["uid"] for e in mine(doc)]))
    second = next(e["uid"] for e in mine(doc) if e["summary"] == "Вторая")
    code, doc = run("set", "local", "2026-10-11", b64("16:00 Вторая, позже"), "--uid", second)
    ok(sorted(e["text"] for e in mine(doc)) == ["10:00 Первая", "16:00 Вторая, позже"], "--uid edits that note: " + repr([e["text"] for e in mine(doc)]))
    code, doc = run("delete", "local", "2026-10-11", "--uid", second)
    ok([e["text"] for e in mine(doc)] == ["10:00 Первая"], "--uid deletes that note only: " + repr([e["text"] for e in mine(doc)]))
    code, doc = run("set", "local", "2026-10-11", b64("x"), "--uid", "someone@elsewhere")
    ok(code == 1 and doc["ok"] is False, "a uid that is no note of yours on that day is refused: " + repr(doc))
    run("delete", "local", "2026-10-11")
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
        elif self.path in STORE.items:
            if not self.authed():
                return
            etag, ics = STORE.items[self.path]
            STORE.log.append(("GET", self.path))
            self.reply(200, ics, {"ETag": etag})
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

    # The settings page's way: the secret in the inbox, hex, the command line without it.
    inbox = Path(TMP) / "plaincalendar" / "inbox.ini"
    secret = 'пароль;="x'
    inbox.write_text("[icloud]\npassword=" + secret.encode().hex() + "\n", encoding="utf-8")
    bare = {"id": "icloud", "name": "iCloud", "kind": "caldav", "url": base, "user": USER, "calendar": ""}
    code, listed = run("account-save", base64.b64encode(json.dumps(bare).encode()).decode())
    stored = json.loads((Path(TMP) / "plaincalendar" / "accounts.json").read_text(encoding="utf-8"))
    ok(code == 0 and next(x for x in stored if x["id"] == "icloud").get("password") == secret, "the secret came from the inbox, not the command line")
    ok(not inbox.exists(), "the inbox is deleted once read")
    ok(oct(os.stat(Path(TMP) / "plaincalendar").st_mode & 0o777) == "0o700", "the folder of the secrets is mode 700")
    run("account-remove", "icloud")

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
    # A second note that day is a resource of its own, created and removed by its uid.
    code, doc = run("set", "yandex", "2026-10-21", base64.b64encode("09:00 Утро".encode()).decode())
    code, doc = run("set", "yandex", "2026-10-21", base64.b64encode("18:00 Вечер".encode()).decode(), "--uid", "new")
    puts = [l for l in STORE.log if l[0] == "PUT"]
    two = [x for x in doc["days"].get("2026-10-21", []) if x["own"]]
    ok(len(two) == 2 and puts[-1][3] == "*" and puts[-1][1] != puts[-2][1], "a second note, a second resource: " + repr([p[1] for p in puts[-2:]]))
    evening = next(x["uid"] for x in two if x["summary"] == "Вечер")
    code, doc = run("delete", "yandex", "2026-10-21", "--uid", evening)
    ok([x["summary"] for x in doc["days"].get("2026-10-21", []) if x["own"]] == ["Утро"], "the second deleted by its uid, the first kept")
    run("delete", "yandex", "2026-10-21")

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


# ── Reminders ─────────────────────────────────────────────────────────────────
ALARMS = """BEGIN:VCALENDAR
BEGIN:VEVENT
UID:al1
DTSTART:20261010T090000
DTEND:20261010T100000
SUMMARY:Встреча
BEGIN:VALARM
ACTION:DISPLAY
DESCRIPTION:Встреча
TRIGGER:-PT15M
END:VALARM
BEGIN:VALARM
ACTION:AUDIO
TRIGGER;RELATED=END:PT5M
END:VALARM
END:VEVENT
BEGIN:VEVENT
UID:al2
DTSTART;VALUE=DATE:20261011
SUMMARY:День
BEGIN:VALARM
TRIGGER;VALUE=DATE-TIME:20261010T180000
END:VALARM
BEGIN:VALARM
TRIGGER:-P1D
END:VALARM
END:VEVENT
BEGIN:VEVENT
UID:al3
DTSTART:20261012T080000
DURATION:PT45M
SUMMARY:Без будильника
END:VEVENT
END:VCALENDAR
"""


def test_reminders():
    # VALARM and DURATION parsed; the end of a timed entry kept.
    es = {e["uid"]: e for e in notes.parse_ics(ALARMS)}
    ok(es["al1"]["alarms"] == [{"rel": -900, "end": False}, {"rel": 300, "end": True}], "relative triggers, one off the end: " + repr(es["al1"]["alarms"]))
    ok(es["al1"]["minutes"] == 60 and es["al1"]["end"] == "10:00", "the length and the end: " + repr(es["al1"]))
    ok(es["al2"]["alarms"] == [{"at": "2026-10-10T18:00"}, {"rel": -86400, "end": False}], "an absolute trigger and a day before: " + repr(es["al2"]["alarms"]))
    ok(es["al3"]["alarms"] == [] and es["al3"]["minutes"] == 45, "DURATION read, no alarm: " + repr(es["al3"]))
    ok(notes.parse_duration("P1DT9H") == 118800 and notes.parse_duration("-PT15M") == -900
       and notes.parse_duration("P2W") == 1209600 and notes.parse_duration("PT0S") == 0 and notes.parse_duration("x") is None, "durations")

    # When each rings.
    opts = notes.alarm_options(lead=10, hour="09:00", events=True)
    t = lambda e, d: [x.strftime("%Y-%m-%dT%H:%M") for x in notes.alarm_times(es[e], dt.date.fromisoformat(d), opts)]
    ok(t("al1", "2026-10-10") == ["2026-10-10T08:45", "2026-10-10T10:05"], "15 min before, 5 min after the end: " + repr(t("al1", "2026-10-10")))
    ok(t("al2", "2026-10-11") == ["2026-10-10T18:00", "2026-10-10T09:00"], "absolute as is; a day before an all-day entry counts from the hour: " + repr(t("al2", "2026-10-11")))
    ok(t("al3", "2026-10-12") == ["2026-10-12T07:50"], "no VALARM: the lead before a timed entry: " + repr(t("al3", "2026-10-12")))
    quiet = notes.alarm_options(lead=10, hour="09:00", events=False)
    ok(notes.alarm_times(es["al3"], dt.date(2026, 10, 12), quiet) == [], "…unless events without alarms are not wanted")

    # The schedule: a window around now, acknowledged out, snoozed moved.
    now = dt.datetime(2026, 10, 10, 8, 50)
    sources = [("acc", {"entries": list(es.values())})]
    st = {"acked": {}, "snoozed": {}}
    due = notes.alarms_for(sources, now, notes.alarm_options(12, "09:00", True, 12, True), st)
    ok([a["at"] for a in due] == ["2026-10-10T08:45", "2026-10-10T09:00", "2026-10-10T10:05", "2026-10-10T18:00"], "four alarms in the window, sorted: " + repr([(a["at"], a["uid"]) for a in due]))
    stamp = lambda d: d["at"].replace("-", "").replace(":", "")
    ok(due[0]["key"] == "acc|al1|2026-10-10|0|" + stamp(due[0]) and due[1]["key"] == "acc|al2|2026-10-11|1|" + stamp(due[1]) and due[0]["summary"] == "Встреча",
       "keys name the account, the uid, the day, the alarm and its time: " + due[0]["key"])
    st = {"acked": {due[0]["key"]: "2026-10-10T08:46"}, "snoozed": {due[1]["key"]: "2026-10-10T12:00"}}
    due = notes.alarms_for(sources, now, notes.alarm_options(12, "09:00", True, 12, True), st)
    ok([a["at"] for a in due] == ["2026-10-10T10:05", "2026-10-10T12:00", "2026-10-10T18:00"], "acknowledged gone, snoozed moved: " + repr([a["at"] for a in due]))
    ok(due[1]["snoozed"] is True and due[0]["snoozed"] is False, "the snoozed one says so")
    due = notes.alarms_for(sources, now, notes.alarm_options(12, "09:00", True, 0, True), {"acked": {}, "snoozed": {}})
    ok([a["at"] for a in due][0] == "2026-10-10T09:00", "missed 0: nothing from before now: " + repr([a["at"] for a in due]))
    ok(notes.alarms_for(sources, now, notes.alarm_options(12, "09:00", True, 12, False), st) == [], "--no-alarms: none")

    # The widget's own notes: a time in the first line, "!" for a day's reminder.
    ok(notes.parse_head("14:30 Стоматолог") == ("", (14, 30), None, "Стоматолог"), "a time")
    ok(notes.parse_head("9.00-10.30 Встреча") == ("", (9, 0), (10, 30), "Встреча"), "a range with points")
    ok(notes.parse_head("!Купить молоко") == ("!", None, None, "Купить молоко") and notes.parse_head("! hi") == ("!", None, None, "hi"), "a bang")
    ok(notes.parse_head("25:99 x") == ("", None, None, "25:99 x") and notes.parse_head("Стоматолог 14:00") == ("", None, None, "Стоматолог 14:00"), "not a time: plain text")
    ics = notes.own_ics("2026-10-09", "14:30 Стоматолог\nкарта", lead=10)
    flat = "\n".join(notes.unfold(ics))
    begins = notes.utc_stamp(dt.datetime(2026, 10, 9, 14, 30))
    ends = notes.utc_stamp(dt.datetime(2026, 10, 9, 15, 30))
    ok(f"DTSTART:{begins}" in flat and f"DTEND:{ends}" in flat, "a timed note in UTC, an hour long: " + flat)
    ok("BEGIN:VALARM" in flat and "TRIGGER:-PT10M" in flat and "SUMMARY:Стоматолог" in flat, "the lead as a VALARM, the time out of the summary: " + flat)
    back = notes.parse_ics(ics)[0]
    ok(back["time"] == "14:30" and back["minutes"] == 60 and back["alarms"] == [{"rel": -600, "end": False}], "round trip: " + repr(back))
    ok(notes.own_text(back) == "14:30 Стоматолог\nкарта", "the editor's text rebuilt: " + repr(notes.own_text(back)))
    back = notes.parse_ics(notes.own_ics("2026-10-09", "9.00-10.30 Встреча", lead=0))[0]
    ok(back["end"] == "10:30" and back["minutes"] == 90 and notes.own_text(back) == "09:00-10:30 Встреча", "a range survives: " + repr(back))
    ok(back["alarms"] == [{"rel": 0, "end": False}], "lead 0 rings at the time: " + repr(back["alarms"]))
    back = notes.parse_ics(notes.own_ics("2026-10-09", "16:00 Созвон", lead=-1))[0]
    ok(back["alarms"] == [], "lead -1: no alarm")
    ics = notes.own_ics("2026-10-09", "!Купить молоко", hour="7:30")
    back = notes.parse_ics(ics)[0]
    ok("DTSTART;VALUE=DATE:20261009" in ics and back["alarms"] == [{"at": "2026-10-09T07:30"}], "a bang: all-day with an alarm at the hour: " + repr(back["alarms"]))
    ok(notes.own_text(back) == "!Купить молоко", "…and the bang comes back: " + repr(notes.own_text(back)))
    back = notes.parse_ics(notes.own_ics("2026-10-09", "Просто заметка"))[0]
    ok(back["alarms"] == [] and notes.own_text(back) == "Просто заметка", "plain text stays plain")

    # Through the CLI: a timed note tomorrow at 12:00 rings at 11:50; ack, snooze, claim.
    tomorrow = (dt.date.today() + dt.timedelta(days=1)).isoformat()
    code, doc = run("set", "local", tomorrow, base64.b64encode("12:00 Созвон".encode()).decode(), "--lead", "10")
    mine = [a for a in doc["alarms"] if a["own"]]
    ok(code == 0 and len(mine) == 1 and mine[0]["at"] == tomorrow + "T11:50" and mine[0]["text"] == "12:00 Созвон", "the note's alarm in the document: " + repr(doc["alarms"]))
    ok(doc["days"][tomorrow][0]["text"] == "12:00 Созвон" and doc["days"][tomorrow][0]["time"] == "12:00", "the day's entry carries the text and the time: " + repr(doc["days"][tomorrow][0]))
    ok(doc["days"][tomorrow][0]["lead"] == 10, "the entry carries its lead for the sticker's remind row: " + repr(doc["days"][tomorrow][0].get("lead")))
    # The sticker's other choices: an hour before, and no alarm at all.
    code, doc = run("set", "local", tomorrow, base64.b64encode("12:00 Созвон".encode()).decode(), "--lead", "60")
    ok(doc["days"][tomorrow][0]["lead"] == 60 and [a["at"] for a in doc["alarms"] if a["own"]] == [tomorrow + "T11:00"], "an hour before: " + repr(doc["days"][tomorrow][0].get("lead")))
    code, doc = run("set", "local", tomorrow, base64.b64encode("12:00 Созвон".encode()).decode(), "--lead", "-1")
    ok(doc["days"][tomorrow][0]["lead"] == -1 and not doc["days"][tomorrow][0]["alarm"], "no alarm: lead -1, alarm false")
    code, doc = run("dump", "--lead", "10")
    ok(not [a for a in doc["alarms"] if a["own"]], "a note of yours without an alarm stays silent under the settings' lead: " + repr(doc["alarms"]))
    code, doc = run("set", "local", tomorrow, base64.b64encode("12:00 Созвон".encode()).decode(), "--lead", "10")
    key = mine[0]["key"]
    code, doc = run("ack", key)
    ok(code == 0 and not [a for a in doc["alarms"] if a["own"]], "acknowledged: gone")
    code, doc = run("snooze", key, "30")
    mine = [a for a in doc["alarms"] if a["own"]]
    soon = dt.datetime.now() + dt.timedelta(minutes=30)
    ok(len(mine) == 1 and mine[0]["snoozed"] and abs((dt.datetime.strptime(mine[0]["at"], "%Y-%m-%dT%H:%M") - soon).total_seconds()) < 120, "snoozed by minutes: " + repr(mine))
    code, doc = run("snooze", key, tomorrow + "T07:00")
    mine = [a for a in doc["alarms"] if a["own"]]
    ok(mine[0]["at"] == tomorrow + "T07:00", "snoozed to a time: " + repr(mine))
    code, doc = run("dump", "--no-alarms")
    ok(doc["alarms"] == [], "--no-alarms empties the list")

    # Upcoming keeps what rang unanswered — first, marked — and drops what is over.
    b64 = lambda t: base64.b64encode(t.encode()).decode()
    now = dt.datetime.now()
    def at(minutes):
        t = now + dt.timedelta(minutes=minutes)
        return t.date().isoformat(), t.strftime("%H:%M")
    d1, t1 = at(-60)
    code, doc = run("set", "local", d1, b64(t1 + " Пропущенное"), "--lead", "10", "--uid", "new")
    first = doc["upcoming"][0] if doc["upcoming"] else {}
    ok(first.get("summary") == "Пропущенное" and first.get("missed") is True and first.get("key"), "a missed reminder heads upcoming, marked: " + repr(first))
    code, doc = run("ack", first.get("key", ""))
    ok(not [u for u in doc["upcoming"] if u["summary"] == "Пропущенное"], "answered and over: gone from upcoming")
    d2, t2 = at(-90)
    _, t2e = at(-30)
    run("set", "local", d2, b64(t2 + "-" + t2e + " Прошло"), "--lead", "-1", "--uid", "new")
    code, doc = run("dump")
    ok(not [u for u in doc["upcoming"] if u["summary"] == "Прошло"], "over, with no alarm: not listed")
    if now.hour >= 1:
        d3, t3 = at(-10)
        _, t3e = at(50)
        run("set", "local", d3, b64(t3 + "-" + t3e + " Идёт"), "--lead", "-1", "--uid", "new")
        code, doc = run("dump")
        ok([u for u in doc["upcoming"] if u["summary"] == "Идёт" and not u.get("missed")], "still going: listed")
    for day in {d1, d2, at(-10)[0]}:
        code, doc = run("dump")
        for e in doc["days"].get(day, []):
            if e["own"] and e["summary"] in ("Пропущенное", "Прошло", "Идёт"):
                run("delete", "local", day, "--uid", e["uid"])
    code, got = run("claim", key)
    ok(code == 0 and got["claimed"] is True, "the first claim wins")
    code, got = run("claim", key)
    ok(got["claimed"] is False, "the second does not")
    state = json.loads((Path(TMP) / "plaincalendar" / "reminders.json").read_text())
    ok(key in state["snoozed"] and key not in state["acked"], "the state file: " + repr(state))
    # "Done" belongs to one ring: the same note rewritten to another time rings again.
    # Earlier, not later: the alarms reach 36 hours ahead, and tomorrow's 12:50 is out of
    # them until 00:50 tonight — the stand failed when run just after midnight.
    code, doc = run("ack", key)
    code, doc = run("set", "local", tomorrow, base64.b64encode("11:30 Созвон".encode()).decode(), "--lead", "10")
    again = [a for a in doc["alarms"] if a["own"]]
    ok(len(again) == 1 and again[0]["at"] == tomorrow + "T11:20" and again[0]["key"] != key, "a rewritten note rings again after an old done: " + repr(again))
    run("set", "local", tomorrow, base64.b64encode("12:00 Созвон".encode()).decode(), "--lead", "10")
    run("delete", "local", tomorrow)

    # Completing a task on the server: GET, STATUS:COMPLETED, PUT with If-Match.
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{port}/"
    STORE.items["/calendars/login/events-default/todos.ics"] = ('"t9"', YANDEX_TODO)
    acc = {"id": "yandex", "name": "Яндекс", "kind": "caldav", "url": base, "user": USER, "password": PASSWORD, "calendar": ""}
    run("account-save", base64.b64encode(json.dumps(acc).encode()).decode())
    code, doc = run("sync", "--from", "2026-10-01", "--to", "2026-11-30", "--force")
    ok(any(x["uid"] == "todo-1" and not x["done"] for x in doc["days"].get("2026-10-10", [])), "the task is open: " + repr(doc["days"].get("2026-10-10")))
    STORE.log.clear()
    code, doc = run("done", "yandex", "todo-1", "yandex|todo-1|2026-10-10|0")
    puts = [l for l in STORE.log if l[0] == "PUT"]
    ok(code == 0 and ("GET", "/calendars/login/events-default/todos.ics") in STORE.log and len(puts) == 1 and puts[0][2] == '"t9"', "fetched, then put back with If-Match: " + repr(STORE.log))
    stored = STORE.items["/calendars/login/events-default/todos.ics"][1]
    ok(stored.count("STATUS:COMPLETED") == 2 and "PERCENT-COMPLETE:100" in stored and "STATUS:NEEDS-ACTION" not in stored, "todo-1 completed, todo-2 left as it was: " + stored)
    ok(any(x["uid"] == "todo-1" and x["done"] for x in doc["days"].get("2026-10-10", [])), "the document shows it done: " + repr(doc["days"].get("2026-10-10")))
    state = json.loads((Path(TMP) / "plaincalendar" / "reminders.json").read_text())
    ok("yandex|todo-1|2026-10-10|0" in state["acked"], "its alarm acknowledged")
    srv.shutdown()
    print("  ✓ reminders: alarms, timed notes, the schedule, ack/snooze/claim, a task completed")


if __name__ == "__main__":
    test_parsing()
    test_rules()
    test_own_ics()
    test_local_and_build()
    test_caldav()
    test_reminders()
    print(f"  ✓ notes.py: {passed} checks passed")
