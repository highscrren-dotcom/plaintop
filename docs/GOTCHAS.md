# Gotchas: a desktop widget under KDE Plasma 6 / KWin Wayland

English · [Русский](GOTCHAS.ru.md)

Collected while setting the widget up on s1dPC on 2026-09-20. Everything is confirmed by
running it on a live system — nothing here comes "from the docs" or "from memory".

Two parts: conky first (the initial implementation), then the plasmoid (the target one).

# Part I. conky

## Conky works under Wayland

The common claim "Conky does not work under Wayland" is wrong for KDE. It runs through
XWayland (`Xwayland :0 -rootless`, which KWin starts automatically) and behaves normally.

⚠️ The real limits are not where people usually look for them — see below.

## Window type: `normal` only

| Type | Window is created | Transparency |
|---|---|---|
| `normal` | yes | **yes** |
| `desktop` | yes, the property is set correctly | **no — a black rectangle** |
| `override` | yes | no (the man page says so: "semi-transparent backgrounds do not work") |

With `desktop`, KWin stops compositing the window. Verified: an opaque black backing
appears around the text.

The combination that works:
```lua
own_window_type = 'normal',
own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
own_window_colour = '#00000000',
```

⚠️ `own_window_transparent` and `own_window_argb_value` are deprecated in conky 1.24,
`own_window_argb_visual` is removed. Transparency comes only from `own_window_colour`.
Almost every older guide on the web is written against the removed keys.

## Click-through: conky has NO setting of its own

The config has six `own_window_*` keys in total, and none of them makes the window
transparent to the mouse. Xshape is compiled into the build ("Xshape extension (click
through)" in `conky --version`), but it is not exposed.

The fix is to give the window an **empty input region** from the outside, through the
X Shape extension (`conky/clickthrough.py`, needs `python-xlib`).

Check the result by reading it back, not by eye:
```
Bounding (what gets drawn): 440x748
Input    (what catches the mouse): 0 rectangles   ← clicks pass through
```

⚠️ **Checking with `xdotool mousemove` is pointless.** Wayland blocks synthetic mouse
motion: the cursor does not move, `getmouselocation` returns the window under its real
position, and the test silently reports the wrong thing. A false "it works" is easy here.

## Who starts conky — many paths, and you cannot block them all

Symptom: after a reboot the screen shows a foreign conky, or ours but catching clicks.

The sources found, all real:
1. **`ksmserver`** — the KDE session manager saves conky (it registers over XSMP) and
   starts it at login. Fixed by `excludeApps` in `ksmserverrc`.
2. **KWin plus the packaged desktop file** — KWin keeps its OWN session
   (`~/.config/session/kwin_saved at previous logout_`), matches `resourceClass=Conky`
   against the packaged `/usr/share/applications/conky.desktop`, and starts **that one**
   (`Exec=conky --daemonize --pause=1`) with the default config.
3. **KWin from the saved command** — starts our command directly, bypassing the launch script.

**The point this section exists for: do not enumerate the launchers.** There are more of
them than it seems, and each one surfaces only after another reboot. Instead, make the
operation idempotent: start conditionally, apply the wanted state **always**.

What covers it (the layers are independent on purpose):
- `own_window_class = 'conky-plainext'` — breaks the match against the packaged desktop file;
- `~/.local/share/applications/conky.desktop` with `Hidden=true` — shadows the system file,
  since the user directory comes first in `XDG_DATA_DIRS`;
- `start.sh` kills foreign instances and applies click-through no matter who started conky.

⚠️ Keep `excludeApps` in step with `own_window_class`: after the class changes, the old
value stops matching and the exclusion silently turns off.

## Small things that cost time

- **`pkill -f 'conky -c'` kills your own shell** — the pattern matches the shell's own
  command line. Use `pkill -x conky` only.
- **`bat cache --build` does not pick up the theme on the first run** — a second run is
  needed. Check with `bat --list-themes | grep tokyo`.
- **Address sensors by chip NAME** (`coretemp-isa-0000`, `nct6779-isa-0a20`), not by
  `hwmon` index — the indexes drift between reboots.
- **`${if_mounted}` does not save you from the `statfs` error**: conky registers file
  objects before it evaluates the condition, so an unmounted path logs the error once.
  Harmless.
- **Lua 5.4 forbids assigning to a loop variable** — `for v in ... do v = tonumber(v)`
  fails with `attempt to assign to const variable`.
- **Cleaning configs with a keyword filter is dangerous.** Deleting every line containing
  `conky` from `ksmserverrc` also removed `excludeApps=conky` — that is, it disabled the
  protection added one line earlier. Order: clean first, write after.

## Traps in the scripts themselves

- **`set -o pipefail` and `grep -q` lie together.** `fc-list | grep -q 'font'` returns an
  error even when the font is there: `grep -q` exits on the first match, `fc-list` catches
  `SIGPIPE`, and with `pipefail` the whole pipeline counts as failed. The check silently
  reports "not found". Fixed by dropping the pipeline — here via `fc-match -f '%{family}'`.

# Part II. the plasmoid

## Reading files from QML inside plasmashell is forbidden

`XMLHttpRequest` to `file:///proc/stat` does not work: Qt answers "Using GET on a local
file is disabled by default. Set `QML_XHR_ALLOW_FILE_READ` to 1". The variable is set on
the process of **the whole shell**, so it loosens file access for any QML inside it, and it
requires a re-login. Verified: the plasmashell journal gets a warning on every tick, and
the data is zero.

⚠️ Hence decision 2 in `DECISIONS.md`: data comes from ksystemstats by subscription instead
of being read out of `/proc` by hand.

## plasmashell keeps the package's QML in a cache

Reinstalling the package is not enough. Recreating the applet on the desktop is not enough
either. Verified with markers in `Component.onCompleted`: the new code did not run after
`kpackagetool6 --upgrade`, nor after `remove()` + `addWidget()`; the marker appeared only
after `systemctl --user restart plasma-plasmashell.service`.

That is why `./install.sh --plasmoid` restarts the shell itself — otherwise an edit
silently never arrives, and the time goes into hunting a QML bug that does not exist.

📝 Place markers for such checks with `console.warn`: it definitely shows up in the journal.

## Scripting plasmashell is not full QML

`org.kde.PlasmaShell.evaluateScript` has **no `Qt` object**: `Qt.rect(...)` fails with
`ReferenceError: Qt is not defined`. Assigning a plain JS object `{x, y, width, height}`
to `widget.geometry` passes silently and **changes nothing**.

Position and size are set only through the creation arguments:

```js
desktops()[0].addWidget("org.s1dd1.plaintop", 48, 44, 440, 815)
```

The size is snapped to the grid in the process: 440x815 becomes 448x816.

## There is no `systemmonitor` engine in Plasma 6

The data engine directory is `/usr/lib/qt6/plugins/plasma5support/dataengine/`, and
`systemmonitor` is missing from it: there are `executable`, `time`, `powermanagement`,
`soliddevice` and the weather ones. All monitoring moved to ksystemstats
(`org.kde.ksysguard.sensors`).

## Sensors do not answer instantly

The `ksystemstats` daemon starts on the first subscription, and for 1–1.5 s the sensor
stays in the "loading" state (`status: 1`). At startup, draw a dash: a zero at that moment
is a falsehood, not a value.

📝 Measured in a separate QML engine of the same Qt version, not inside the shell.

## Ready-made formatting breaks monospace columns

`formattedValue` and `Formatter` insert an invisible U+200B before "%", U+2009 before "°C",
and U+00A0 in the thousands separator. In text whose columns rely on an equal character
width, it shows immediately. Take the raw `value` and format it yourself.

📝 Verified in the same place — the separate engine; the format was not re-checked inside
the shell, because the ready-made formatting is not used at all.

## The applet size is set by `Layout.*` on the root — and only as a constant

The containment does not ask for `implicitWidth/Height` inside `fullRepresentation`: it takes
the size from `Layout.minimum*`/`Layout.preferred*` **on the root `PlasmoidItem`**.

⚠️ And the hint must be constant. While it was computed from the text height, the containment
rebuilt the layout on every change in the number of lines — and lines arrive as the data
comes in (disks after 10 s, services after 15 s). Every rebuild reset the widget into the
0,0 corner. Verified many times over.

## The applet position cannot be pinned programmatically

Tried, all confirmed by running it:

| Attempt | Result |
|---|---|
| `addWidget(type, x, y, w, h)` | coordinates ignored |
| `widget.geometry = {x, y, …}` in scripting | passes silently, changes nothing |
| `Qt.rect(...)` in the same place | `ReferenceError: Qt is not defined` |
| Writing `ItemGeometries` into the config while the shell is running | overwritten by the shell itself |
| The same with the shell stopped | **plasmashell still puts the applet at 0,0** |

That is why the gap from the edge is drawn **inside** the widget (the *Left padding* /
*Top padding* settings), not by the applet's coordinates: this way it
holds no matter where the containment put the applet, and it survives a shell restart.

## systemd silences plasmashell after frequent restarts

While debugging QML the shell restarts on every edit, and after a few in a row systemd
answers "start request repeated too quickly" — the desktop is left without a panel. Fixed
by `systemctl --user reset-failed plasma-plasmashell.service` and another `start`. A pause
between restarts is needed; `install.sh --plasmoid` does one.

## Qt logs go to journald, not to stderr

`console.warn` from QML is not visible in the terminal — the message goes to the journal.
For debugging `qml6`, `QT_FORCE_STDERR_LOGGING=1` helps; without it the code looks like it
never runs at all.

## ksysguard model roles are addressed by name

Role numbers differ between models: `Value` is 265 in `SensorDataModel` and 256 in
`ProcessDataModel`. Hardcoding the numbers is not an option, and guessing is not needed
either: the enum is available in QML as `Sensors.SensorDataModel.Value` and
`Proc.ProcessDataModel.Value`.

⚠️ For `KSortFilterProxyModel`, sorting is set with `sortRoleName: "Value"`;
with `sortRole` the component does not build at all.

## `http://127.0.0.1` is allowed, `file://` is not

The XHR ban applies to local files only. A request to a local HTTP server from inside
`plasmashell` works: verified with a probe in the installed widget, which logged
`status=200` and a full response body. So a block that needs data no sensor provides can
get it from a small local service instead of a compiled plugin.

⚠️ The price is in the polling, not the drawing. Measured on s1dPC: a 120-tick ring drawn
from scene items costs 3.9% of one core at 30 updates/s, while polling the same data over
HTTP at 45/s and parsing the JSON costs 6.3% on its own. Rate and payload size matter more
than the shape.

## An animated transform costs more than the data it animates

The same ring, same data: 3.9% of one core standing still at 30 fps, 12.3% spinning at
60 fps, 26.4% when drawn on a `Canvas` instead of scene items. If motion is not in the
data, it is not worth its price.

## A desktop plasmoid passes the right button on, never the left

`enabled: false` on the full representation is not useless — it hands the **right** button
over, so the desktop's own context menu (and an icon's menu) opens through the widget. The
**left** button never arrives: it is what the applet container watches for press-and-hold
to enter edit mode (`editModeCondition: Plasmoid.immutable ? Manual : AfterPressAndHold`).

Four attempts, all executed, all failed on the left button:

| Attempt | Outcome |
|---|---|
| `enabled: false` on the full representation | right button passes through, left does not |
| `locked = true` through plasmashell scripting | the property is read-only in Plasma 6; it stays `false` |
| `immutability=2` on the containment | applied and survived a restart, left button still caught |
| `immutability=2` on the containment **and** every applet | the condition above should become `Manual`, and the left button is still caught |

⚠️ The last row is the interesting one: locking the widgets does not free the left button
even though the QML condition says it should stop waiting for press-and-hold. Whatever
grabs it sits deeper, in `ItemContainer` itself. Nothing in an applet's QML can decline it.

## A plain window can: `Qt.WindowTransparentForInput` works under KWin Wayland

Verified with a counter on screen: a `Window` with
`flags: Qt.FramelessWindowHint | Qt.WindowTransparentForInput` caught **zero** clicks
while being clicked repeatedly. Wayland gets an empty input region for it — the native
equivalent of the X Shape trick conky needed.

⚠️ The price is placement: under Wayland a window cannot position itself. `x` and `y` are
ignored and KWin places the window where it likes, so a widget-like window needs a KWin
rule to force position, size, keep-below and skip-taskbar.

## `SensorDataModel` silently drops ids it cannot resolve

Ask it for 165 sensors and it may give back 162 columns: the ids it cannot resolve are not
reported, they simply are not there, and **every later column shifts**. Code that reads
column *n* then gets a neighbour's value — on s1dPC the "NVMe temperature" read a fan.
Re-subscribing does not help, and there is no cap on the count (200 core ids resolve fine).

What works: address columns by their `SensorId` role instead of by position, and take
everything that is not a uniform array through individual `Sensors.Sensor` objects. Those
resolve the very same ids reliably and expose `status` — 2 means Ready, so a missing
reading can be told apart from a zero one.

## `cpu/all/coreCount` is not `cpu/all/cpuCount`

`cpuCount` is the number of physical packages — 2 on this machine. `coreCount` is 72.
Latching the length of the per-core arrays from `cpuCount` left the widget reading two
temperatures out of 72 and looked exactly like "the core temperatures disappeared".

## Chip names rot exactly like hwmon indexes

The project already bans taking sensors by `hwmon` index. The chip name is no safer:
after a reboot `lmsensors/nvme-pci-0500/temp1` became `nvme-pci-0600`, and the network
interface went from `enp4s0` to `enp5s0`. A widget that carries such an id in its config
goes quiet, without an error, on the machine it was written for — never mind another one.

So ids are discovered: `SensorTreeModel` is enumerated once (675 entries here), a stored
id is kept only as a **preference**, and when the machine no longer has it a pattern finds
the replacement — `^lmsensors/nvme-[^/]+/temp\d+$` finds the drive whatever the bus
renumbering did.

## The sensor tree also contains regex templates

Among the entries are `cpu/cpu\d+/temperature`, `gpu/gpu\d+/usage` and
`network/(?!all).*/download` — 11 of 675 on s1dPC. They are patterns for whole groups, not
sensors, and subscribing to one returns nothing. Filter them out by regex metacharacters
(`( * \ ? [ ] | +`): a real id never contains any of them.

## Network interfaces come out of the tree in hash order

"The first interface in the tree" is not a choice but a coin toss. ksystemstats keeps
devices in a `QHash` (`SensorContainer` in libksysguard), so with two connected devices —
Wi-Fi plus a dock, two ports — the order changes from one daemon start to the next. The
tree is clean, though: the NetworkManager backend publishes only Ethernet, Wi-Fi,
Bluetooth, modem and ADSL devices with an active connection, and the rtnetlink backend
only `ARPHRD_ETHER` links with no link type that are UP. `docker0`, tun (sing-box,
WireGuard), veth and `lo` appear in neither: on s1dPC `nmcli` reports four connected
devices and the tree holds one. Read in the ksystemstats 6.7.5 source.

So the candidates are sorted and ranked: a default gateway first (a non-empty
`ipv4gateway` or `ipv6gateway` — only the NetworkManager backend fills them, the
rtnetlink one never does), then the traffic carried (`totalDownload`), then the name.
They are ranked once per set of interfaces so the pick does not flicker, the probes
unsubscribe as soon as the pick is made, and with a single interface they are never
created at all.

## Inside a `Sensors.Sensor`, a bare `name` is the sensor's own property

`Sensor` has its own `name`, `shortName`, `value`, `unit`, `status` and `enabled`, and an
unqualified identifier in a binding inside it is looked up there first. In a delegate
with a `name` property, `sensorId: "network/" + name + "/download"` came out as
`network//download` — the sensor's display name, empty until metadata arrives — and the
sensor stayed in Loading; `probe.name` gave `network/enp5s0/download`. Verified on s1dPC
2026-09-22. Refer to the delegate by its `id`.

## Kirigami's `FormLayout` complains when a `Repeater` rebuilds its children

`TypeError: Cannot read property 'isSection' of null`, `Cannot read property 'Accessible'
of null`, `Unable to assign [undefined] to int` — three lines per rebuild, every time the
model of a `Repeater` inside a `FormLayout` changes. Reproduced with a 25-line file
containing nothing but a `FormLayout`, a `Repeater` and one model swap: it is Kirigami's
own noise, not a bug in the delegate. Worth knowing before spending an hour in your own
code, as happened here.

## A list reaches a `Repeater` delegate as a variant list, not a JS array

`modelData.value` holding a list of strings: `Array.isArray()` returns **false**. A guard
written as `Array.isArray(v) ? v : []` renders an empty list while the config holds two
entries — and nothing warns, because both branches are valid. Copy it by `length` instead
and the same code works for a JS array and for a variant list alike.

## At boot the relay can start before PipeWire — and one bad line used to kill it

The unit is ordered after `pipewire.service`, yet at boot cava still found no stream,
exited, and wrote a terminal-title escape (`\x1b]0;cava…`) to stdout on the way out. The
relay fed that line to `int()`, the reading thread died with a `ValueError`, and the relay
went on answering HTTP with no cava and no restarts — `/state` read `frames: 0,
restarts: 0` until the next reboot. The ring simply looked silent.

Now a line that is not a frame is skipped, any error inside the loop ends in a restart
rather than in a dead thread, and restarts back off to 10 s while cava cannot start at
all. The unit also waits for `wireplumber` and `pipewire-pulse` — that narrows the race,
but only the retry closes it. Reproduced with a fake `cava` that prints the same escape
and exits: three restarts at 2, 4 and 8 s, no traceback.

## A pid file does not know about the autostart

The window hosts recorded their pid when started from `setup.py`, but the autostart entry
launches `qml6` directly and writes nothing. After a reboot the file was stale: `--status`
reported "not running" about a live window, and a restart left the old one alone and put a
second copy on the desktop. The running windows are now found in the process table — the
exact executable (`comm` is `qml6`) and the exact `window.qml` path among its arguments —
which also keeps well clear of `pkill -f`.

## Reassigning a `var` map from many handlers rebuilds everything that reads it

Each of ~25 individual `Sensors.Sensor` objects published its value by copying a map and
assigning the copy. Every line of the monitor reads that map, so every line was rebuilt
once per sensor per second — the window cost 18% of a core for text that changes once a
second. Mutating the map in place and rebuilding on one shared tick brought it to 9%
(4.6% collecting, the rest drawing). The same rule for the sensor registry: its 10-second
poll now assigns the id list only when it actually changed, instead of recreating every
sensor object each time.

## A `Repeater` fed a JS array recreates every delegate when the array changes

The monitor builds its lines as a new array on every tick, and the `Repeater` took that
array as its model — so every tick destroyed all 41 line items and built them again,
`Text` layout included. Counted with a `Component.onCompleted` counter: ~57 delegates a
second at a 700 ms interval. Giving the `Repeater` the count (`lines.length`) and letting
each delegate read `lines[index]` keeps the items; a `Text` whose string did not change
does nothing. The window went from 8.0% of a core to 4.5%, the same picture on screenshots.

## A child's CPU time is not in the parent's own

`utime + stime` of the monitor window left out everything its `executable` data sources
ran — those go to `cutime + cstime` once reaped. The services script was 615 ms of CPU
per run, every 15 s: 4.3% of a core around the clock, measured over 15 hours, and missing
from every earlier figure. `pacman -Qu` alone was 362 ms; it now runs only when the
pacman database changes. Measure children too, or a shell-out hides in plain sight.

## `ProcessDataModel` reads all of /proc every 2 s, whatever else is set

The period is fixed inside libksysguard (2000 ms) and does not follow the widget's
interval. `enabled` starts and stops that timer; enabling does not read at once, the first
read lands 2 s later. Switching it on for one read per period works: CPU usage is computed
from the real elapsed time — a process spinning one core read 99–100% both at 2 s and at
one read per 10 s. Cost with ~900 processes: 3.2% of a core at 2 s, 1.3% at 10 s.

## cava computes through silence unless `sleep_timer` is set

Silence is all-zero samples, and cava keeps running its FFT and writing frames through it:
3.9% of a core. `sleep_timer=N` makes it stop after N seconds of silence and look at the
input once a second — 0.35%. The relay had a comment saying cava falls asleep, but the
setting itself was never passed, so it never did. The price is waking up: the first frame
comes 0.04–1 s after the sound returns, measured by feeding cava a FIFO.

## A status check that compares with the install-time copy passes after every edit

The shared QML is copied into the plasmoid package at install time, and `--status`
compared the installed package with that copy — after an edit in `shared/` both were old
and the check said "match". The window hosts were checked only for existence: the monitor
window ran a `SensorRegistry.qml` one fix behind the repository for a day. `--status` now
compares with the sources, including the relay, and says when a window was started before
its files were deployed (`ctime` of the files, since `copy2` carries the source `mtime`
over; process start through `/proc/uptime`, since `btime` is a whole second and flagged a
window started 0.05 s after its deploy).

## xgettext marks ki18n placeholders as JavaScript format

Run over QML with `-L JavaScript`, xgettext flags a string like `"%1d"` as
`javascript-format`. That is the wrong format: ki18n's placeholders are `%1`…`%99`, and the
Russian `"%1д"` then comes out of `msgmerge` fuzzy — ignored at run time. `po/extract.py`
drops the JavaScript flag and marks every string with `%1`… as `kde-format`, which
`msgfmt --check` really does check: a translation that loses `%2` fails the build.
Verified on s1dPC 2026-09-22.

## KDE's Formats win over `LANG` and `LC_ALL`

To look at the widget as an English user would, `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
LANGUAGE=en` is not enough under Plasma: the words switch, but the date stays
"Вторник, сентября 22" and the decimal separator a comma. The KDE integration that
Kirigami loads applies `~/.config/plasma-localerc` (System Settings → Formats) over the
environment. With an empty `XDG_CONFIG_HOME` the same run gives "Tuesday, September 22"
and "9.2 GiB". This is right for users — Formats are theirs to choose apart from the
language — and only matters for tests.

## A locale that is not generated silently turns every translation off

`locale -a` on s1dPC lists only C, en_US and ru_RU. Run the widget with
`LC_ALL=de_DE.UTF-8 LANGUAGE=de` and glibc, not finding the locale, falls back to C — and
in the C locale gettext ignores `LANGUAGE`. Every string stays English, while the date is
German, because Qt names weekdays and months from its own data. All four translation runs
hit this independently. Without root, build the locale into a scratch directory and point
glibc at it: `localedef -i de_DE -f UTF-8 $DIR/de_DE.UTF-8`, then add `LOCPATH=$DIR`.
Leaving `LC_ALL` alone also works — `LANGUAGE` is honoured under any generated locale —
but then the date stays in yours.
