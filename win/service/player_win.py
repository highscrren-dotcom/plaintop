#!/usr/bin/env python3
"""The System Media Transport Controls as the fields the player view reads.

On Plasma, player/shared/PlayerView.qml reads one row of Plasma's Mpris2Model — identity,
desktopEntry, track, artist, album, length and position in microseconds, rate,
playbackStatus, the canGoNext/canGoPrevious/canPlay/canPause flags — and calls Previous,
PlayPause, Next and updatePosition on it. On Windows the same facts live in the System
Media Transport Controls (SMTC), which every player that shows up in the volume flyout
feeds: Spotify, the browsers, the Media Player, foobar2000 with its component. The service
reads the SMTC and serves them in the /player shape of PROTOCOL.md; the Mpris2Model shim
in win/host fills its rows from that.

    snapshot()                        → {"players": [...], "current": i, "backend": "winrt"}
    command("Spotify.exe", "Next")    → True when the session took the command

WinRT is reached through the `winsdk` package, or the newer split `winrt-*` packages that
carry the same classes under `winrt.windows.media.control`. Every WinRT call runs on one
dedicated thread with its own asyncio loop (Manager, below), started on first use: the HTTP
server answers from several threads, and WinRT objects want the thread that made them. The
snapshot is cached and refreshed at most every REFRESH seconds — two hosts poll once a
second each — and a position is extrapolated from the session's last_updated_time while it
plays, as the view itself counts on between its own queries.

Without winsdk (Linux, or not installed) the module imports all the same: snapshot() lists
no players and says "backend": "none", command() answers False. set_backend() takes any
object with sessions(), current_id() and command(id, name) — the stand's fake — and the
WinRT side is one such backend, so the mapping is tested where WinRT is not.

A backend's sessions() returns one dict per session with the SMTC's own values untouched:

    {"id": AUMID, "title": "…", "artist": "…", "album": "…",
     "status": 0–5 (CLOSED, OPENED, CHANGING, STOPPED, PLAYING, PAUSED), "rate": 1.0 or None,
     "position": timedelta, "start": timedelta, "end": timedelta, "updated": aware datetime,
     "next": bool, "previous": bool, "play": bool, "pause": bool}
"""
import asyncio
import datetime as dt
import importlib
import sys
import threading
import time

# GlobalSystemMediaTransportControlsSessionPlaybackStatus → the view's Mpris.PlaybackStatus
# (0 unknown, 1 stopped, 2 paused, 3 playing). CHANGING is the moment between two states,
# which MPRIS has no word for: unknown, and the view draws no bar for it.
STATUS = {0: 1, 1: 1, 2: 0, 3: 1, 4: 3, 5: 2}
PLAYING = 4
COMMANDS = ("Previous", "PlayPause", "Next", "Position")
REFRESH = 0.5       # seconds the cached sessions are served before the SMTC is asked again
TIMEOUT = 3.0       # seconds a WinRT call may take before it counts as failed
# An extrapolation over more than this is not one: a session that never updated its timeline
# reports 1601-01-01, and a position counted from there would only hit the clamp.
STALE = 86400.0


def clock():
    """Now, aware and in UTC — what the SMTC's last_updated_time is compared with. A module
    function rather than a call in place, so the stand can hold the clock still."""
    return dt.datetime.now(dt.timezone.utc)


# ── The mapping ───────────────────────────────────────────────────────────────
def identity(aumid):
    """A readable player name from an Application User Model ID. A packaged app's reads
    `Publisher.Name_hash!Entry`, and the entry point is the name people know ("Spotify");
    an app whose entry is the generic "App" is named after its package. A desktop app's
    AUMID is its executable, "chrome.exe": the name without the suffix, and the last
    dotted part of a reverse-DNS name ("org.videolan.VLC")."""
    aumid = str(aumid or "")
    if "!" in aumid:
        family, _, entry = aumid.rpartition("!")
        if entry and entry.lower() != "app":
            return entry.rsplit(".", 1)[-1]
        return family.split("_", 1)[0].rsplit(".", 1)[-1] or aumid
    name = aumid.replace("\\", "/").rsplit("/", 1)[-1]
    if name.lower().endswith(".exe"):
        name = name[:-4]
    return name.rsplit(".", 1)[-1] or aumid


def micros(value):
    """A timedelta (or seconds) as whole microseconds; nothing is 0."""
    if value is None:
        return 0
    if isinstance(value, dt.timedelta):
        return value // dt.timedelta(microseconds=1)
    return int(float(value) * 1000000)


def to_player(raw, now):
    """One backend session as the row the view reads. The position is counted on from the
    moment the session last reported it, at the playback rate, while it plays."""
    aumid = str(raw.get("id") or "")
    status = STATUS.get(int(raw.get("status") or 0), 0)
    rate = raw.get("rate")
    rate = 1.0 if rate is None else float(rate)
    start = micros(raw.get("start"))
    length = max(0, micros(raw.get("end")) - start)
    position = max(0, micros(raw.get("position")) - start)
    updated = raw.get("updated")
    if int(raw.get("status") or 0) == PLAYING and isinstance(updated, dt.datetime):
        if updated.tzinfo is None:
            updated = updated.replace(tzinfo=dt.timezone.utc)
        elapsed = (now - updated).total_seconds()
        if 0 <= elapsed <= STALE:
            position += int(elapsed * rate * 1000000)
    if length > 0:
        position = min(position, length)
    return {
        "id": aumid,
        "identity": identity(aumid),
        "desktopEntry": aumid.lower(),
        "track": str(raw.get("title") or ""),
        "artist": str(raw.get("artist") or ""),
        "album": str(raw.get("album") or ""),
        "length": length,
        "position": position,
        "rate": rate,
        "playbackStatus": status,
        "canGoNext": bool(raw.get("next")),
        "canGoPrevious": bool(raw.get("previous")),
        "canPlay": bool(raw.get("play")),
        "canPause": bool(raw.get("pause")),
    }


# ── The WinRT backend ─────────────────────────────────────────────────────────
def control_module():
    """windows.media.control from whichever projection is installed, else None. Anything
    going wrong in the import counts as absence: a broken projection serves no better."""
    for name in ("winsdk.windows.media.control", "winrt.windows.media.control"):
        try:
            return importlib.import_module(name)
        except Exception:
            continue
    return None


def init_apartment():
    """WinRT wants the thread's COM apartment declared. winsdk and winrt name the call
    differently, and either may have declared it already — hence the silence on failure."""
    for module, attr in (("winsdk._winrt", "ApartmentType"), ("winrt.system", "ApartmentType")):
        try:
            mod = importlib.import_module(module)
            mod.init_apartment(getattr(mod, attr).MULTI_THREADED)
            return
        except Exception:
            continue


class Manager:
    """The WinRT side: one thread, one asyncio loop, the session manager requested once and
    kept. Each public method blocks its caller for the call, TIMEOUT at most, and raises
    when the call fails — snapshot() turns that into an empty list and a line on stderr."""
    name = "winrt"

    def __init__(self, control):
        self._control = control
        self._loop = None
        self._manager = None
        self._lock = threading.Lock()

    def _start(self):
        with self._lock:
            if self._loop is not None:
                return
            loop = asyncio.new_event_loop()
            ready = threading.Event()

            def run():
                init_apartment()
                asyncio.set_event_loop(loop)
                ready.set()
                loop.run_forever()

            threading.Thread(target=run, name="smtc", daemon=True).start()
            ready.wait(TIMEOUT)
            self._loop = loop

    def _call(self, coro):
        self._start()
        return asyncio.run_coroutine_threadsafe(coro, self._loop).result(TIMEOUT)

    async def _mgr(self):
        if self._manager is None:
            klass = self._control.GlobalSystemMediaTransportControlsSessionManager
            self._manager = await klass.request_async()
        return self._manager

    async def _read(self, session):
        try:
            props = await session.try_get_media_properties_async()
        except Exception:       # a session closing under us still has a status to show
            props = None
        info = session.get_playback_info()
        line = session.get_timeline_properties()
        controls = info.controls
        return {
            "id": session.source_app_user_model_id,
            "title": getattr(props, "title", "") or "",
            "artist": getattr(props, "artist", "") or "",
            "album": getattr(props, "album_title", "") or "",
            "status": int(info.playback_status),
            "rate": info.playback_rate,
            "position": line.position,
            "start": line.start_time,
            "end": line.end_time,
            "updated": line.last_updated_time,
            "next": bool(controls.is_next_enabled),
            "previous": bool(controls.is_previous_enabled),
            "play": bool(controls.is_play_enabled),
            "pause": bool(controls.is_pause_enabled),
        }

    async def _sessions(self):
        out = []
        for session in (await self._mgr()).get_sessions():
            try:
                out.append(await self._read(session))
            except Exception:
                continue
        return out

    async def _current(self):
        session = (await self._mgr()).get_current_session()
        return session.source_app_user_model_id if session is not None else None

    async def _command(self, session_id, name):
        for session in (await self._mgr()).get_sessions():
            if session.source_app_user_model_id != session_id:
                continue
            if name == "Next":
                return bool(await session.try_skip_next_async())
            if name == "Previous":
                return bool(await session.try_skip_previous_async())
            if name == "PlayPause":
                return bool(await session.try_toggle_play_pause_async())
            # Position: the timeline is read fresh with the next snapshot, which command()
            # below forces; there is nothing to ask the session for.
            return True
        return False

    def sessions(self):
        return self._call(self._sessions())

    def current_id(self):
        return self._call(self._current())

    def command(self, session_id, name):
        return self._call(self._command(session_id, name))


# ── The module's state ────────────────────────────────────────────────────────
_lock = threading.Lock()
_backend = None
_backend_name = "none"
_cache = {"stamp": -1.0, "sessions": [], "current": None}


def winrt_backend():
    control = control_module()
    return Manager(control) if control is not None else None


def set_backend(obj):
    """Any object with sessions(), current_id() and command(id, name). None means the
    WinRT one where winsdk is installed, and no backend at all elsewhere."""
    global _backend, _backend_name
    with _lock:
        _backend = obj if obj is not None else winrt_backend()
        if _backend is None:
            _backend_name = "none"
        else:
            _backend_name = str(getattr(_backend, "name", "") or type(_backend).__name__.lower())
        _cache.update(stamp=-1.0, sessions=[], current=None)


set_backend(None)


def snapshot():
    """The /player answer. The backend is asked at most every REFRESH seconds; between two
    readings the same sessions are served with their positions counted on."""
    with _lock:
        backend, name = _backend, _backend_name
        if backend is None:
            return {"players": [], "current": -1, "backend": "none"}
        stamp = time.monotonic()
        if _cache["stamp"] < 0 or stamp - _cache["stamp"] >= REFRESH:
            try:
                sessions = list(backend.sessions())
                current = backend.current_id()
            except Exception as ex:
                print(f"player_win: {type(ex).__name__}: {ex}", file=sys.stderr)
                sessions, current = [], None
            _cache.update(stamp=stamp, sessions=sessions, current=current)
        sessions, current = list(_cache["sessions"]), _cache["current"]
    now = clock()
    players = [to_player(s, now) for s in sessions]
    index = -1
    if current is not None:
        index = next((i for i, p in enumerate(players) if p["id"] == str(current)), -1)
    return {"players": players, "current": index, "backend": name}


def command(session_id, name):
    """Previous, PlayPause, Next or Position for one session; True when it was taken.
    Whatever the answer, the next snapshot reads the SMTC anew — the state has changed,
    or a fresh position was asked for."""
    if name not in COMMANDS:
        return False
    with _lock:
        backend = _backend
    if backend is None:
        return False
    try:
        taken = bool(backend.command(str(session_id), name))
    except Exception as ex:
        print(f"player_win: {name}: {type(ex).__name__}: {ex}", file=sys.stderr)
        taken = False
    with _lock:
        _cache["stamp"] = -1.0
    return taken


if __name__ == "__main__":
    import json
    json.dump(snapshot(), sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
