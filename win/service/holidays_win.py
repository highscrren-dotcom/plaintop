#!/usr/bin/env python3
"""Holidays for the calendar on Windows, from the `holidays` package: /holidays of PROTOCOL.md.

On Plasma the calendar takes its holidays from KHolidays through Plasma's calendar plugin
(Holidays.qml), and tells a day off from any other entry by name, through HolidayKinds.js.
Windows has no KHolidays; the `holidays` package (pip) knows about as many countries, with
subdivisions, translated names and the day-off question answered by the package itself:
its default category, "public", is the days off, and the other categories a country has —
observances, school holidays, half days, the bank's and the government's days — are what
Plasma's "every holiday" mode shows.

    regions("ru")                          → [{"code": "DE", "name": "Germany", "subdivisions": […],
                                              "languages": ["de", "en_US", …]}, …]
    month(["RU", "DE-BY"], 2026, 10, "de") → {"days": {"2026-10-03": [{"title": "Tag der
                                              Deutschen Einheit", "public": True}]}, "unknown": []}

Regions are ISO codes with an optional subdivision (DE-BY), not KHolidays' plan names.
A name's language is the one asked for when the country has it, else the country's own —
never the process environment's, which the package would otherwise consult. The package
does not translate country names and the standard library cannot, so `name` is English
unless Babel happens to be installed.

    python3 win/service/holidays_win.py --compare ru_ru de_de us_en-us

maps KHolidays plan names to package codes and lists the package's day-off names of a year
next to HolidayKinds.js PUBLIC — the check that both sides spell the days off alike.
Without the package every call degrades: regions() is empty, month() lists every region as
unknown and says why.
"""
import datetime as dt
import functools
import json
import re
import sys
from pathlib import Path

try:
    import holidays
    from holidays import registry
except ImportError:
    holidays = None
    registry = None

try:
    from babel import Locale
except ImportError:
    Locale = None

PUBLIC = "public"
KINDS = Path(__file__).resolve().parents[2] / "calendar" / "package" / "contents" / "ui" / "HolidayKinds.js"


# ── Names ─────────────────────────────────────────────────────────────────────
@functools.lru_cache(maxsize=None)
def english_names():
    """ISO code → the country's English name, from the package's registry: the class is
    named UnitedStates, IsleOfMan — spaced out, the small words lowered."""
    out = {}
    if registry is None:
        return out
    for entry in registry.COUNTRIES.values():
        klass, code = entry[0], entry[1]
        words = re.findall(r"[A-Z][a-z]*|[0-9]+", klass)
        words = [w if i == 0 or w not in ("And", "Of", "The") else w.lower() for i, w in enumerate(words)]
        out[code] = " ".join(words)
    return out


def country_name(code, lang):
    if Locale is not None and lang:
        try:
            name = Locale.parse(lang.replace("-", "_")).territories.get(code)
            if name:
                return str(name)
        except Exception:
            pass
    return english_names().get(code, code)


def regions(lang=""):
    """Every country the package knows, with the subdivision codes it takes and the
    languages it can name the holidays in (empty: the country's own only)."""
    if holidays is None:
        return []
    languages = holidays.list_localized_countries(include_aliases=False)
    out = []
    for code, subs in sorted(holidays.list_supported_countries(include_aliases=False).items()):
        out.append({"code": code, "name": country_name(code, str(lang or "")),
                    "subdivisions": list(subs), "languages": list(languages.get(code, []))})
    return out


# ── The month ─────────────────────────────────────────────────────────────────
def pick_language(entity, lang):
    """The language to ask the package for: the country's code for `lang` — exactly, or
    the first with that prefix ("en" finds en_US; the package itself takes a bare "en" as
    unknown, verified 2026-10-04) — else the country's own. Never None: that makes the
    package read LANGUAGE/LC_ALL, which on a service machine means whatever the account
    happens to have."""
    supported = tuple(entity.supported_languages or ())
    lang = str(lang or "").replace("-", "_")
    for candidate in (lang, lang.split("_")[0]):
        if not candidate:
            continue
        if candidate in supported:
            return candidate
        for code in supported:
            if code.startswith(candidate + "_"):
                return code
    return entity.default_language


def entity(code, sub):
    """country_holidays for a code, or None when the package does not know it. Subdivisions
    are tried as written, then upper-cased: the ISO codes are upper, the aliases ("Bayern")
    are not."""
    for subdiv in dict.fromkeys((sub, sub.upper())) if sub else (None,):
        try:
            return holidays.country_holidays(code, subdiv=subdiv or None)
        except (NotImplementedError, KeyError, ValueError):
            continue
    return None


@functools.lru_cache(maxsize=256)
def region_month(code, year, month, lang):
    """((date, title, public), …) for one region and month, or None for an unknown code.
    Two readings of the package: the days off (its default category) and every other
    category the country has, whose names are days off only when the first reading has
    them too — a country may list the same day under both."""
    cc, _, sub = code.strip().upper().partition("-")
    base = entity(cc, sub.strip())
    if base is None:
        return None
    language = pick_language(base, lang)
    kwargs = {"subdiv": base.subdiv, "years": year, "language": language}
    public = holidays.country_holidays(cc, **kwargs)
    others = tuple(c for c in base.supported_categories if c != PUBLIC)
    extra = holidays.country_holidays(cc, categories=others, **kwargs) if others else None
    out = []
    day = dt.date(year, month, 1)
    while day.month == month:
        off = sorted(set(public.get_list(day))) if day in public else []
        out.extend((day.isoformat(), title, True) for title in off)
        if extra is not None and day in extra:
            out.extend((day.isoformat(), title, False)
                       for title in sorted(set(extra.get_list(day))) if title not in off)
        day += dt.timedelta(days=1)
    return tuple(out)


def month(regions, year, month, lang=""):
    """The /holidays answer: the month's days with their holidays, a title once per day
    (a day off wins over the same name as an observance), days off first, then by title."""
    if holidays is None:
        return {"days": {}, "unknown": [str(r) for r in regions], "error": "the holidays package is not installed"}
    days, unknown = {}, []
    for code in regions:
        code = str(code).strip()
        if not code:
            continue
        entries = region_month(code, int(year), int(month), str(lang or ""))
        if entries is None:
            unknown.append(code)
            continue
        for key, title, public in entries:
            entry = next((e for e in days.setdefault(key, []) if e["title"] == title), None)
            if entry is None:
                days[key].append({"title": title, "public": public})
            else:
                entry["public"] = entry["public"] or public
    for entries in days.values():
        entries.sort(key=lambda e: (not e["public"], e["title"]))
    return {"days": {k: days[k] for k in sorted(days) if days[k]}, "unknown": unknown}


# ── The comparison with KHolidays' spelling ───────────────────────────────────
def kinds_public():
    """The PUBLIC names of HolidayKinds.js — one JSON array on the line that declares it."""
    for line in KINDS.read_text(encoding="utf-8").splitlines():
        if line.startswith("var PUBLIC = "):
            return set(json.loads(line[len("var PUBLIC = "):].rstrip(";")))
    raise SystemExit(f"  ✗ no PUBLIC list in {KINDS}")


def plan_to_region(plan):
    """A KHolidays plan name → (country code, subdivision, language). The plans are named
    holiday_<country>[-<region>]_<lang>[-<variant>]: us_en-us, de-by_de, ca_fr-ca."""
    name = plan[len("holiday_"):] if plan.startswith("holiday_") else plan
    region, _, lang = name.partition("_")
    cc, _, sub = region.upper().partition("-")
    base, _, variant = lang.replace("-", "_").partition("_")
    return cc, sub, base.lower() + ("_" + variant.upper() if variant else "")


def compare(plans, year=2026):
    if holidays is None:
        raise SystemExit("  ✗ the holidays package is not installed")
    known = kinds_public()
    total = matched = 0
    for plan in plans:
        cc, sub, lang = plan_to_region(plan)
        base = entity(cc, sub)
        if base is None:
            print(f"  {plan}: the package knows no {cc}{'-' + sub if sub else ''}")
            continue
        language = pick_language(base, lang)
        days = holidays.country_holidays(cc, subdiv=base.subdiv, years=year, language=language)
        names = sorted({n for d in days for n in days.get_list(d)})
        hits = [n for n in names if n in known]
        code = cc + ("-" + sub if sub else "")
        print(f"  {plan} → {code}, names in {language}: {len(hits)} of {len(names)} day-off names of {year} are in HolidayKinds.js PUBLIC")
        for n in names:
            print("    " + ("✓ " if n in known else "✗ ") + n)
        total += len(names)
        matched += len(hits)
    print(f"  {matched} of {total} names match exactly")
    return matched, total


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--compare":
        compare(sys.argv[2:] or ["ru_ru", "de_de", "us_en-us"])
    elif len(sys.argv) > 1 and sys.argv[1] == "--regions":
        json.dump(regions(sys.argv[2] if len(sys.argv) > 2 else ""), sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
    else:
        # python3 holidays_win.py RU,DE-BY 2026 10 de
        codes = sys.argv[1].split(",") if len(sys.argv) > 1 else ["RU"]
        today = dt.date.today()
        year = int(sys.argv[2]) if len(sys.argv) > 2 else today.year
        mon = int(sys.argv[3]) if len(sys.argv) > 3 else today.month
        json.dump(month(codes, year, mon, sys.argv[4] if len(sys.argv) > 4 else ""), sys.stdout, ensure_ascii=False, indent=1)
        sys.stdout.write("\n")
