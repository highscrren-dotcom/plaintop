# plaintop on Windows 11

English · [Русский](README.ru.md) · the protocol: [PROTOCOL.md](PROTOCOL.md)

The same five widgets — the text monitor, the audio visualizer, the player, the weather and
the calendar — on a Windows 11 desktop, drawn by the same QML files the KDE Plasma widgets
are drawn by. Nothing of Plasma is needed: each widget is a frameless transparent window
run by Qt's own `qml.exe`, and one small Python service feeds all five with readings,
settings and the calendar's notes. How that was chosen, and what it costs, is decision 17
in [../docs/DECISIONS.md](../docs/DECISIONS.md).

⚠️ **Status.** The port was written in a Linux container, without a Windows machine, and
verified there on a bare Qt (6.8, 6.10 and 6.11) against a stand-in of the service and with the service's
own Python stands; the CI job on `windows-latest` is where it first met Windows, and it is
green: the service's stands, the hosts loaded by `qml.exe` against the real service, and the
zip — all offscreen, no desktop. The things only a desktop can show — the sound capture, the media session, the sensors from
LibreHardwareMonitor, the look of the window flags, the tray, the toast — have not been
seen on one yet. Reports welcome.

## What you need

- **Windows 11** (10 should do; not tried).
- **Python 3.12** from python.org or the Store, with
  `pip install numpy psutil holidays tzdata tzlocal`. Optional, each bringing one
  thing: `winsdk` — the player (the System Media Transport Controls); `soundcard` or
  `pyaudiowpatch` — the visualizer's sound capture (WASAPI loopback of the default output);
  `pycaw` — the monitor's sound line.
- **Qt 6.8 or newer** — only `qml.exe` and its QML modules are used. The Qt online
  installer (`C:\Qt\6.10.3\msvc2022_64`, say), or `pip install aqtinstall` and
  `aqt install-qt windows desktop 6.10.3 win64_msvc2022_64`. The hosts pass their stand on
  6.8, 6.10 and 6.11; CI uses 6.10.
- **The font**: *JetBrainsMono Nerd Font Mono* — the `JetBrainsMono.zip` from
  [nerdfonts.com](https://www.nerdfonts.com/font-downloads), unpacked and every `.ttf`
  installed for the user (right-click → *Install*). Without it the widgets take the first
  fixed-pitch face Windows has (Cascadia Mono, Consolas, Lucida Console, Courier New — in
  that order), so the columns stay columns, but the Nerd icons and the weather's character
  icons lose their shape. (On Windows "monospace" names no family: the first desk ran on
  Segoe UI, and the monitor's percentages wandered.)
- **LibreHardwareMonitor** (optional) for the temperatures and the fans: run it,
  *Options → Remote Web Server → Run* (port 8085). Without it those readings are absent and
  the lines that need them say nothing, as on a Linux machine without `lm_sensors`. The GPU
  block does not need it: the load and the memory come from the performance counters Task
  Manager reads, the name from the registry, and an NVIDIA card's temperature and power from
  `nvidia-smi`; an Intel or AMD card shows no temperature without LHM.

## Run it from the repository

```powershell
git clone https://github.com/highscrren-dotcom/plaintop.git
cd plaintop
python win\build.py --qt C:\Qt\6.10.3\msvc2022_64   # copies the shared QML in, converts the catalogs
python win\plaintop.py                              # the service, the widgets, the tray icon
```

`build.py` assembles `win\host\<widget>\` from the shared sources, as `install.sh` assembles
the plasmoid packages, and writes the translations to `win\host\i18n\`. `plaintop.py`
starts the service on `127.0.0.1:8788`, then every widget whose `shown` setting is on, and
a tray icon. It looks for `qml.exe` in `PLAINTOP_QML`, then on `PATH`, then under `C:\Qt`;
`pythonw win\plaintop.py` runs it without a console window.

**The tray icon** is the way in while the widgets let clicks through: which widgets are
shown, each one's settings, quit. **The settings** open in a window of their own — the same
pages, fields and words as the Plasma dialog, written to `%APPDATA%\plaintop\<widget>.ini`,
which you may also edit by hand; a running widget follows within a second. **The mouse**
setting (*General*, or the widget's own menu) makes a widget transparent for input: every
click lands on the desktop, as the Plasma widgets were before their active lines. With it
off, the left button drags the widget, the right opens its menu — settings, the mouse
switch, *behind the desktop icons*, close. The place is remembered.

**Where the window sits.** A tool window kept at the bottom of the stack — Rainmeter's
"Bottom" position; Qt holds it there itself. Two things follow: *Show desktop* (Win+D) hides
the widgets until the desktop is un-shown, and the desktop icons draw over them where they
overlap. **Behind the desktop icons** (experimental, off) parents the window under the
wallpaper's `WorkerW` the way wallpaper engines do; it depends on the Windows build (24H2
moved that layer inside Progman) and dies with an Explorer restart. **`softwareRender`**
(in the ini, off) starts a widget on Qt Quick's software backend: such a window is painted
with per-pixel alpha, and Windows is documented to pass the mouse through its transparent
pixels — the candidate for clicks that reach the text and nothing else. None of the three
has been seen on a desktop: try them, and say what happened
([../docs/research/windows-widgets.ru.md](../docs/research/windows-widgets.ru.md) has the
sources and a checklist).

**The reminder's notification** is a Windows toast raised under PowerShell's own id (a
desktop app without a Start-menu shortcut cannot raise one), so it says "Windows
PowerShell" above the text. **Defender** will show "Windows protected your PC" for an
unsigned zip: *More info → Run anyway*. **LibreHardwareMonitor** needs administrator rights
for the sensors, so it cannot sit in the Startup folder; start it from Task Scheduler with
the highest privileges.

**The zip.** Every green CI run keeps `plaintop-win.zip` as the artifact `plaintop-win`
(*Actions → checks → the run → Artifacts*): `plaintop.exe` with the frozen service, `host/`,
and `qt/` with `qml.exe` and its modules — unpack anywhere, run `plaintop.exe`; the font and
the optional packages above are not inside. Built by `win/package.py`; the CI job runs the
`plaintop.exe` it just packed (`PLAINTOP_NO_HOSTS=1`, the service alone) and asks it for
`/monitor`, `/bands`, `/settings`, `/holidays`, `/notes` before the artifact is kept. The
frozen service finds its files beside the exe (`win/service/paths.py`); `PLAINTOP_ROOT`
names another root by hand, `PLAINTOP_PORT` another port. The first run on a desk (2026-10-05)
died in a message box, `FileNotFoundError: …\spectrum\relay.py` — that is what the step
guards against; a `--noconsole` exe shows an uncaught exception as that box and nothing else.

**Autostart:** a shortcut in the Startup folder (`Win+R`, `shell:startup`) to
`pythonw.exe C:\path\to\plaintop\win\plaintop.py`.

## What is different from Plasma

| | Plasma | Windows |
|---|---|---|
| Host | the plasmoid | `qml.exe`, one window per widget |
| Clicks through | everywhere but the active lines, the player's controls, the calendar's cells (decisions 11, 14) | whole window: on, nothing takes the mouse; off, everything does |
| Active lines | on by default | off by default: the items are Linux commands |
| Holidays | KHolidays' 170 regions, chosen by name | the `holidays` package, ISO codes (`DE`, `DE-BY`, `RU`) on the *Holidays* page |
| Reminders aside the sheet | `notify-send`, `pw-play` | a toast, `winsound` |
| Settings | Plasma's dialog, the shell's config | our window, `%APPDATA%\plaintop\*.ini` |
| Sensors | ksystemstats | psutil, LibreHardwareMonitor's JSON, `winget`, the Event Log |
| The visualizer's source | cava | WASAPI loopback and numpy |

## The stands

```powershell
python tests\win_service.py        # the sensors, the command emulation, the server
python tests\win_bands.py          # the spectrum analyzer on synthetic signals
python tests\win_media.py          # the player mapping, notes.py in the service, holidays, time zones
python tests\win_hosts.py --qt C:\Qt\6.10.3\msvc2022_64   # the five hosts through the shims, against the real service
```

The last one builds the hosts, starts the service on a free port, runs `tests\win_hosts.qml`
in `qmltestrunner` offscreen and stops the service. All four run in CI on `windows-latest`
(`.github/workflows/check.yml`).

## Layout

- `win/host/` — the five hosts (`monitor.qml`, …), `tray.qml`, `settings.qml`, and under
  `imports/` the QML-only stand-ins for the Plasma modules the shared files import, plus the
  `plaintop` module (the service client, the i18n functions, the base window).
- `win/service/` — the Python service: `server.py` (the router), `monitor_win.py`,
  `exec_win.py`, `bands.py`, `player_win.py`, `notes_bridge.py`, `holidays_win.py`,
  `timezones.py`, `settings_store.py`, `ui.py`, `notify_win.py`.
- `win/build.py`, `win/plaintop.py` — the build and the launcher.
