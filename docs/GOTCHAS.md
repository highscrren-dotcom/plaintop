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
That is not a plasmashell trait: on this Arch-based system any Qt program logs to journald
as soon as stderr is not a terminal, so a pipe or a redirect into a file gets nothing at
all, while `journalctl --user` has the messages. `QT_FORCE_STDERR_LOGGING=1` brings them
back — for `qml6`, and for `qmltestrunner` in a script; without it the code looks like it
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

## The applet's wrapper takes the left button — and can be told to let go

`enabled: false` on the full representation hands over the **right** button only: the
desktop's context menu (and an icon's menu) opens through the widget, a left click never
reaches the desktop. It is not the applet that keeps it. plasmashell wraps every desktop
applet in an `AppletContainer` — the QML `BasicAppletContainer` over the C++
`ItemContainer` (`plasma-workspace/components/containmentlayoutmanager/itemcontainer.cpp`);
the applet is that container's `contentItem` and its direct child. Three calls in the
constructor decide everything:

```cpp
setFiltersChildMouseEvents(true);         // sees a press before the applet does
setAcceptedMouseButtons(Qt::LeftButton);  // wants the left button only — that is why the right one passes
setKeepMouseGrab(true);                   // and does not let it be taken away
```

`ItemContainer::mousePressEvent` ends in `event->accept()` for every `editModeCondition`
except `Manual`, which returns early — and even that keeps the press, because Qt accepts a
mouse event *before* delivering it (`qquickdeliveryagent.cpp`,
`deliverMatchingPointsToItem`: `pointerEvent->accept();` right before
`QCoreApplication::sendEvent`). One level down, `AppletsLayout::mousePressEvent` does
`event->setAccepted(false)` unless some container is in edit mode, so a press the container
does not take goes on to the folder view and the containment. The wrapper is the whole
problem.

Four attempts, all executed, all failed on the left button — with the line that beat each:

| Attempt | Outcome | The line |
|---|---|---|
| `enabled: false` on the full representation | right button passes through, left does not | `setAcceptedMouseButtons(Qt::LeftButton)`: the container never wanted the right one, and it filters the left one before the child sees it |
| `locked = true` through plasmashell scripting | the property is read-only in Plasma 6; it stays `false` | nothing reached the container at all |
| `immutability=2` on the containment | applied and survived a restart, left button still caught | the desktop containment sets `editModeCondition: Plasmoid.immutable ? Locked : AfterPressAndHold`, and `Locked` still runs down to `event->accept()` |
| `immutability=2` on the containment **and** every applet | the condition should become `Manual`, and the left button is still caught | `ItemContainer::editModeCondition()` answers `Locked` whenever the layout is locked; and `Manual` would be pre-accepted by Qt anyway |

The way out is in Qt's target list, not in Plasma's flags. `eventTargets` skips a child
that is `!isVisible() || !isEnabled() || culled` — a disabled item and its whole subtree
are never mouse targets, for either button. From the applet's QML the container is
`root.parent`, and `enabled` is a public, writable property of every `QQuickItem`:

```qml
readonly property bool shellEditMode: (Plasmoid.containment && Plasmoid.containment.corona)
    ? Plasmoid.containment.corona.editMode : false

Binding {
    target: root.parent
    property: "enabled"
    value: !root.cfg.clickThrough || root.shellEditMode
    when: root.parent !== null && ("editModeCondition" in root.parent)
}
```

`Plasmoid.containment → .corona → .editMode` are public `Q_PROPERTY`s of libplasma
(`applet.h`, `containment.h`, `corona.h`), so the widget sees the shell's edit mode and
gives the wrapper back for exactly that time — in edit mode the wrapper is enabled again
(verified over DBus), so the shell's own move, resize and configure handles apply.
The `when` guard binds only when the parent has an `editModeCondition`, that is an
`ItemContainer`, and so stays out of `plasmawindowed` and the previews. The representation
keeps its own `enabled: !root.cfg.clickThrough`, so that in edit mode the wrapper, not the
widget, takes the mouse.

⚠️ While clicks go through, the widget cannot be right-clicked either. Its settings are
reached through the desktop's edit mode, or with `./install.sh --clicks-off`.

⚠️ Disabling the wrapper is the way only for a widget with nothing to click — the monitor
and the weather. Where buttons must keep working — the player, and the visualizer with the
player in its ring — the wrapper stays enabled and gets a `containmentMask` over the
buttons instead: *A partial `containmentMask` on the wrapper* below (decision 11).

Verified in two steps:

- **A stand**, `tests/passthrough.qml`: a QtTest file importing the installed
  `org.kde.plasma.private.containmentlayoutmanager` — the same compiled classes plasmashell
  uses — with an `AppletsLayout`, two `ItemContainer`s over counting `MouseArea`s and one
  more `MouseArea` beneath for the desktop. `./install.sh --check-passthrough` runs it
  offscreen (`QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen
  /usr/lib/qt6/bin/qmltestrunner -input tests/passthrough.qml`): 10 of 10 passed in about
  a second — 11 of 11 since `test_09` for the right button, below, and 17 tests since the
  partial mask of decision 11 (`test_10`–`test_17`; 19 of 19 with init and cleanup,
  2026-09-23). It reproduces the old
  behaviour (left swallowed, right passes), shows that `Locked` and `Manual` still swallow, that `enabled = false` on the
  container passes both buttons on to the desktop and to an applet beneath, that
  re-enabling restores the capture, and that no press-and-hold edit mode starts while
  disabled.
- **The real desktop** (Plasma 6.7.5, Qt 6.11.2): a throwaway counting applet, two
  instances side by side, one plain and one with the binding — the parent printed as
  `BasicAppletContainer_QMLTYPE_85_QML_105`. Real mouse clicks: the plain one counted 30
  presses, the pass-through one 0, and the clicks landed on the desktop. Toggling
  `editMode` of `org.kde.PlasmaShell` over DBus re-enabled the wrapper; leaving edit mode
  disabled it again.

### The right button needs one thing more: the desktop finds the applet by geometry

With only the wrapper disabled, a right-click over the widget still opened the **widget's**
menu. The desktop does not deliver that press to the applet, it looks the applet up:
`ContainmentItem::mousePressEvent` (libplasma,
`src/plasmaquick/plasmoid/containmentitem.cpp`, under the comment "FIXME: very inefficient
appletAt() implementation") loops over every `PlasmoidItem` and takes the first with

```cpp
ai->isVisible() && ai->contains(ai->mapFromItem(this, event->position()))
```

— `enabled` is never looked at, so a disabled applet is still "there" for the context
menu. What `QQuickItem::contains()` does look at is the item's `containmentMask`
(qtdeclarative, `qquickitem.cpp`: with a `QQuickItem` as the mask,
`return quickMask->contains(point - quickMask->position())`). An empty 0×0 `Item` as the
mask makes `contains()` answer "no", and the desktop shows its own menu, as if the widget
were not there. The monitor's and the weather's `main.qml`:

```qml
Binding {
    target: root
    property: "containmentMask"
    value: (root.cfg.clickThrough && !root.shellEditMode) ? noHitMask : null
}
Item { id: noHitMask; width: 0; height: 0; visible: false }
```

In edit mode the mask comes off as the wrapper comes back, so the shell's own handles and
menu work as usual. The player and the visualizer put the controls row's rectangle there
instead of an empty item, so their own menu opens over the buttons only — the partial
mask, below. ⚠️ Why a `Binding` and not `containmentMask: …` — the next gotcha.
Verified: the stand's `test_09` sets the mask by name on an `ItemContainer` and
`contains(Qt.point(50, 50))` flips true → false → true (11 of 11 pass); on the real desktop
both widgets pass the right button as well as the left, with music playing, and the
visualizer loaded without QML warnings.

## "PlasmoidItem.containmentMask" is not available in org.kde.plasma.plasmoid 255.255

Writing the mask declaratively on the applet's root — `containmentMask: noHitMask` inside
`PlasmoidItem { … }` — fails at load, and both applets showed it on the desktop. The
journal says (shortened):

```
error when loading applet "org.s1dd1.plaintop" … main.qml:78:5:
"PlasmoidItem.containmentMask" is not available in org.kde.plasma.plasmoid 255.255
```

The property exists — it is `QQuickItem::containmentMask` — but it carries QtQuick
revision 2.11, and the `org.kde.plasma.plasmoid` module does not import that revision for
its types, so on a `PlasmoidItem` the QML compiler refuses it.

What works is setting it by name:

```qml
Binding { target: root; property: "containmentMask"; value: … }
```

A `Binding` by name goes through `QQmlProperty`, which looks the property up at run time
and does not check revisions. All four `main.qml` files do exactly that, and the stand's
`test_09` does the same against an `ItemContainer`. ⚠️ It is the `PlasmoidItem` that
refuses, not the property: on an `ItemContainer` — the wrapper — `containmentMask: …`
written declaratively loads and works (`test_17`, 2026-09-23). The widgets reach the
wrapper only as `root.parent`, so there it is a `Binding` by name in any case.

## `/usr/bin/qmltestrunner` is the Qt 5 one

On this Arch-based system `/usr/bin/qmltestrunner` belongs to `qt5-declarative` and
answers "Library import requires a version" to a Qt 6 file — it cannot read a Qt 6
`qmldir`. The Qt 6 runner is `/usr/lib/qt6/bin/qmltestrunner` (`qt6-declarative`).

## `left` and `right` are FINAL on every `Item`

They are the anchor lines. A counter named `property int left` in a `MouseArea` does not
compile: "Cannot override FINAL property". Counters are `nLeft` / `nRight`.

## A plain window can: `Qt.WindowTransparentForInput` works under KWin Wayland

Verified with a counter on screen: a `Window` with
`flags: Qt.FramelessWindowHint | Qt.WindowTransparentForInput` caught **zero** clicks
while being clicked repeatedly. Wayland gets an empty input region for it — the native
equivalent of the X Shape trick conky needed.

⚠️ The price is placement: under Wayland a window cannot position itself. `x` and `y` are
ignored and KWin places the window where it likes, so a widget-like window needs a KWin
rule to force position, size, keep-below and skip-taskbar.

The window hosts that were built on this are retired (decision 9) — the plasmoid lets both
buttons through by itself; the fact stands.

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

## `/usr/bin/qmllint` is the Qt 5 one too — as are `qml` and `qmltestrunner`

The same trap as the runner above, one tool over: `/usr/bin/qmllint` belongs to
`qt5-declarative`. Given a Qt 6 file it prints nothing and exits 255 — no unknown import,
no line number — so a check that reads the output and not the exit code passes as "nothing
to report". The Qt 6 linter is `/usr/lib/qt6/bin/qmllint` (`qt6-declarative`), with
`-I /usr/lib/qt6/qml` for the Plasma imports; `CONTRIBUTING.md` spells it out in full. Rule
for this system: for a Qt 6 tool look in `/usr/lib/qt6/bin/` first.

## `plasmawindowed` runs one instance: a second launch exits 0 and says nothing

With one `plasmawindowed` already open, `plasmawindowed org.s1dd1.plainweather` returned at
once with exit code 0, printed nothing, and the log it was pointed at stayed empty — no
window, no error. It looked like the applet had failed to load without a trace. The running
instance is what matters: end it (or check `pgrep -x plasmawindowed`) before launching the
next applet — one at a time.

## The ksystemstats power plugin lists every `Solid::Battery` — mice and headsets included

A desktop with no battery still gets entries under `power/` in the sensor tree as soon as a
wireless mouse, a keyboard or a headset is connected: the plugin registers every
`Solid::Battery` it finds, under the device's serial rather than a name, and each has a real
`chargePercentage`. What tells a battery from a peripheral is `capacity` in Wh: 0 for the
peripherals. So the battery block subscribes to every entry — the capacity is readable only
once subscribed — and shows the ones with `capacity` > 0; on this desktop that is none, and
the block hides. ⚠️ A real battery has not been under it yet: verified are the hide path
and a stub with made-up values.

## The sensor tree lists a childless `power` group, and does not list `pressure`

`registry.has("power")` is true on s1dPC — the group is in the tree with nothing under it —
and `registry.has("pressure")` is false while `pressure/cpu/some10Sec` is there and
answers. Whether a group node appears is up to the plugin, so a group is not evidence of
anything either way. Test a leaf pattern instead: `^pressure/cpu/some10Sec$` for the
pressure block, `^power/[^/]+/chargePercentage$` for the batteries.

## The QML `font` has no `families` in Qt 6.11

A fallback list — the configured family first, `monospace` after it — cannot be written on
a QML `font`: the value type has no `families` property in Qt 6.11, and the assignment
fails. With just `font.family` a family that is not installed goes to fontconfig's
substitution, which need not pick a monospace face, and the columns fall apart. The player
asks `Qt.fontFamilies()` whether the configured family exists and uses `"monospace"` when
it does not.

## Qt's `XMLHttpRequest` has no timeout

`req.timeout` is ignored and `ontimeout` never fires: a request to a host that does not
answer sits open. The weather widget keeps a `Timer` of 10 s next to the request and calls
`abort()` from it; an aborted request comes to `readyState` DONE with `status` 0, the same
as any failed one, so one handler serves both. ⚠️ Reading `status` before DONE throws
"Invalid state" — check `readyState` first, then look at the status. The search on the
location page does the same.

## `new Date("YYYY-MM-DD")` is UTC midnight

An ISO date with no time is parsed as UTC: `new Date("2026-09-24")` is 2026-09-24T00:00Z.
West of Greenwich that instant is still the 23rd in local time, and the weekday taken from
it is yesterday's — the forecast rows would be off by a day for half the world. Build the
date from its parts, `new Date(y, m - 1, d)`: that is local midnight, and the weekday is
right everywhere.

## `msginit` for zh_CN leaves `Plural-Forms: nplurals=INTEGER`

`msginit -l zh_CN` writes the header placeholder `Plural-Forms: nplurals=INTEGER;
plural=EXPRESSION;` instead of a rule, and `msgfmt --check` — the install's gate — refuses
the catalog until it is fixed by hand: `Plural-Forms: nplurals=1; plural=0;` for Chinese and
Japanese. It matters now that `po/extract.py` starts a missing catalog through msginit
itself: look at the header of a fresh catalog before the first install.

## The `services` source runs whether its block is shown or not — the new sources are gated

`services.sh` has run every 15 s since the block was written, block enabled or not: its
`DataSource` has a constant `connectedSources`. The `health` source is gated — with no
enabled `health` block `connectedSources` is empty, and the number of error lines is the
script's argument, so it never reads more than is shown. ⚠️ One property, not two: with
"enabled" and "lines" read as separate properties, the command was rebuilt twice per change
of `blocks`, and the first script was killed while still running — reproduced in the
standalone harness. Gate every new source the same way; the old one stays as it is until
somebody touches it.

## `FontMetrics.height` is not the height of a `NativeRendering` line

At 10 pt JetBrains Mono `FontMetrics.height` says 17.14 px, and a `Text` with
`renderType: Text.NativeRendering` comes out 18 px tall — hinting rounds the line to whole
pixels. An applet sized to five lines from the metric is four pixels short, and the last
line is clipped. Measure a hidden `Text` in the same font and take its `implicitHeight`;
both new widgets size their board that way. Measured in the offscreen host, 2026-09-23.

## A partial `containmentMask` on the wrapper: the buttons take the mouse, the rest lets it through

Decision 8 disables the wrapper, and with it every `MouseArea` inside — a click-through
player had no buttons (decision 11). The way round is Qt's own target search:
`QQuickDeliveryAgentPrivate::eventTargets` skips an item whose `contains()` says no but
still walks into its children. So the wrapper stays enabled and gets a `containmentMask`
that is only the controls row's rectangle, in the wrapper's coordinates: inside it the
wrapper is a target as for any applet — a click reaches the glyph's `MouseArea`,
press-and-hold enters edit mode — and outside it the wrapper is skipped, the press lands
on the desktop or the applet beneath, and so does the hover. The same rectangle goes on
the `PlasmoidItem` for the right button (the desktop's geometric lookup, above), both
through a `Binding` by name, both `null` in edit mode. While the row is hidden — no
player on the bus, or the controls switched off — the rectangle is 0×0 and everything
passes. `player/package/contents/ui/main.qml` and `spectrum/package/contents/ui/main.qml`
do it; the rectangle comes from `PlayerView.controlsRect`, mapped through `mapToItem()`.

Verified on the stand, `tests/passthrough.qml`, tests 11–15: a masked container with a
text and a 120×24 row of buttons over another applet — inside the rectangle the buttons
count the click, outside it the desktop or the applet beneath does; the right button
reaches the desktop either side; hover follows the same line (`test_13`: hover delivery
walks into every visible child whatever the parent says, so a `hoverEnabled` area over the
whole applet would take hover everywhere — the buttons' area takes it only over itself);
press-and-hold inside enters edit mode, outside does not; the mask back to `null` restores
full capture. A second, throwaway stand put the real `PlayerView.qml` inside the compiled
`ItemContainer`: 11 of 11. ⚠️ The stand is offscreen; real clicks on the live desktop are
still the user's check. Verified 2026-09-23, plasma-workspace 6.7.5, Qt 6.11.2.

## A `Text` with the default `textFormat` accepts the left button

Under a partial mask this is the trap. A `Text` built with the default `textFormat`
(`AutoText`) keeps the constructor's `acceptedMouseButtons = LeftButton`
(`qquicktext.cpp`: `init()`; only `setTextFormat()` lowers it to `NoButton`), so it is a
pointer target, and the wrapper's `childMouseEventFilter` runs for it without asking
`contains()`: the press-and-hold timer starts. The press itself goes on to the desktop,
and so does the release — to the desktop's grabber, never through the filter — so nothing
stops the timer, and a plain click on the text puts the wrapper into edit mode 800 ms
later. Without a mask the wrapper is a target too, takes the grab and stops the timer in
its own `mouseReleaseEvent`; outside the mask it is not. `test_10` shows both halves:
edit mode after 1.2 s with the default text, none with `Text.PlainText`.

So under a partial mask nothing but the buttons may accept the mouse: `textFormat:
Text.PlainText` on every `Text` (`PlayerView.qml`'s `Line` component, the visualizer's
relay notice), or `enabled: false` on a subtree that has nothing to click. The ring's
bars are `Rectangle`s and take no input.

## `containmentMask` coordinates: only the mask's x/y count

`QQuickItem::contains()` does `quickMask->contains(point - quickMask->position())`: the
point is in the masked item's coordinates, only the mask's `x`/`y` are subtracted, and the
mask's parent — or its visibility — is never consulted (`qquickitem.cpp`, Qt 6.11.2). So
the mask `Item` may live anywhere in the tree, invisible, as long as its `x`/`y`/size are
the rectangle in the wrapper's coordinates; and the mask gates the wrapper only, not its
subtree — a `MouseArea` is hit by its own geometry. `test_16` shows both with a padding of
20 on the container: the content and the buttons move to 60..180, both masks stay at
40..160, a click at 50 is taken by the wrapper and one at 170 by the buttons. Hence
`maskRect()` in the two hosts: the row's rectangle mapped into `root.parent` for the
wrapper and into `root` for the `PlasmoidItem`, the positions along the chain read first
so the binding follows a move. Declaratively, `containmentMask: …` loads on an
`ItemContainer` (`test_17`) — it is the `PlasmoidItem` that refuses it, the gotcha above.

## On the stand, edit mode reorders the containers

A release in edit mode changes the stacking: `ItemContainer::mouseReleaseEvent` calls
`AppletsLayout::positionItem`, and the grid manager then stacks the container before a
sibling to its right or below (`GridLayoutManager::assignSpaceImpl`, "Reorder items tab
order") — on the stand the masked "row" ended up under the "beneath" applet, whose
`MouseArea` then took everything, and later clicks went there for a reason that had
nothing to do with the mask. `resetRow()` re-parents the container (`parent = null`, then
back to the layout), which appends it last, on top again, and restores its geometry.
Worth knowing for any test that lets an `ItemContainer` enter edit mode.

## A bare `i18n()` in a shared file follows the host's domain

`player/shared/PlayerView.qml` is copied into two packages, and its strings go through a
bare `i18n()`. That call resolves through the translation domain of the plasmoid that
loaded the copy: the same file shows the player's catalog inside plainplayer and the
visualizer's inside plainspectrum. Verified 2026-09-23. So `po/extract.py` lists
`player/shared` under both domains, and a string added there lands in two catalogs —
forget one and the visualizer shows English where the player is translated. This is the
opposite of `monitor/shared/`, whose `KI18nContext` carries a hard-wired domain: the
pattern for a file with two hosts is the bare call.

## `barRow` labels are three characters

`barRow(label, value)` pads and cuts the label to three characters so the percentage column
stays put — the disks block asked for `root` and got `roo`. The row now takes an optional
label width: the disks pass four, and the bar gives up one character (`bar(value, width)`)
so the column does not move. Four fits `root`, `home`, `data`, `boot`; a longer last path
element is cut. The root mount is `root` rather than `/` on purpose: the bar beside it is
made of slashes too, and `/   //` read as one thing.

## QML's JavaScript has no time zones: `toLocaleString` ignores `timeZone`

Qt's JS engine has no `Intl` — `typeof Intl` is `undefined` — and the `timeZone` option
is silently dropped: `d.toLocaleString("en-US", { timeZone: "Asia/Tokyo" })` prints the
machine's own 17:00 for an instant that is 21:00 in Tokyo, no error. Verified 2026-09-23
with `/usr/lib/qt6/bin/qml`, Qt 6.11. MET Norway's series is in UTC, and cutting it into
the place's days needs the place's offset — the machine may sit in another zone. What
has it is Plasma's `time` engine (`org.kde.plasma.plasma5support`): any IANA name is a
source there, and its `Offset` is that zone's current offset from UTC in seconds, daylight
time included; a name it does not know gets the machine's offset (verified the same day).
The weather widget connects a second `DataSource` to the `timezone` the geocoder stored
and shifts the UTC instants by that offset before taking the date (`localDate` in
`Sources.js`). A typed or guessed place has no zone, and the machine's is used.

## MET Norway answers 403 to the default `User-Agent`

Qt's `XMLHttpRequest` sends `Mozilla/5.0` unless told otherwise, and `api.met.no` answers
403 to that: their terms require a User-Agent that names the application. Qt lets
`setRequestHeader("User-Agent", …)` set it, so the source sends
`plainweather/0.1 github.com/highscrren-dotcom/plaintop` and gets 200 — verified
2026-09-23 in the widget for Berlin and Yekaterinburg, and again with `curl -A`: 403 with
`Mozilla/5.0`, 200 with the widget's string. Their terms also cap the coordinates at four
decimals; `build()` rounds.

## A 304 has no body — never `JSON.parse` it

With `If-Modified-Since` set to the last `Last-Modified`, `api.met.no` answers 304 when
nothing changed: `status` 304, `responseText` empty (`body=0` with curl). `JSON.parse("")`
throws, so a handler that parses first and looks at the status after counts "nothing new"
as a failure and starts backing off. The widget parses on 200 only; on 304 it keeps what is
shown, takes the new `Expires` and reports the answer as fresh. `Expires` is read against
the server's own `Date` header, not the machine's clock, and the next request waits for it
— plus 5 s, and at most an hour whatever the header says. Verified 2026-09-23: the second
request for the same place answered 304, and the server's `Expires` was about 30 minutes
out.

## Visual Crossing answers fifteen days when no dates are named — and bills them

The Timeline API without a date range in the path returns fifteen forecast days, and the
free plan counts every day in an answer as a record, of a thousand a day: three rows
shown, fifteen billed, per request. So `build()` names its dates — today to today plus
`days − 1`, in the place's local date — and the source refreshes every 30 minutes instead
of 15. ⚠️ This one is from Visual Crossing's documentation, not from a run: no real key
was available, and what was verified is a bogus key (401 → `· bad key`) and the parser on
a sample response. Recorded because it changes the request's shape.

## "offline" in the weather header may be the network, not the widget — and the source is a setting

On the author's machine the header showed `· offline` for a while although the search on
the *Location* page still worked: the tunnel's exit was in Russia, and from there TCP to
`api.open-meteo.com` did not connect at all, while `geocoding-api.open-meteo.com` — a
different host, at a different hosting company — and `api.met.no` answered (measured
2026-09-23, and again while writing this: a connection timeout on the one, 200 on the
others). The widget kept the cached forecast and went on retrying on its backoff, as
decision 10 says it should. A network fact, not a widget one; recorded so the next "the
weather is broken" starts with the network — and it is why the widget has four sources
(decision 13): when the one in use is cut, *Source* on the *Location* page switches to
another, MET Norway without a key.

## A change handler sees derived bindings before they update

`onDaysChanged` compared the derived `dayCount` (a binding on `days`) with the rows it
had — and always saw the old value: a handler connected before a binding runs before that
binding re-evaluates. Raising the day count never refetched. Compare the source value the
handler is about, or defer with `Qt.callLater`.

## A 304 is not "nothing changed" for a forecast cut at the request hour

met.no answers 304 to `If-Modified-Since` for as long as its model did not run (35 min
to an hour and a half), but every 200 body starts at the hour of the request. Keeping the
last parse on a 304 froze "now" and the day rows at the hour of the last 200, and bumping
the age hid it. The widget keeps the raw body of the last 200, re-parses it on a 304 from
the entry covering the current hour, and sends `If-Modified-Since` only while that body is
in memory.

## At 3 px, `Text.QtRendering` blurs the dots — and the software backend hides the difference

The weather icon is 24 rows of characters at 3 px, each character one dot of the picture.
With `renderType: Text.NativeRendering` that is what comes out: glyphs hinted to the pixel
grid, even grey dots. With the default `Text.QtRendering` — a distance field scaled down
to 3 px — every character smears into its neighbours with coloured fringes, and the
picture is a blur. ⚠️ Only a real GPU scene graph shows this: `plasmawindowed` on the
offscreen platform runs Qt Quick's software backend, where both render types go through
the same raster path and the two pictures are identical — a comparison there says "no
difference" and is wrong for the desktop. Compare under the RHI, `QSG_RHI_BACKEND=opengl
QT_QUICK_BACKEND=rhi`, or on the live desktop. The icon's `Text` is `NativeRendering`,
like every line of the widgets. Verified 2026-09-24.

## `lineHeightMode: FixedHeight` below the natural line: `implicitHeight` is one line too tall

A `Text` of n lines with `lineHeightMode: Text.FixedHeight` and a `lineHeight` smaller
than the font's own line does not measure n × fixed. Its `implicitHeight` is
(n − 1) × fixed + natural: the rows are packed, but the last one is counted at the natural
height. The icon at 3 px measures 73 px, not 72 (23 × 3 + 4); at 4 px 98, at 5 px 122. A
box sized from `implicitHeight` is a line taller than the picture. Size the box yourself —
rows × fixed — as `iconHeight` does in `WeatherView.qml` and `main.qml`; the glyphs of the
last row hang one pixel below it, into the next line's empty top. Measured with
`/usr/lib/qt6/bin/qml` on the offscreen platform, Qt 6.11, 2026-09-24.

## The natural line of a 3 px `NativeRendering` `Text` is 4 px

`font.pixelSize: 3` with `renderType: Text.NativeRendering` gives a line 4 px tall —
hinting rounds the line, as it rounds 10 pt to 18 px (above); 4 px gives 6, 5 px gives 7.
A picture stacked at the font's own line height is a third taller at 3 px than its
characters say, half again at 4, and the cell the generator draws for (0.6 wide for 1
tall: 1.8 × 3 px) no longer holds — discs come out tall. So the icon packs its rows at
exactly `iconSize` — `lineHeightMode: Text.FixedHeight` with `lineHeight` equal to the
pixel size — and is 24 × `iconSize` pixels tall: 72 at the default, four lines at 10 pt.
Measured the same way, 2026-09-24.
