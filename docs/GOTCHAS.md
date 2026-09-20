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
Input    (what catches the mouse): 0 rectangles   ← клики проходят (clicks pass through)
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

That is why the gap from the edge is drawn **inside** the widget (the «Отступ
слева/сверху» settings — left/top margin), not by the applet's coordinates: this way it
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

## A desktop plasmoid cannot pass clicks to the desktop

Three attempts, all executed, all failed:

| Attempt | Outcome |
|---|---|
| `enabled: false` on the full representation | the click still does not reach the desktop |
| `locked = true` through plasmashell scripting | the property is read-only in Plasma 6; it stays `false` |
| `immutability=2` on the containment, written while the shell was stopped | applied and survived, clicks still caught |

The reason is in the shell's own code: `BasicAppletContainer` wraps every applet and its
C++ base listens for the press itself — it needs press-and-hold to enter edit mode
(`editModeCondition: AfterPressAndHold`). Nothing in the applet's QML can decline that.

## A plain window can: `Qt.WindowTransparentForInput` works under KWin Wayland

Verified with a counter on screen: a `Window` with
`flags: Qt.FramelessWindowHint | Qt.WindowTransparentForInput` caught **zero** clicks
while being clicked repeatedly. Wayland gets an empty input region for it — the native
equivalent of the X Shape trick conky needed.

⚠️ The price is placement: under Wayland a window cannot position itself. `x` and `y` are
ignored and KWin places the window where it likes, so a widget-like window needs a KWin
rule to force position, size, keep-below and skip-taskbar.
