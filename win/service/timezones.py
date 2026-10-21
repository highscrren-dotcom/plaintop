#!/usr/bin/env python3
"""A time zone's offset and city for the weather view: the /time endpoint of PROTOCOL.md.

On Plasma the weather asks the time engine two things (WeatherView.qml): the "Timezone
City" of the zone "Local" — the part after the region, "Yekaterinburg", to guess a place
on a first run — and the "Offset" of the zone the place is in, daylight time included,
read once a minute so a change under a running shell is picked up. Here both come from
zoneinfo:

    info("Europe/Berlin")   → {"zone": "Europe/Berlin", "offset": 7200, "city": "Berlin"}
    info("Local")           → the machine's zone, named by tzlocal when it is installed

Windows has no /usr/share/zoneinfo: zoneinfo there reads the `tzdata` pip package, which
the service's requirements name. Without it, or for a name nobody knows, the answer
degrades the way the time engine's does (a name it does not know gets the machine's offset,
verified on Plasma 2026-09-23): the local offset and no city.
"""
import datetime as dt

try:
    import zoneinfo
except ImportError:         # Python < 3.9
    zoneinfo = None

try:
    import tzlocal
except ImportError:
    tzlocal = None


def local_offset():
    """The machine's current UTC offset in seconds, from the C library's notion of local time."""
    return int(dt.datetime.now().astimezone().utcoffset().total_seconds())


def local_name():
    """The machine's zone as an IANA name — tzlocal maps the Windows registry's name to one —
    or "" when tzlocal is not installed."""
    if tzlocal is None:
        return ""
    try:
        return str(tzlocal.get_localzone_name() or "")
    except Exception:
        return ""


def city(zone):
    """The last part of an IANA name with its underscores as spaces. A name without a
    region ("UTC", "EST") or in the Etc/ family ("Etc/GMT+5") names no place, and the
    weather's lookup would only fail on it."""
    if "/" not in zone or zone.startswith("Etc/"):
        return ""
    return zone.rsplit("/", 1)[-1].replace("_", " ").strip()


def info(zone):
    zone = str(zone or "").strip()
    name = local_name() if zone == "Local" else zone
    tz = None
    if name and zoneinfo is not None:
        try:
            tz = zoneinfo.ZoneInfo(name)
        except Exception:   # unknown, malformed, or no tzdata on this machine
            tz = None
    if tz is None:
        # "Local" without tzlocal keeps the machine's offset and names no city; an unknown
        # zone is treated the same, as the time engine treats it.
        offset = local_offset()
        return {"zone": zone, "offset": offset, "city": city(name) if zone == "Local" else ""}
    offset = int(dt.datetime.now(tz).utcoffset().total_seconds())
    return {"zone": zone, "offset": offset, "city": city(name)}


if __name__ == "__main__":
    import json
    import sys
    for arg in sys.argv[1:] or ["Local"]:
        print(json.dumps(info(arg), ensure_ascii=False))
