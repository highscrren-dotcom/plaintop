#!/usr/bin/env python3
"""Notes and calendars for plaincalendar.

The widget cannot write files or talk CalDAV from QML (docs/GOTCHAS.md), so it runs this
script through Plasma's executable engine and reads one JSON document back: the entries
of every day in a window, the next few upcoming ones, and the state of every account.
Everything here is the standard library.

Accounts, ~/.config/plaincalendar/accounts.json (mode 600), one object each:

    {"id": "yandex", "name": "Яндекс", "kind": "caldav",
     "url": "https://caldav.yandex.ru/", "user": "login", "password": "app password",
     "calendar": ""}                      # a calendar href, or empty: the first one found
    {"id": "icloud", "kind": "caldav", "url": "https://caldav.icloud.com/", …}
    {"id": "google", "kind": "google", "url": "https://apidata.googleusercontent.com/caldav/v2/",
     "user": "me@gmail.com", "client_id": "…", "client_secret": "…"}   # then `google-auth`
    {"id": "feed", "kind": "ics", "url": "https://…/basic.ics"}        # read-only

"local" is always there: a folder of .ics files, one per note, a vdir. CalDAV is one
protocol for all three providers; Google's only takes OAuth, hence its kind and the
one-off browser login. The widget's own notes of a day are VEVENTs with the uid
plaincalendar-<date>@<host> (the first) or plaincalendar-<date>-<hex>@<host> (each one
more, `set --uid new`), in the account the settings name; the first line of the text is
the SUMMARY, the rest the DESCRIPTION.

Reminders live in the text and in the data. A first line "14:30 Dentist" makes the note a
timed event (DTSTART/DTEND in UTC, an hour long unless "14:30-15:15") with a VALARM
--lead minutes before it; "!Buy milk" keeps the note all-day and sets a VALARM at --hour
of that day. Both reach the account's server, so a phone rings too. The document carries
`alarms`: every alarm of every entry (VALARMs, or --lead before a timed entry without one)
that falls between --missed hours ago and 36 hours ahead, minus those acknowledged, with
snoozed ones moved; the widget fires them. The state is reminders.json in the cache.

    notes.py sync [--from D --to D] [--every MIN] [--force] [--upcoming N] [ALARM OPTS]
    notes.py dump [--from D --to D] [--upcoming N] [ALARM OPTS]               print from the caches
    notes.py set ACCOUNT DATE B64TEXT [--uid UID|new] [ALARM OPTS]            create or update a note
    notes.py delete ACCOUNT DATE [--uid UID]
    notes.py ack KEY                        the alarm was seen; never again
    notes.py snooze KEY MINUTES|ISO         again in MINUTES, or at a local "YYYY-MM-DDTHH:MM"
    notes.py claim KEY                      {"claimed": true} for the one instance that asked first
    notes.py done ACCOUNT UID [KEY]         complete the task on its server, acknowledge KEY
      ALARM OPTS: --lead MIN (10; -1 none) --hour HH:MM (09:00) --no-events --missed HOURS (12) --no-alarms
    notes.py accounts                       the accounts without their secrets
    notes.py account-save B64JSON           add or replace one (by id); its secrets from inbox.ini
    notes.py account-remove ID
    notes.py check ID                       reach the server, list its calendars
    notes.py google-auth ID                 the browser login; stores the refresh token
"""
import argparse
import base64
import binascii
import configparser
import datetime as dt
import http.client
import http.server
import json
import os
import re
import secrets
import socket
import ssl
import subprocess
import sys
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    from zoneinfo import ZoneInfo
except ImportError:          # Python < 3.9: times in named zones are taken as local
    ZoneInfo = None

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "plaincalendar"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "plaincalendar"
LOCAL_DIR = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "plaincalendar" / "notes"
ACCOUNTS = CONFIG_DIR / "accounts.json"
# The settings page cannot hand a secret over on a command line — anyone on the machine
# reads /proc/*/cmdline — so it writes it here (QtCore.Settings, hex), in a folder kept
# at 700, and account-save takes it and deletes the file.
INBOX = CONFIG_DIR / "inbox.ini"
# What was acknowledged or snoozed, and the claims of the instance that shows an alarm.
REMINDERS = CACHE_DIR / "reminders.json"
CLAIMS = CACHE_DIR / "claims"
PRODID = "-//s1dd1//plaincalendar//EN"
TIMEOUT = 15
DAV = "DAV:"
CAL = "urn:ietf:params:xml:ns:caldav"
SECRET_KEYS = ("password", "client_secret", "refresh_token", "access_token")


# ── iCalendar ─────────────────────────────────────────────────────────────────
def unfold(text):
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    out = []
    for line in lines:
        if line[:1] in (" ", "\t") and out:
            out[-1] += line[1:]
        elif line.strip():
            out.append(line)
    return out


def split_line(line):
    """NAME;PARAM=value;PARAM="quoted:value":value → (NAME, {PARAM: value}, value)."""
    i, quoted = 0, False
    while i < len(line):
        c = line[i]
        if c == '"':
            quoted = not quoted
        elif c == ":" and not quoted:
            break
        i += 1
    head, value = line[:i], line[i + 1:]
    parts, cur, quoted = [], "", False
    for c in head:
        if c == '"':
            quoted = not quoted
        if c == ";" and not quoted:
            parts.append(cur)
            cur = ""
        else:
            cur += c
    parts.append(cur)
    params = {}
    for p in parts[1:]:
        if "=" in p:
            k, v = p.split("=", 1)
            params[k.upper()] = v.strip('"')
    return parts[0].upper(), params, value


def unescape(value):
    return re.sub(r"\\([\;,nN])", lambda m: "\n" if m.group(1) in "nN" else m.group(1), value)


def escape(value):
    return value.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def components(text):
    """The VEVENT and VTODO components of an iCalendar text, each a list of
    (name, params, value) — VTIMEZONE and the rest are not needed: zones go by name."""
    stack, out = [], []
    for line in unfold(text):
        name, params, value = split_line(line)
        if name == "BEGIN":
            stack.append((value.upper(), []))
        elif name == "END":
            if stack:
                kind, props = stack.pop()
                if kind in ("VEVENT", "VTODO"):
                    out.append((kind, props))
                elif kind == "VALARM" and stack:
                    # An alarm belongs to the entry around it: its properties ride along
                    # as one pseudo-property, the list in place of a value.
                    stack[-1][1].append(("VALARM", {}, props))
        elif stack:
            stack[-1][1].append((name, params, value))
    return out


def local_datetime(value, params):
    """A DATE-TIME value as a naive local datetime, or None: Z and TZID are converted,
    a floating time is taken as local."""
    m = re.fullmatch(r"(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z?)", value.strip())
    if not m:
        return None
    y, mo, d, hh, mi, ss, z = m.groups()
    when = dt.datetime(int(y), int(mo), int(d), int(hh), int(mi), int(ss or 0))
    tzid = params.get("TZID")
    if z == "Z":
        when = when.replace(tzinfo=dt.timezone.utc).astimezone().replace(tzinfo=None)
    elif tzid and ZoneInfo is not None:
        try:
            when = when.replace(tzinfo=ZoneInfo(tzid)).astimezone().replace(tzinfo=None)
        except Exception:
            pass                # an unknown zone name: taken as local time
    return when


def to_local(value, params):
    """A DATE or DATE-TIME value as (date, "HH:MM" or ""), in local time."""
    value = value.strip()
    if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", value):
        return dt.date(int(value[:4]), int(value[4:6]), int(value[6:8])), ""
    when = local_datetime(value, params)
    if when is None:
        return None, ""
    return when.date(), when.strftime("%H:%M")


def utc_stamp(when):
    """A naive local datetime as an iCalendar UTC value: unambiguous on every server,
    no VTIMEZONE needed."""
    return when.astimezone(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def parse_duration(value):
    """An iCalendar duration ("-PT15M", "P1DT9H", "PT0S", "P2W") in seconds, signed."""
    m = re.fullmatch(r"([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", value.strip())
    if not m:
        return None
    sign, w, d, h, mi, sec = m.groups()
    total = (int(w or 0) * 7 + int(d or 0)) * 86400 + int(h or 0) * 3600 + int(mi or 0) * 60 + int(sec or 0)
    return -total if sign == "-" else total


def alarm_of(props):
    """A VALARM's trigger: {"at": local "YYYY-MM-DDTHH:MM"} for an absolute one, or
    {"rel": seconds, "end": bool} relative to the start (or the end). The action does not
    matter here: DISPLAY, AUDIO and EMAIL all ring on the desktop."""
    for name, params, value in props:
        if name != "TRIGGER":
            continue
        if params.get("VALUE") == "DATE-TIME" or "T" in value and value.strip()[:1].isdigit():
            when = local_datetime(value, params)
            return {"at": when.strftime("%Y-%m-%dT%H:%M")} if when else None
        secs = parse_duration(value)
        if secs is None:
            return None
        return {"rel": secs, "end": params.get("RELATED", "START").upper() == "END"}
    return None


def parse_rrule(value):
    rule = {}
    for part in value.split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            rule[k.upper()] = v
    return rule if "FREQ" in rule else None


def entry_of(kind, props):
    """One stored entry from a component's properties, or None when it has no date."""
    e = {"kind": "todo" if kind == "VTODO" else "event", "uid": "", "summary": "", "description": "",
         "start": None, "time": "", "span": 1, "rrule": None, "exdates": [], "done": False,
         "alarms": [], "minutes": 0, "end": ""}
    end = None
    due = None
    start_dt = end_dt = None
    duration = None
    for name, params, value in props:
        if name == "UID":
            e["uid"] = value
        elif name == "SUMMARY":
            e["summary"] = unescape(value).strip()
        elif name == "DESCRIPTION":
            e["description"] = unescape(value).strip()
        elif name == "DTSTART":
            d, t = to_local(value, params)
            if d:
                e["start"], e["time"] = d.isoformat(), t
                start_dt = local_datetime(value, params) if t else None
        elif name == "DUE" and kind == "VTODO":
            d, t = to_local(value, params)
            if d:
                due = (d.isoformat(), t)
        elif name == "DTEND" and kind == "VEVENT":
            d, t = to_local(value, params)
            end = (d, t)
            end_dt = local_datetime(value, params) if t else None
        elif name == "DURATION":
            duration = parse_duration(value)
        elif name == "VALARM":
            alarm = alarm_of(value)
            if alarm:
                e["alarms"].append(alarm)
        elif name == "RRULE":
            e["rrule"] = parse_rrule(value)
        elif name == "EXDATE":
            for v in value.split(","):
                d, _ = to_local(v, params)
                if d:
                    e["exdates"].append(d.isoformat())
        elif name == "STATUS" and kind == "VTODO":
            e["done"] = value.upper() == "COMPLETED"
        elif name == "COMPLETED" and kind == "VTODO":
            e["done"] = True
    if kind == "VTODO" and due:
        # A task is shown on the day it is due; DTSTART is when it may be started.
        e["start"], e["time"] = due
    if e["start"] is None:
        return None
    if end and end[0] and not e["time"]:
        # All-day events end on the day after their last day (exclusive).
        span = (end[0] - dt.date.fromisoformat(e["start"])).days
        e["span"] = max(1, span)
    # A timed entry's length, for alarms set off its end and for the text of a note.
    if e["time"]:
        if start_dt and end_dt:
            e["minutes"] = max(0, int((end_dt - start_dt).total_seconds() // 60))
            if end_dt.date() == start_dt.date():
                e["end"] = end_dt.strftime("%H:%M")
        elif duration:
            e["minutes"] = max(0, duration // 60)
    return e


def parse_ics(text):
    out = []
    for kind, props in components(text):
        e = entry_of(kind, props)
        if e:
            out.append(e)
    return out


WEEKDAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]


def last_day(d):
    return (d.replace(day=28) + dt.timedelta(days=4)).replace(day=1) - dt.timedelta(days=1)


def matches(rule, start, d):
    """Does a date fall on the rule anchored at `start`? FREQ, INTERVAL, BYDAY (weekly;
    monthly with an ordinal such as 2MO or -1FR), BYMONTHDAY, BYMONTH — what calendars
    actually hand out: weekly meetings, monthly bills, yearly birthdays."""
    interval = max(1, int(rule.get("INTERVAL", "1") or 1))
    freq = rule["FREQ"].upper()
    byday = [x for x in rule.get("BYDAY", "").upper().split(",") if x]
    bymonthday = [int(x) for x in rule.get("BYMONTHDAY", "").split(",") if x.lstrip("-").isdigit()]
    bymonth = [int(x) for x in rule.get("BYMONTH", "").split(",") if x.isdigit()]
    if freq == "DAILY":
        return (d - start).days % interval == 0
    if freq == "WEEKLY":
        week = lambda x: (x - dt.timedelta(days=x.weekday())).toordinal() // 7
        if (week(d) - week(start)) % interval != 0:
            return False
        days = byday or [WEEKDAYS[start.weekday()]]
        return WEEKDAYS[d.weekday()] in days
    if freq == "MONTHLY":
        months = (d.year - start.year) * 12 + d.month - start.month
        if months % interval != 0:
            return False
        if byday:
            for spec in byday:
                m = re.fullmatch(r"([+-]?\d+)?([A-Z]{2})", spec)
                if not m or m.group(2) != WEEKDAYS[d.weekday()]:
                    continue
                if not m.group(1):
                    return True
                n = int(m.group(1))
                if n > 0 and (d.day - 1) // 7 + 1 == n:
                    return True
                if n < 0 and (last_day(d).day - d.day) // 7 + 1 == -n:
                    return True
            return False
        if bymonthday:
            return d.day in bymonthday or d.day - last_day(d).day - 1 in bymonthday
        return d.day == start.day
    if freq == "YEARLY":
        if (d.year - start.year) % interval != 0:
            return False
        if bymonth and d.month not in bymonth:
            return False
        if not bymonth and d.month != start.month:
            return False
        return d.day == (bymonthday[0] if bymonthday else start.day)
    return False


def occurrences(e, lo, hi):
    """Start dates of the entry's occurrences within [lo, hi]. A rule is walked day by
    day from its first occurrence, so COUNT and UNTIL are honoured; EXDATE removes."""
    start = dt.date.fromisoformat(e["start"])
    rule = e.get("rrule")
    if not rule:
        return [start] if start <= hi and start + dt.timedelta(days=e.get("span", 1)) > lo else []
    count = int(rule["COUNT"]) if rule.get("COUNT", "").isdigit() else None
    until = None
    if rule.get("UNTIL"):
        until, _ = to_local(rule["UNTIL"], {})
    out, n, d = [], 0, start
    last = min(hi, until) if until else hi
    steps = 0
    while d <= last and steps < 20000:
        steps += 1
        if d == start or matches(rule, start, d):
            n += 1
            if count and n > count:
                break
            if d + dt.timedelta(days=e.get("span", 1)) > lo and d.isoformat() not in e["exdates"]:
                out.append(d)
        d += dt.timedelta(days=1)
    return out


def fold(line):
    out, cur = [], ""
    for ch in line:
        if len((cur + ch).encode("utf-8")) > 74:
            out.append(cur)
            cur = " " + ch
        else:
            cur += ch
    out.append(cur)
    return "\r\n".join(out)


def note_uid(date):
    return f"plaincalendar-{date}@{socket.gethostname() or 'host'}"


def own_uid(date, uid):
    """The uid a set or delete works on. None or "" is the day's first note (the one
    uid the widget had before a day could hold several), "new" a fresh one; anything
    else must be a note of yours on that day — the widget never touches other entries."""
    if not uid:
        return note_uid(date)
    if uid == "new":
        return f"plaincalendar-{date}-{secrets.token_hex(3)}@{socket.gethostname() or 'host'}"
    if not uid.startswith(f"plaincalendar-{date}") or "/" in uid or len(uid) > 200:
        raise DavError(f"not a note of yours on {date}: {uid!r}")
    return uid


HEAD_RE = re.compile(r"^(!?)\s*(\d{1,2})[:.](\d{2})(?:\s*[-\u2013\u2014]\s*(\d{1,2})[:.](\d{2}))?(?:\s+(.*))?$")


def parse_head(line):
    """The first line of a note: ("!" or "", start (h, m) or None, end (h, m) or None,
    the summary). "14:30 Dentist", "9.00-10.30 Standup", "!Buy milk", or plain text."""
    m = HEAD_RE.match(line.strip())
    if m:
        bang, h1, m1, h2, m2, rest = m.groups()
        start = (int(h1), int(m1))
        end = (int(h2), int(m2)) if h2 is not None else None
        if start[0] < 24 and start[1] < 60 and (end is None or (end[0] < 24 and end[1] < 60)):
            return bang, start, end, (rest or "").strip()
    if line.strip().startswith("!"):
        return "!", None, None, line.strip()[1:].strip()
    return "", None, None, line.strip()


def parse_hour(value, fallback=(9, 0)):
    m = re.fullmatch(r"(\d{1,2})[:.](\d{2})", str(value or "").strip())
    if m and int(m.group(1)) < 24 and int(m.group(2)) < 60:
        return int(m.group(1)), int(m.group(2))
    return fallback


def own_ics(date, text, uid=None, lead=10, hour="09:00"):
    """The widget's note as iCalendar: an all-day event, or a timed one when the first
    line starts with a time; the rest of that line is the summary, the other lines the
    description. A timed note gets a VALARM `lead` minutes before (none when lead < 0);
    "!" on an all-day note sets one at `hour` of its day."""
    day = dt.date.fromisoformat(date)
    lines = [l.rstrip() for l in text.strip().split("\n")]
    bang, start, end, summary = parse_head(lines[0] if lines else "")
    description = "\n".join(lines[1:]).strip()
    props = [
        "BEGIN:VCALENDAR", "VERSION:2.0", f"PRODID:{PRODID}",
        "BEGIN:VEVENT",
        f"UID:{uid or note_uid(date)}",
        "DTSTAMP:" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
    ]
    alarm = None
    if start:
        begins = dt.datetime(day.year, day.month, day.day, start[0], start[1])
        ends = dt.datetime(day.year, day.month, day.day, end[0], end[1]) if end else begins + dt.timedelta(hours=1)
        if ends <= begins:
            ends = begins + dt.timedelta(hours=1)
        props += ["DTSTART:" + utc_stamp(begins), "DTEND:" + utc_stamp(ends)]
        if lead is not None and lead >= 0:
            alarm = "TRIGGER:-PT%dM" % lead if lead > 0 else "TRIGGER:PT0S"
    else:
        props += ["DTSTART;VALUE=DATE:" + day.strftime("%Y%m%d"),
                  "DTEND;VALUE=DATE:" + (day + dt.timedelta(days=1)).strftime("%Y%m%d")]
        if bang:
            h, mi = parse_hour(hour)
            alarm = "TRIGGER;VALUE=DATE-TIME:" + utc_stamp(dt.datetime(day.year, day.month, day.day, h, mi))
    props.append("SUMMARY:" + escape(summary))
    if description:
        props.append("DESCRIPTION:" + escape(description))
    if alarm:
        props += ["BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:" + escape(summary or "plaincalendar"),
                  alarm, "END:VALARM"]
    props += ["END:VEVENT", "END:VCALENDAR"]
    return "\r\n".join(fold(p) for p in props) + "\r\n"


def own_text(e):
    """The text of the widget's own note as the editor shows it: the time or the "!"
    back in front of the summary, the description below."""
    head = ""
    if e.get("time"):
        head = e["time"]
        if e.get("end") and e.get("minutes", 60) != 60:
            head += "-" + e["end"]
        head += " "
    elif e.get("alarms"):
        head = "!"
    text = head + e.get("summary", "")
    if e.get("description"):
        text += "\n" + e["description"]
    return text


def is_own(e):
    return e.get("uid", "").startswith("plaincalendar-")


# ── Accounts and caches ───────────────────────────────────────────────────────
def load_accounts():
    if not ACCOUNTS.exists():
        return []
    try:
        data = json.loads(ACCOUNTS.read_text(encoding="utf-8"))
        return [a for a in data if isinstance(a, dict) and a.get("id")] if isinstance(data, list) else []
    except (json.JSONDecodeError, OSError):
        return []


def save_accounts(accounts):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = ACCOUNTS.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(accounts, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(ACCOUNTS)


def take_inbox(account_id):
    """The secrets the settings page left for one account, hex-encoded; then forgotten."""
    if not INBOX.exists():
        return {}
    cp = configparser.ConfigParser(interpolation=None)
    cp.optionxform = str
    try:
        cp.read(INBOX, encoding="utf-8")
    except (configparser.Error, OSError):
        INBOX.unlink(missing_ok=True)
        return {}
    found = {}
    if cp.has_section(account_id):
        for k in SECRET_KEYS:
            value = cp.get(account_id, k, fallback="")
            try:
                if value:
                    found[k] = bytes.fromhex(value).decode("utf-8")
            except ValueError:
                pass
        cp.remove_section(account_id)
    if cp.sections():
        with open(INBOX, "w", encoding="utf-8") as f:
            cp.write(f)
        os.chmod(INBOX, 0o600)
    else:
        INBOX.unlink(missing_ok=True)
    return found


def public(account):
    out = {k: v for k, v in account.items() if k not in SECRET_KEYS}
    out["has_password"] = bool(account.get("password"))
    out["signed_in"] = bool(account.get("refresh_token"))
    return out


def cache_path(account_id):
    return CACHE_DIR / (re.sub(r"[^A-Za-z0-9_.-]", "_", account_id) + ".json")


def load_cache(account_id):
    p = cache_path(account_id)
    if not p.exists():
        return {"fetched": "", "entries": [], "error": "", "calendar": ""}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {"fetched": "", "entries": [], "error": "", "calendar": ""}


def save_cache(account_id, cache):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = cache_path(account_id).with_suffix(".tmp")
    tmp.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")
    tmp.replace(cache_path(account_id))


# ── The local account: a vdir ─────────────────────────────────────────────────
def local_entries():
    out = []
    if LOCAL_DIR.exists():
        for p in sorted(LOCAL_DIR.glob("*.ics")):
            try:
                for e in parse_ics(p.read_text(encoding="utf-8")):
                    e["href"] = p.name
                    out.append(e)
            except OSError:
                pass
    return out


def local_set(date, text, lead=10, hour="09:00", uid=None):
    uid = uid or note_uid(date)
    LOCAL_DIR.mkdir(parents=True, exist_ok=True)
    (LOCAL_DIR / f"{uid}.ics").write_text(own_ics(date, text, uid, lead, hour), encoding="utf-8")


def local_delete(date, uid=None):
    p = LOCAL_DIR / f"{uid or note_uid(date)}.ics"
    if p.exists():
        p.unlink()


# ── HTTP and CalDAV ───────────────────────────────────────────────────────────
class DavError(Exception):
    pass


def http_request(method, url, body=None, headers=None):
    """One request with redirects followed by hand, same method and body: urllib would
    turn a redirected PROPFIND into a GET, and iCloud redirects the principal to another
    host. Returns (status, lowercase headers, text, final url)."""
    headers = dict(headers or {})
    headers.setdefault("User-Agent", "plaincalendar/0.2")
    if body is not None:
        body = body.encode("utf-8") if isinstance(body, str) else body
        headers["Content-Length"] = str(len(body))
    for _ in range(6):
        u = urllib.parse.urlsplit(url)
        conn_cls = http.client.HTTPSConnection if u.scheme == "https" else http.client.HTTPConnection
        conn = conn_cls(u.hostname, u.port, timeout=TIMEOUT)
        path = (u.path or "/") + ("?" + u.query if u.query else "")
        try:
            conn.request(method, path, body=body, headers=headers)
            resp = conn.getresponse()
            data = resp.read()
        except (OSError, http.client.HTTPException, ssl.SSLError) as ex:
            raise DavError(f"{method} {u.hostname}: {ex}") from ex
        finally:
            conn.close()
        if resp.status in (301, 302, 307, 308) and resp.getheader("Location"):
            url = urllib.parse.urljoin(url, resp.getheader("Location"))
            continue
        return resp.status, {k.lower(): v for k, v in resp.getheaders()}, data.decode("utf-8", "replace"), url
    raise DavError("too many redirects")


class Dav:
    """A thin CalDAV client: PROPFIND discovery, calendar-query REPORT, PUT and DELETE
    with etags. Basic auth, or a Google bearer token refreshed when it expires."""

    def __init__(self, account):
        self.account = account
        self.base = account.get("url", "").strip()
        if not self.base:
            raise DavError("no server URL")

    def auth_header(self):
        a = self.account
        if a.get("kind") == "google":
            return "Bearer " + google_token(a)
        cred = f"{a.get('user', '')}:{a.get('password', '')}".encode("utf-8")
        return "Basic " + base64.b64encode(cred).decode("ascii")

    def request(self, method, url, body=None, headers=None):
        headers = dict(headers or {})
        headers["Authorization"] = self.auth_header()
        if body is not None:
            headers.setdefault("Content-Type", "application/xml; charset=utf-8")
        status, resp_headers, text, final = http_request(method, url, body, headers)
        if status == 401:
            raise DavError("the server refused the login (401)")
        if status == 403:
            raise DavError("the server refused the request (403)")
        return status, resp_headers, text, final

    def propfind(self, url, props, depth):
        body = ('<?xml version="1.0" encoding="utf-8"?>'
                f'<d:propfind xmlns:d="{DAV}" xmlns:c="{CAL}"><d:prop>{props}</d:prop></d:propfind>')
        status, _, text, final = self.request("PROPFIND", url, body, {"Depth": str(depth)})
        if status not in (207, 200):
            raise DavError(f"PROPFIND {url}: HTTP {status}")
        return parse_multistatus(text), final

    def discover(self):
        """The calendars of the account: [{href, name, components}], hrefs absolute."""
        responses, final = self.propfind(self.base, "<d:current-user-principal/>", 0)
        principal = None
        for href, props in responses:
            p = props.get(f"{{{DAV}}}current-user-principal")
            if p is not None:
                h = p.find(f"{{{DAV}}}href")
                if h is not None and h.text:
                    principal = urllib.parse.urljoin(final, h.text.strip())
        if not principal:
            raise DavError("the server did not name a principal — is the URL the CalDAV root?")
        responses, final = self.propfind(principal, "<c:calendar-home-set/>", 0)
        home = None
        for href, props in responses:
            p = props.get(f"{{{CAL}}}calendar-home-set")
            if p is not None:
                h = p.find(f"{{{DAV}}}href")
                if h is not None and h.text:
                    home = urllib.parse.urljoin(final, h.text.strip())
        if not home:
            raise DavError("the principal has no calendar home")
        responses, final = self.propfind(
            home, "<d:resourcetype/><d:displayname/><c:supported-calendar-component-set/>", 1)
        calendars = []
        for href, props in responses:
            rt = props.get(f"{{{DAV}}}resourcetype")
            if rt is None or rt.find(f"{{{CAL}}}calendar") is None:
                continue
            name = props.get(f"{{{DAV}}}displayname")
            comps = props.get(f"{{{CAL}}}supported-calendar-component-set")
            kinds = [c.get("name") for c in comps] if comps is not None else []
            calendars.append({"href": urllib.parse.urljoin(final, href),
                              "name": (name.text or "").strip() if name is not None and name.text else href.rstrip("/").split("/")[-1],
                              "components": kinds})
        return calendars

    def query(self, calendar, comp, start=None, end=None):
        """The entries of one component kind, each (href, etag, ics text)."""
        rng = ""
        if start and end:
            rng = f'<c:time-range start="{start.strftime("%Y%m%dT000000Z")}" end="{end.strftime("%Y%m%dT000000Z")}"/>'
        body = ('<?xml version="1.0" encoding="utf-8"?>'
                f'<c:calendar-query xmlns:d="{DAV}" xmlns:c="{CAL}">'
                '<d:prop><d:getetag/><c:calendar-data/></d:prop>'
                f'<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="{comp}">{rng}</c:comp-filter></c:comp-filter></c:filter>'
                '</c:calendar-query>')
        status, _, text, final = self.request("REPORT", calendar, body, {"Depth": "1"})
        if status not in (207, 200):
            raise DavError(f"REPORT {calendar}: HTTP {status}")
        out = []
        for href, props in parse_multistatus(text):
            data = props.get(f"{{{CAL}}}calendar-data")
            etag = props.get(f"{{{DAV}}}getetag")
            if data is not None and data.text:
                out.append((urllib.parse.urljoin(final, href),
                            (etag.text or "").strip() if etag is not None else "", data.text))
        return out

    def put(self, href, ics, etag=""):
        headers = {"Content-Type": "text/calendar; charset=utf-8"}
        headers["If-Match" if etag else "If-None-Match"] = etag or "*"
        status, resp_headers, _, _ = self.request("PUT", href, ics, headers)
        if status not in (200, 201, 204):
            raise DavError(f"PUT {href}: HTTP {status}")
        return resp_headers.get("etag", "")

    def delete(self, href, etag=""):
        headers = {"If-Match": etag} if etag else {}
        status, _, _, _ = self.request("DELETE", href, None, headers)
        if status not in (200, 202, 204, 404):
            raise DavError(f"DELETE {href}: HTTP {status}")


def parse_multistatus(text):
    """[(href, {tag: Element})] from a multistatus body, successful propstats only."""
    try:
        root = ET.fromstring(text)
    except ET.ParseError as ex:
        raise DavError(f"the server's answer is not XML: {ex}") from ex
    out = []
    for resp in root.iter(f"{{{DAV}}}response"):
        href = (resp.findtext(f"{{{DAV}}}href") or "").strip()
        props = {}
        for ps in resp.findall(f"{{{DAV}}}propstat"):
            status = ps.findtext(f"{{{DAV}}}status") or ""
            if status and " 200 " not in status + " ":
                continue
            prop = ps.find(f"{{{DAV}}}prop")
            if prop is not None:
                for child in prop:
                    props[child.tag] = child
        out.append((href, props))
    return out


# ── Google: OAuth for the same CalDAV ─────────────────────────────────────────
GOOGLE_AUTH = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN = "https://oauth2.googleapis.com/token"
GOOGLE_SCOPE = "https://www.googleapis.com/auth/calendar"


def post_form(url, fields):
    body = urllib.parse.urlencode(fields)
    status, _, text, _ = http_request("POST", url, body, {"Content-Type": "application/x-www-form-urlencoded"})
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        parsed = {}
    if status != 200:
        raise DavError(f"Google token endpoint: HTTP {status} {parsed.get('error', '')} {parsed.get('error_description', '')}".strip())
    return parsed


def google_token(account):
    """A valid access token, refreshed through the stored refresh token when expired."""
    now = dt.datetime.now(dt.timezone.utc).timestamp()
    if account.get("access_token") and account.get("expires_at", 0) > now + 60:
        return account["access_token"]
    if not account.get("refresh_token"):
        raise DavError("no Google login yet — run: notes.py google-auth " + account.get("id", ""))
    tok = post_form(GOOGLE_TOKEN, {"client_id": account.get("client_id", ""), "client_secret": account.get("client_secret", ""),
                                   "refresh_token": account["refresh_token"], "grant_type": "refresh_token"})
    account["access_token"] = tok.get("access_token", "")
    account["expires_at"] = now + int(tok.get("expires_in", 3600))
    accounts = load_accounts()
    for i, a in enumerate(accounts):
        if a.get("id") == account.get("id"):
            accounts[i] = account
    save_accounts(accounts)
    return account["access_token"]


def google_auth(account):
    """The one-off login: a browser consent page, the code caught on a local port, the
    refresh token stored in the account."""
    if not account.get("client_id") or not account.get("client_secret"):
        raise DavError("the account needs client_id and client_secret from a Google Cloud OAuth client (Desktop app)")
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    redirect = f"http://127.0.0.1:{port}/"
    state = secrets.token_urlsafe(16)
    url = GOOGLE_AUTH + "?" + urllib.parse.urlencode({
        "client_id": account["client_id"], "redirect_uri": redirect, "response_type": "code",
        "scope": GOOGLE_SCOPE, "access_type": "offline", "prompt": "consent", "state": state})
    got = {}

    class Catch(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
            got["code"] = q.get("code", [""])[0]
            got["state"] = q.get("state", [""])[0]
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write("plaincalendar: signed in, this tab can be closed.\n".encode("utf-8"))

        def log_message(self, *args):
            pass

    print("Open this page in a browser and allow the access:\n" + url, flush=True)
    try:
        subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass
    with http.server.HTTPServer(("127.0.0.1", port), Catch) as srv:
        srv.timeout = 300
        srv.handle_request()
    if got.get("state") != state or not got.get("code"):
        raise DavError("no code came back from the browser")
    tok = post_form(GOOGLE_TOKEN, {"code": got["code"], "client_id": account["client_id"],
                                   "client_secret": account["client_secret"], "redirect_uri": redirect,
                                   "grant_type": "authorization_code"})
    if not tok.get("refresh_token"):
        raise DavError("Google returned no refresh token — remove the app's access in the Google account and try again")
    account["refresh_token"] = tok["refresh_token"]
    account["access_token"] = tok.get("access_token", "")
    account["expires_at"] = dt.datetime.now(dt.timezone.utc).timestamp() + int(tok.get("expires_in", 3600))
    return account


# ── Fetching ──────────────────────────────────────────────────────────────────
def plain_get(url):
    status, _, text, _ = http_request("GET", url)
    if status != 200:
        raise DavError(f"GET {url}: HTTP {status}")
    return text


def calendar_of(account, dav):
    """The calendar href to read and write: the account's own, or the first found."""
    if account.get("calendar"):
        return urllib.parse.urljoin(dav.base, account["calendar"])
    calendars = dav.discover()
    events = [c for c in calendars if not c["components"] or "VEVENT" in c["components"]]
    if not events:
        raise DavError("no calendar found on the server")
    return events[0]["href"]


def refresh(account, lo, hi):
    """Fetch an account into its cache; the error, if any, is stored with it."""
    cache = load_cache(account["id"])
    cache["error"] = ""
    try:
        if account.get("kind") == "ics":
            entries = parse_ics(plain_get(account.get("url", "")))
            for e in entries:
                e["href"], e["etag"] = "", ""
            cache["calendar"] = account.get("url", "")
        else:
            dav = Dav(account)
            calendar = calendar_of(account, dav)
            cache["calendar"] = calendar
            entries = []
            # A wide window: a recurring event's master lies before the window, and
            # servers match it by its occurrences inside the range.
            for href, etag, ics in dav.query(calendar, "VEVENT", lo - dt.timedelta(days=366), hi):
                for e in parse_ics(ics):
                    e["href"], e["etag"] = href, etag
                    entries.append(e)
            for href, etag, ics in dav.query(calendar, "VTODO"):
                for e in parse_ics(ics):
                    if e["kind"] == "todo":
                        e["href"], e["etag"] = href, etag
                        entries.append(e)
        cache["entries"] = entries
        cache["fetched"] = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    except DavError as ex:
        cache["error"] = str(ex)
    except Exception as ex:                       # never let one account take the rest down
        cache["error"] = f"{type(ex).__name__}: {ex}"
    save_cache(account["id"], cache)
    return cache


# ── The document the widget reads ─────────────────────────────────────────────
def lead_of(e):
    """Minutes the first alarm rings before the start — what the sticker's "remind" row
    shows for a note of yours; -1 when no alarm counts from the start."""
    for a in e.get("alarms") or []:
        if a and "rel" in a and not a.get("end") and a["rel"] <= 0:
            return int(-a["rel"] // 60)
    return -1


def shown(e, account_id, day):
    return {"account": account_id, "uid": e.get("uid", ""), "kind": e["kind"],
            "summary": e.get("summary", ""), "description": e.get("description", ""),
            "time": e.get("time", ""), "end": e.get("end", ""), "done": bool(e.get("done")),
            "own": is_own(e), "alarm": bool(e.get("alarms")), "lead": lead_of(e),
            "text": own_text(e) if is_own(e) else "",
            "date": day.isoformat(), "start": e["start"]}


# ── Reminders ─────────────────────────────────────────────────────────────────
def load_state():
    if REMINDERS.exists():
        try:
            st = json.loads(REMINDERS.read_text(encoding="utf-8"))
            if isinstance(st, dict):
                return {"acked": dict(st.get("acked") or {}), "snoozed": dict(st.get("snoozed") or {})}
        except (json.JSONDecodeError, OSError):
            pass
    return {"acked": {}, "snoozed": {}}


def save_state(st):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = REMINDERS.with_suffix(".tmp")
    tmp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
    tmp.replace(REMINDERS)


def prune_state(st, now):
    """Acknowledgements and snoozes older than a week go; so do claim files."""
    limit = (now - dt.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M")
    st["acked"] = {k: v for k, v in st["acked"].items() if str(v) >= limit}
    st["snoozed"] = {k: v for k, v in st["snoozed"].items() if str(v) >= limit}
    if CLAIMS.exists():
        cutoff = (now - dt.timedelta(days=3)).timestamp()
        for p in CLAIMS.iterdir():
            try:
                if p.stat().st_mtime < cutoff:
                    p.unlink()
            except OSError:
                pass


def alarm_options(lead=10, hour="09:00", events=True, missed=12, alarms=True):
    return {"lead": lead, "hour": hour, "events": events, "missed": missed, "alarms": alarms}


def alarm_times(e, day, opts):
    """When an entry's occurrence on `day` rings, local datetimes. A VALARM relative to
    the start of an all-day entry counts from `hour` of its day, not midnight — the hour
    a phone would use; one relative to the end counts from the end of a timed entry.
    Without a VALARM, an account's timed entry rings `lead` minutes before, when asked."""
    h, mi = parse_hour(opts["hour"])
    if e.get("time"):
        t = dt.datetime.strptime(e["time"], "%H:%M").time()
        start = dt.datetime.combine(day, t)
    else:
        start = dt.datetime.combine(day, dt.time(h, mi))
    out = []
    for a in e.get("alarms", []):
        if "at" in a:
            try:
                out.append(dt.datetime.strptime(a["at"], "%Y-%m-%dT%H:%M"))
            except ValueError:
                pass
        else:
            anchor = start + dt.timedelta(minutes=e.get("minutes", 0)) if a.get("end") and e.get("time") else start
            out.append(anchor + dt.timedelta(seconds=int(a.get("rel", 0))))
    # The accounts' timed entries without a VALARM; a note of yours says for itself —
    # "none" in the sticker writes it without one, and it must stay silent.
    if (not e.get("alarms") and e.get("time") and not is_own(e) and opts.get("events")
            and opts.get("lead", -1) is not None and opts["lead"] >= 0):
        out.append(start - dt.timedelta(minutes=opts["lead"]))
    return out


def alarm_key(account_id, e, day, i, when):
    """An alarm as acknowledged, snoozed and claimed: the entry, the occurrence, the
    alarm's index — and the time it is due by the data, so a note rewritten to another
    time (the day's first note keeps its uid) rings again after an old "done"."""
    return f"{account_id}|{e.get('uid', '')}|{day.isoformat()}|{i}|{when.strftime('%Y%m%dT%H%M')}"


def alarms_for(sources, now, opts, st):
    """The alarms due between `missed` hours ago and 36 hours ahead, acknowledged ones
    left out, snoozed ones at their new time, sorted by time."""
    if not opts.get("alarms", True):
        return []
    lo = now - dt.timedelta(hours=max(0, opts.get("missed", 12)))
    hi = now + dt.timedelta(hours=36)
    out = []
    for account_id, cache in sources:
        for e in cache.get("entries", []):
            if e["kind"] == "todo" and e.get("done"):
                continue
            # An alarm may precede its day (-P1D) or follow a snooze into the next one.
            for o in occurrences(e, lo.date() - dt.timedelta(days=2), hi.date() + dt.timedelta(days=1)):
                for i, when in enumerate(alarm_times(e, o, opts)):
                    key = alarm_key(account_id, e, o, i, when)
                    if key in st["acked"]:
                        continue
                    if key in st["snoozed"]:
                        try:
                            when = dt.datetime.strptime(st["snoozed"][key], "%Y-%m-%dT%H:%M")
                        except ValueError:
                            pass
                    if lo <= when <= hi:
                        item = shown(e, account_id, o)
                        item.update({"key": key, "at": when.strftime("%Y-%m-%dT%H:%M"),
                                     "snoozed": key in st["snoozed"]})
                        out.append(item)
    out.sort(key=lambda x: (x["at"], x["summary"]))
    return out


def build(accounts, lo, hi, upcoming_n, caches, opts=None):
    days, ahead = {}, {}
    today = dt.date.today()
    far = max(hi, today + dt.timedelta(days=180))
    opts = opts or alarm_options()

    def add(day, item, into):
        into.setdefault(day.isoformat(), []).append(item)

    sources = [("local", {"entries": local_entries()})]
    sources += [(a["id"], caches.get(a["id"]) or load_cache(a["id"])) for a in accounts]
    for account_id, cache in sources:
        for e in cache.get("entries", []):
            for o in occurrences(e, lo, far):
                for k in range(e.get("span", 1)):
                    day = o + dt.timedelta(days=k)
                    if lo <= day <= hi:
                        add(day, shown(e, account_id, day), days)
                    if day >= today and k == 0:
                        add(day, shown(e, account_id, day), ahead)
    order = lambda x: (0 if x["own"] else 1, x["kind"] == "todo", x["time"] or "~", x["summary"])
    for key in days:
        days[key].sort(key=order)
    upcoming = []
    for key in sorted(ahead):
        for item in sorted(ahead[key], key=order):
            if item["kind"] == "todo" and item["done"]:
                continue
            upcoming.append(item)
            if len(upcoming) >= upcoming_n:
                break
        if len(upcoming) >= upcoming_n:
            break
    state = [{"id": "local", "name": "local", "kind": "local", "ok": True, "error": "", "fetched": ""}]
    for a in accounts:
        c = caches.get(a["id"]) or load_cache(a["id"])
        state.append({"id": a["id"], "name": a.get("name") or a["id"], "kind": a.get("kind", "caldav"),
                      "ok": not c.get("error") and bool(c.get("fetched")), "error": c.get("error", ""),
                      "fetched": c.get("fetched", "")})
    now = dt.datetime.now()
    return {"generated": now.isoformat(timespec="seconds"), "today": today.isoformat(),
            "from": lo.isoformat(), "to": hi.isoformat(), "accounts": state, "days": days, "upcoming": upcoming,
            "alarms": alarms_for(sources, now, opts, load_state())}


def window(frm=None, to=None):
    """The default window: the previous month's first day to the next month's last."""
    today = dt.date.today()
    lo = dt.date.fromisoformat(frm) if frm else (today.replace(day=1) - dt.timedelta(days=1)).replace(day=1)
    hi = dt.date.fromisoformat(to) if to else last_day((today.replace(day=28) + dt.timedelta(days=4)).replace(day=1))
    return lo, hi


def due(cache, minutes):
    if not cache.get("fetched"):
        return True
    try:
        then = dt.datetime.fromisoformat(cache["fetched"])
    except ValueError:
        return True
    return (dt.datetime.now(dt.timezone.utc) - then).total_seconds() >= minutes * 60


def find_account(accounts, account_id):
    for a in accounts:
        if a.get("id") == account_id:
            return a
    raise DavError(f"no account {account_id!r}")


def set_note(accounts, account_id, date, text, lead=10, hour="09:00", uid=None):
    try:
        dt.date.fromisoformat(date)
    except ValueError as ex:
        raise DavError(f"not a date: {date}") from ex
    uid = own_uid(date, uid)
    if account_id == "local":
        if text.strip():
            local_set(date, text, lead, hour, uid)
        else:
            local_delete(date, uid)
        return
    account = find_account(accounts, account_id)
    if account.get("kind") == "ics":
        raise DavError("an ICS link is read-only")
    dav = Dav(account)
    calendar = calendar_of(account, dav)
    cache = load_cache(account_id)
    existing = next((e for e in cache.get("entries", []) if e.get("uid") == uid and e.get("href")), None)
    if text.strip():
        href = existing["href"] if existing else calendar.rstrip("/") + "/" + uid + ".ics"
        dav.put(href, own_ics(date, text, uid, lead, hour), existing.get("etag", "") if existing else "")
    elif existing:
        dav.delete(existing["href"], existing.get("etag", ""))


def complete_todo(accounts, account_id, uid):
    """Mark a task done on its server: the resource is fetched, STATUS:COMPLETED and the
    completion stamp put in, and it goes back with If-Match on the etag."""
    account = find_account(accounts, account_id)
    if account.get("kind") == "ics":
        raise DavError("an ICS link is read-only")
    cache = load_cache(account_id)
    e = next((x for x in cache.get("entries", []) if x.get("uid") == uid and x.get("href")), None)
    if e is None or e.get("kind") != "todo":
        raise DavError(f"no task {uid!r} in {account_id}")
    dav = Dav(account)
    status, headers, text, _ = dav.request("GET", urllib.parse.urljoin(dav.base, e["href"]))
    if status != 200:
        raise DavError(f"GET {e['href']}: HTTP {status}")
    etag = headers.get("etag", e.get("etag", ""))
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    # Each VTODO is taken whole — its UID may come after its STATUS — and only the one
    # asked for is rewritten; the others in the resource stay as they were.
    out, todo = [], None
    for line in unfold(text):
        name, _, value = split_line(line)
        if name == "BEGIN" and value.upper() == "VTODO":
            todo = [line]
            continue
        if todo is not None:
            todo.append(line)
            if name == "END" and value.upper() == "VTODO":
                mine = any(split_line(l)[0] == "UID" and split_line(l)[2] == uid for l in todo)
                if mine:
                    body = [l for l in todo[1:-1] if split_line(l)[0] not in ("STATUS", "COMPLETED", "PERCENT-COMPLETE")]
                    todo = [todo[0]] + body + ["STATUS:COMPLETED", f"COMPLETED:{stamp}", "PERCENT-COMPLETE:100", todo[-1]]
                out += todo
                todo = None
            continue
        out.append(line)
    dav.put(urllib.parse.urljoin(dav.base, e["href"]), "\r\n".join(fold(l) for l in out) + "\r\n", etag)


def claim(key):
    """The first instance of the widget to ask gets the alarm; the others do not. One
    file per key, created exclusively."""
    CLAIMS.mkdir(parents=True, exist_ok=True)
    name = re.sub(r"[^A-Za-z0-9_.@-]", "_", key)[:200]
    try:
        fd = os.open(CLAIMS / name, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        return False
    os.close(fd)
    return True


def emit(obj):
    json.dump(obj, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


def main(argv):
    ap = argparse.ArgumentParser(prog="notes.py", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    # The alarm options go with every command that prints a document, so the widget's
    # settings reach the schedule whichever command refreshed it.
    alarms = argparse.ArgumentParser(add_help=False)
    alarms.add_argument("--lead", type=int, default=10)
    alarms.add_argument("--hour", default="09:00")
    alarms.add_argument("--no-events", dest="events", action="store_false")
    alarms.add_argument("--missed", type=int, default=12)
    alarms.add_argument("--no-alarms", dest="alarms", action="store_false")
    alarms.add_argument("--upcoming", type=int, default=5)
    for name in ("sync", "dump"):
        p = sub.add_parser(name, parents=[alarms])
        p.add_argument("--from", dest="frm")
        p.add_argument("--to")
        if name == "sync":
            p.add_argument("--every", type=int, default=15)
            p.add_argument("--force", action="store_true")
    p = sub.add_parser("set", parents=[alarms]); p.add_argument("account"); p.add_argument("date"); p.add_argument("b64")
    p.add_argument("--uid", default="")
    p = sub.add_parser("delete", parents=[alarms]); p.add_argument("account"); p.add_argument("date")
    p.add_argument("--uid", default="")
    p = sub.add_parser("ack", parents=[alarms]); p.add_argument("key")
    p = sub.add_parser("snooze", parents=[alarms]); p.add_argument("key"); p.add_argument("when")
    p = sub.add_parser("claim"); p.add_argument("key")
    p = sub.add_parser("done", parents=[alarms]); p.add_argument("account"); p.add_argument("uid"); p.add_argument("key", nargs="?", default="")
    sub.add_parser("accounts")
    p = sub.add_parser("account-save"); p.add_argument("b64")
    p = sub.add_parser("account-remove"); p.add_argument("id")
    p = sub.add_parser("check"); p.add_argument("id")
    p = sub.add_parser("google-auth"); p.add_argument("id")
    args = ap.parse_args(argv)
    # The folder holds the passwords and the page's inbox: 700, whoever created it.
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(CONFIG_DIR, 0o700)
    accounts = load_accounts()
    opts = (alarm_options(args.lead, args.hour, args.events, args.missed, args.alarms)
            if hasattr(args, "lead") else alarm_options())

    try:
        if args.cmd in ("sync", "dump"):
            lo, hi = window(args.frm, args.to)
            caches = {}
            if args.cmd == "sync":
                for a in accounts:
                    cache = load_cache(a["id"])
                    if args.force or due(cache, args.every):
                        cache = refresh(a, lo, hi)
                    caches[a["id"]] = cache
                st = load_state()
                prune_state(st, dt.datetime.now())
                save_state(st)
            emit(build(accounts, lo, hi, args.upcoming, caches, opts))
        elif args.cmd in ("set", "delete"):
            text = base64.b64decode(args.b64).decode("utf-8") if args.cmd == "set" else ""
            set_note(accounts, args.account, args.date, text, args.lead, args.hour, args.uid)
            lo, hi = window()
            if args.account != "local":
                refresh(find_account(accounts, args.account), lo, hi)
            emit(build(accounts, lo, hi, args.upcoming, {}, opts))
        elif args.cmd in ("ack", "snooze"):
            st = load_state()
            now = dt.datetime.now()
            if args.cmd == "ack":
                st["acked"][args.key] = now.strftime("%Y-%m-%dT%H:%M")
                st["snoozed"].pop(args.key, None)
            else:
                if re.fullmatch(r"\d+", args.when):
                    when = now + dt.timedelta(minutes=int(args.when))
                else:
                    when = dt.datetime.strptime(args.when[:16], "%Y-%m-%dT%H:%M")
                st["snoozed"][args.key] = when.strftime("%Y-%m-%dT%H:%M")
                st["acked"].pop(args.key, None)
            save_state(st)
            lo, hi = window()
            emit(build(accounts, lo, hi, args.upcoming, {}, opts))
        elif args.cmd == "claim":
            emit({"ok": True, "key": args.key, "claimed": claim(args.key)})
        elif args.cmd == "done":
            complete_todo(accounts, args.account, args.uid)
            if args.key:
                st = load_state()
                st["acked"][args.key] = dt.datetime.now().strftime("%Y-%m-%dT%H:%M")
                save_state(st)
            lo, hi = window()
            refresh(find_account(accounts, args.account), lo, hi)
            emit(build(accounts, lo, hi, args.upcoming, {}, opts))
        elif args.cmd == "accounts":
            emit([public(a) for a in accounts])
        elif args.cmd == "account-save":
            new = json.loads(base64.b64decode(args.b64).decode("utf-8"))
            if not isinstance(new, dict) or not new.get("id") or new["id"] == "local":
                raise DavError("an account needs an id other than local")
            new["id"] = re.sub(r"[^A-Za-z0-9_.-]", "_", new["id"])
            new.update(take_inbox(new["id"]))
            old = next((a for a in accounts if a.get("id") == new["id"]), None)
            if old:
                # A secret left empty in the form keeps the stored one.
                for k in SECRET_KEYS + ("expires_at",):
                    if not new.get(k) and old.get(k):
                        new[k] = old[k]
                accounts[accounts.index(old)] = new
            else:
                accounts.append(new)
            save_accounts(accounts)
            emit([public(a) for a in accounts])
        elif args.cmd == "account-remove":
            accounts = [a for a in accounts if a.get("id") != args.id]
            save_accounts(accounts)
            p = cache_path(args.id)
            if p.exists():
                p.unlink()
            emit([public(a) for a in accounts])
        elif args.cmd == "check":
            a = find_account(accounts, args.id)
            if a.get("kind") == "ics":
                emit({"ok": True, "calendars": [], "entries": len(parse_ics(plain_get(a.get("url", ""))))})
            else:
                emit({"ok": True, "calendars": Dav(a).discover()})
        elif args.cmd == "google-auth":
            a = find_account(accounts, args.id)
            accounts[accounts.index(a)] = google_auth(a)
            save_accounts(accounts)
            print("  ✓ signed in; the refresh token is stored in " + str(ACCOUNTS))
    except (DavError, ValueError, binascii.Error) as ex:
        # A bad date, a bad base64, a bad JSON: one line for the widget, never a traceback.
        emit({"ok": False, "error": str(ex)})
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
