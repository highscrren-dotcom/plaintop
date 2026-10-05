# The Windows service: what it serves and what the hosts expect

English only: a protocol for people writing code against it. The user-facing pages are
[README.md](README.md) · [README.ru.md](README.ru.md).

One Python process, `win/service/`, listens on `http://127.0.0.1:8788` (HTTP/1.1,
keep-alive, the relay's port — `spectrum/relay.py` is its model and the `/bands` protocol is
the same byte for byte). It owns every reading, every secret and every setting; the QML
hosts in `win/host/` only draw, and reach it with `XMLHttpRequest`. Nothing but the hosts
is meant to talk to it, and the reasons it exists are in decision 17 of
[../docs/DECISIONS.md](../docs/DECISIONS.md).

## Vocabulary: the service speaks ksystemstats

The shared QML of the monitor — `monitor/shared/MonitorData.qml`, `SensorRegistry.qml` —
asks Plasma's sensor daemon for ids like `cpu/all/usage`. On Windows the same files run
unchanged behind QML-only shim modules (`win/host/imports/org/kde/…`), so the service
publishes the same ids with the same units:

| id | unit | from |
|---|---|---|
| `cpu/all/usage`, `cpu/cpuN/usage` | % | psutil |
| `cpu/cpuN/frequency` | MHz | psutil (one value for every core) |
| `cpu/cpuN/temperature` | °C | LibreHardwareMonitor, when it runs; else absent |
| `cpu/all/cpuCount` | physical processors | WMI once |
| `cpu/all/coreCount` | logical processors (the number of `cpuN`) | psutil |
| `cpu/loadaverages/loadaverage1\|5\|15` | runnable tasks | `psutil.getloadavg()` |
| `memory/physical/used`, `total` | bytes | psutil |
| `memory/physical/usedPercent` | % | psutil |
| `memory/swap/used`, `total` | bytes | psutil (the page file) |
| `os/system/hostname`, `os/system/name`, `os/kernel/version` | text | `platform` |
| `os/system/uptime` | seconds | psutil |
| `network/<iface>/download`, `upload` | bytes/s | psutil, rates from two readings |
| `network/<iface>/totalDownload`, `totalUpload` | bytes | psutil |
| `network/<iface>/ipv4address`, `ipv4gateway`, `ipv6gateway` | text | psutil, `route print` once |
| `network/<iface>/signal` | % | `netsh wlan show interfaces`, Wi-Fi only |
| `gpu/gpuN/usage`, `temperature`, `usedVram`, `totalVram`, `power`, `name` | %, °C, bytes, bytes, W, text | LibreHardwareMonitor |
| `disk/all/read`, `write`, `disk/<name>/read`, `write` | bytes/s | psutil |
| `power/<battery>/chargePercentage`, `chargeRate`, `charge`, `capacity`, `health` | %, W (+ charging), Wh, Wh, % | psutil + WMI `Win32_Battery` |
| `lmsensors/<chip>/fanN`, `lmsensors/<chip>/tempN` | rpm, °C | LibreHardwareMonitor: `<chip>` is the hardware's name slugged, the sensor's own name travels in `name` |

`pressure/*` does not exist on Windows and is never listed, so the pressure block hides
itself as it does on a kernel without PSI. Interfaces are the connected hardware ones,
loopback and virtual adapters left out, under their Windows names (`Ethernet`, `Wi-Fi`).

LibreHardwareMonitor is read from its own web server, `http://localhost:8085/data.json`
(*Options → Remote Web Server* in LHM), every 2 s when it answers; without it the
temperatures, fans and GPU sensors are simply absent, and the lines that need them say
nothing — the same behaviour as a Linux machine without `lm_sensors`.

## Endpoints

All answers are JSON (`application/json; charset=utf-8`) unless said otherwise. `GET`
reads; `POST` takes a JSON body. Errors come as HTTP 4xx/5xx with `{"error": "…"}`.

### Writes are protected

Anything that runs a command, writes a note or changes a setting takes a token: the
header `X-Plaintop-Token: <token>`. The service makes the token at start, writes it to
`%LOCALAPPDATA%\plaintop\token` (readable by this user only) and hands it to every host
it starts as a command-line argument (`-- --token …`); a host reads
`Qt.application.arguments`. A request carrying an `Origin` header — a browser's — is
refused whatever it asks. `GET` endpoints that only read need no token. The server binds
`127.0.0.1` only.

### `/bands?bars=N&mono=1` · `GET`, `text/plain`

The relay's protocol, unchanged: one line of integers 0–1000 separated by commas, `N` of
them. The capture is WASAPI loopback of the default output (`win/service/bands.py`); the
frame is kept in cava's stereo order — the left channel from its highest band down to its
lowest, then the right from lowest to highest — so `fold_mono` and `resample` are
imported from `spectrum/relay.py` and `spectrum/shared/Spectrum.qml` needs no change.
Silence for a second is served as zeros. `/state` answers `{"frames", "restarts",
"source", "age", "bars", "fps", "backend"}` as the relay does, plus the capture backend,
`libraries` (each capture library by name, `true` where it imports or the text of what
its import raised — a frozen exe packed without the library and a desk without a sound
device look the same otherwise), `candidates` (the outputs the backend can choose from),
`prefer` (`PLAINTOP_CAPTURE`), `scan` (what the idle capture heard on the outputs it
tried, newest last: `[{"source": "Speakers (Realtek)", "peak": 0.31}, …]`), `rate` (frames
a second actually produced over the last five), `input_peak` (the last block's largest
sample, 0–1: 0.009 is −41 dBFS, the system volume at a few percent), `gain_db` and
`gain_max_db` (where the automatic gain stands against its ceiling).

### `/devices?seconds=0.4` · `GET`

The reconnaissance of a dark ring: every output's loopback listened to for `seconds`
(0.1–2) — `{"outputs": [{"name", "default", "peak", "error"}], "capture": <the /state
dict>}`. `peak` is the largest sample magnitude heard: 0.0 is silence, anything above
about 0.01 is sound rendered on that output. Ask it while the music plays.

### `/monitor` · `GET`

Everything the monitor's shims read, in one answer, refreshed once a second on the
service's own clock:

```json
{
  "stamp": 1760000000.123,
  "sensors": {
    "cpu/all/usage": {"value": 12.5},
    "cpu/cpu0/temperature": {"value": 54.0, "name": "CPU Core #1"},
    "os/system/hostname": {"value": "DESKTOP-1"}
  },
  "processes": [["chrome.exe", 3.1, 734003200, 1234], …],
  "coreCount": 16
}
```

`sensors` lists only ids that exist on this machine (this is also the sensor tree for
`SensorRegistry`); `value` is a number or a string, `name` the sensor's own label when it
has one. The GPU ids (`gpu/gpuN/usage`, `name`, `usedVram`, `totalVram`, and
`temperature`, `power` where a source has them) come from LibreHardwareMonitor when it
runs, else from `win/service/gpu_win.py`: the `GPU Engine` and `GPU Adapter Memory`
performance counters (Task Manager's reading — the busiest engine type, summed over
processes) joined to the cards DXGI lists by LUID (`IDXGIFactory1::EnumAdapters1`: the
name, the dedicated memory, the shared limit, the software adapter left out), the
temperature and power from `nvidia-smi` where it is, matched by the card's name. An
integrated GPU's "VRAM" is its shared usage against DXGI's shared limit, as Task Manager
shows it. The registry's display class is the fallback where DXGI cannot be asked. `processes` are `[name, cpu %, memory bytes, pid]` — the union of the thirty
heaviest by CPU and by memory, unsorted: the `KSortFilterProxyModel` shim sorts.

### `/exec` · `POST` `{"command": "…"}` → `{"stdout": "…", "stderr": "…", "exit code": 0}`

The executable engine's protocol. `MonitorData.qml` builds Linux command lines; the
service recognises the ones the monitor is known to run and answers them in the same
output format from Windows sources, and runs anything else through `cmd.exe /c` with a
10-second timeout (a `command` block of the user's own):

| command line (as MonitorData builds it) | answered from |
|---|---|
| `cat /sys/devices/system/node/node*/cpulist` | one line per NUMA node, `0-15` |
| `LC_ALL=C lscpu` | `Model name:`, `Socket(s):`, `Core(s) per socket:`, `Thread(s) per core:` lines |
| `cat …/board_vendor …/board_name …/bios_version …` | three lines from the registry's `HARDWARE\DESCRIPTION\System\BIOS` |
| `cat /proc/loadavg` | `psutil.getloadavg()` |
| `timeout 5 df -B1 --output=target,size,used,pcent MOUNTS` | a header line, then `target size used N%` per mount; `/` means the system drive, `D:` or `D:\` a drive |
| `bash …/services.sh` | `docker\|running\|total` when docker answers, `ollama\|…` as the script, `winget\|N` pending upgrades (cached 30 min) |
| `bash …/health.sh N` | `failed\|<automatic services not running>\|0`, `err\|<System log errors since boot>\|<Application log errors>`, up to N `errline\|<source>\|<message>` newest first, `reboot\|yes` from the Windows Update / CBS reboot keys |
| `bash …/units.sh [--user] 'svc' …` | `svc\|state` with running → active, stopped → inactive, start_pending → activating, stop_pending → deactivating, unknown → inactive |
| `bash …/sound.sh [input]` | `sink\|name\|volume%\|muted` (and `source\|…`) through pycaw when installed, else nothing |
| `bash …/repos.sh 'path' …` | `name\|branch\|dirty\|ahead\|behind` or `name\|notgit`, git in PATH |
| `bash …/peripherals.sh` | `model\|percentage\|state` of Bluetooth devices reporting a battery (PowerShell, cached 60 s), else nothing |

The service tells them apart by the script's base name and the first word, never by the
directory, so the hosts may live anywhere. Quoting follows POSIX `sh` (`shlex`): that is
what the shared QML writes.

### `/player` · `GET`

The System Media Transport Controls, in the fields `player/shared/PlayerView.qml` reads
from Plasma's `Mpris2Model` (the shim fills a model from this):

```json
{"players": [{"id": "Spotify.exe", "identity": "Spotify", "desktopEntry": "spotify",
              "track": "…", "artist": "…", "album": "…", "length": 213000000,
              "position": 42000000, "rate": 1.0, "playbackStatus": 3,
              "canGoNext": true, "canGoPrevious": true, "canPlay": false, "canPause": true}],
 "current": 0}
```

Times are microseconds, as MPRIS has them; `playbackStatus` is 0 unknown, 1 stopped,
2 paused, 3 playing; `current` is the index of the session Windows calls current, −1
with none. `POST /player {"id": "Spotify.exe", "command": "PlayPause"}` with `Previous`,
`PlayPause`, `Next` or `Position` (asks the session for a fresh position) → `{"ok": true}`.

### `/notes` · `POST` `{"args": ["sync", "--every", "15", …]}` → `{"stdout": "…", "exit code": 0}`

Runs `calendar/package/contents/code/notes.py` with those arguments, in the service's
process, one at a time. The arguments are the script's own (its docstring); nothing is
quoted, nothing passes through a shell, and the text of a note travels base64 inside the
JSON body as the script expects. The script's paths on Windows: `%APPDATA%\plaincalendar`
for the accounts and the local notes, `%LOCALAPPDATA%\plaincalendar` for the caches.

### `/notify` · `POST` `{"title": "…", "text": "…", "sound": "path or builtin name"}` → `{"ok": true, "toast": true, "sound": true}`

The calendar's reminder outside its sheet — what `notify-send` and `pw-play` do on Plasma.
The toast goes through PowerShell's WinRT toast API under PowerShell's own AppUserModelID
(a desktop app without a Start-menu shortcut may raise none of its own), the sound through
`winsound`; a builtin name resolves to `service/sounds/` (the calendar's own files). Both
degrade to `false` where they cannot run. Write-protected like every `POST`.

### `/holidays?regions=RU,DE-BY&year=2026&month=10&lang=ru` · `GET`

From the `holidays` package: `{"days": {"2026-10-03": [{"title": "…", "public": true}]}}`
for the month, `public` meaning a day off. `/holidays/regions?lang=ru` lists what the
package knows: `[{"code": "DE", "name": "Germany", "subdivisions": ["BB", "BE", …]}]`.
Regions are ISO codes with an optional subdivision, not KHolidays' plan names.

### `/time?zone=Europe/Berlin` · `GET`

`{"zone": "Europe/Berlin", "offset": 7200, "city": "Berlin"}` — the zone's current UTC
offset in seconds and the city part of its name, what the weather view asks Plasma's time
engine for. `zone=Local` is the machine's zone.

### `/fetch?url=https://…` · `GET`

The weather's relay: the URL fetched by the service and answered as it came — the
status (a 304 and a 403 included), the body, the content type, and `Last-Modified`,
`ETag`, `Expires`, `Cache-Control`, `Date`. `User-Agent`, `Accept`, `Accept-Language`,
`If-Modified-Since` and `If-None-Match` from the request go along. `https` only, GET only,
4 MiB at most; a host that cannot be reached is a 502 with the reason. The weather host
sets `WeatherView.requestPrefix` to this path, so every request of the shared view goes
through Python, which reads the system proxy from the registry and trusts the system's
certificate store — a bare qml window on a corporate network stayed "offline".

### `/settings/<widget>` · `GET`, `POST`

The settings of one widget (`monitor`, `spectrum`, `player`, `weather`, `calendar`): every
key of that widget's `package/contents/config/main.xml` with the stored value or the
default, plus the window keys the plasmoid never had — `winX`, `winY`, `screen`,
`behindIcons`. Stored in `%APPDATA%\plaintop\<widget>.ini` (one `[General]` section, the
same key names), which a person may edit; the service re-reads it when it changes.
`GET` answers `{"stamp": 17, "values": {…}}`; `GET …?since=17` answers 304 while nothing
changed, so a host may ask every second for nothing. `POST {"key": value, …}` merges and
writes. The types come from `main.xml`.

### `/themes` · `GET`, `POST` `{"name": "nord"}`

The palettes — `palettes/*.json`, the same files `install.sh --palette` writes into the
plasmoids — for the tray's *Theme* menu: `GET` answers `{"themes": [{"name", "title",
"note", "swatch": {"fg", "accent", "dim", "value"}}, …], "current": "nord"}`, `stock`
first (the widgets' own defaults), `current` the palette whose every key the settings
carry now (`""` when none does). `POST` writes one into every widget's settings through
the store; the hosts follow on their next poll. Every key is checked against the schema
before anything is written, as `palette.py` does on Plasma: a misspelt key is a 400, an
unknown name a 404.

### `/ui` · `POST`

The process manager: `{"show": "monitor", "on": true}` starts (or stops) a widget's
host, `{"settings": "monitor"}` opens its settings window, `{"quit": true}` stops
everything. `GET /ui` lists what runs. The tray icon (`win/host/tray.qml`) and the hosts'
own menus speak this.

## What the hosts are

`qml.exe` from Qt 6 runs `win/host/<widget>.qml`, one process and one window per widget:
frameless, transparent, `Qt.Tool`, `Qt.WindowStaysOnBottomHint`, and
`Qt.WindowTransparentForInput` while the *Mouse* setting lets clicks through — the
archived window hosts of 2026-09-21, on another OS. The shared QML is copied in by
`win/build.py` (as `install.sh` copies it into the plasmoid packages) and the Plasma
modules it imports are QML-only shims under `win/host/imports/`. Translations are the
`po/` catalogs converted with `lconvert -target-language LANG` and loaded with
`qml -translation`; the `i18n*` functions sit on each window's root and call
`qsTranslate("", text, context, n)` — the context goes into Qt's disambiguation, which is
where `lconvert` puts `msgctxt`.
