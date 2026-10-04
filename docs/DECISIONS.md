# Project decisions

English · [Русский](DECISIONS.ru.md)

Recorded with the reasoning, not just the outcome: a month later it matters more to
understand "why" than "what".

## 1. Widget engine — a KDE plasmoid, not conky (2026-09-20)

**Decision:** the target implementation is our own Plasma 6 plasmoid in QML.
The conky implementation stays working until it is replaced and lives in `conky/`.

**Why not conky.** It works, but every one of its quirks under KDE cost us time,
and none of them would be a problem for a plasmoid:

| What hurt with conky | With a plasmoid |
|---|---|
| No click-through — we killed the input region through X Shape | Configurable: input off on the representation, see the correction below |
| X11 only, goes through XWayland | QML natively, Wayland with no layer in between |
| Three autostart sources, three reboots to find them | KDE places the widget itself and keeps it in the session |
| `own_window_type` breaks transparency | Not an issue |
| Its own config language instead of a structure | QML plus the plasmoid's built-in config |

Details on each point — `GOTCHAS.md`.

⚠️ **Correction, 2026-09-21.** That row used to claim a desktop plasmoid "does not
intercept clicks by design". It was written from memory, never executed, and the desktop
contradicted it. What is actually true, after four attempts: turning input off on the
representation (`clickThrough`, with `install.sh --clicks-on` / `--clicks-off` behind it)
hands over the **right** button, so the desktop's menu opens through the widget — and the
**left** button stays with the applet container no matter what, including with the widgets
locked. Details and the table of attempts: `GOTCHAS.md`. Compared with conky this is still
better, but it is half a click-through, not a free one.

⚠️ **Note, 2026-09-22.** Since decision 8 the left button passes too: outside edit mode
the plasmoid disables the wrapper, so this is no longer half a click-through.

**And the main argument.** Plasmoids have a **built-in settings window**: Plasma builds
the dialog itself from `config/main.xml` and stores the values. So the editor the project
was started for largely comes for free — instead of a separate PySide6 application that
we would have to write and maintain.

**What we pay.** We will have to build the data sources ourselves. conky ships two dozen
substitutions out of the box: CPU load, top processes, hwmon, NVIDIA, filesystems,
network. In a plasmoid that is either `QProcess`/`executable` sources, or reading `/proc`
and `/sys` from QML. Estimate: a week against a day.

**What softens the price.** Some of the sources are already written in Python and shell
and do not depend on conky: per-NUMA-node accounting (`conky/plainext.lua`), the state of
docker/ollama/updates (`conky/services.sh`). Their logic ports over almost as is.

**What the decision does NOT change.** The three-layer scheme stays: description
(`schema/widget.json`) → generator → interface. The description says *what to show*,
not *how to write it down* — so changing the engine touches only the generator. That is
exactly why the schema was introduced.

**Revisit if:** it turns out a plasmoid cannot give the text density or the refresh rate
we need without noticeable load. Then conky stays — it works.

## 2. Data — from ksystemstats sensors, not from `/proc` by hand (2026-09-20)

**Decision:** the plasmoid subscribes to sensors through `org.kde.ksysguard.sensors`.
External commands (`sensors -u`, `nvidia-smi`, `ps`) only for what the sensors do not
have, and on a rare interval.

**How we chose.** We took apart four approaches, each one verified by running it on s1dPC:

| Approach | Outcome |
|---|---|
| **ksysguard sensors** | 620 ready-made IDs: `cpu/*`, `gpu/*`, `memory/*`, `disk/*`, `network/*`, `lmsensors/*`, `os/*`. Zero command launches |
| `DataSource{engine:"executable"}` | Works, but it is a fork on every tick: `sensors -u` 25 ms, `nvidia-smi` 29 ms. The engine has no timeout at all |
| `XMLHttpRequest` to `file:///proc/stat` | **Rejected.** Inside plasmashell Qt forbids it; it turns on only with `QML_XHR_ALLOW_FILE_READ=1` for the whole shell — a system-wide setting and weaker access to save 2 ms |
| The `systemmonitor` engine | **Does not exist in Plasma 6.** Verified: `valid: false`. Monitoring moved to ksystemstats |

**What this changes in the price of decision 1.** "We will have to build the data sources
ourselves" turned out to be an overestimate: what we reached for `hwmon`, `nvidia-smi`
and `ps` for in conky, Plasma already computes and hands out by subscription. Our own
commands remain only for docker, ollama and pending updates — `services.sh` was launching
them there anyway.

**What we pay.** A dependency on the `ksystemstats` daemon: it comes up on subscription
(DBus activation) and does not answer instantly — for the first 1–1.5 s a sensor is in
the "loading" state. So at startup we draw a dash, not a zero: a zero would lie.

**On formatting, separately.** We do not use the ready-made `formattedValue` and
`Formatter`: they insert U+200B before "%" and U+2009 before "°C". In monospaced text
that pulls the columns out of line — we format it ourselves.

**Revisit if:** we need values the sensors do not have (GPU fan speed, encoder/decoder,
detailed VRAM per process) — then an `executable` with an interval of a few seconds joins
them, but not instead of the sensors.

## 3. The audio visualizer is a ready-made widget, not ours (2026-09-20)

**Decision:** we do not write a spectrum visualizer. We install
[Plasma Audio Visualizer](https://github.com/luisbocanegra/plasma-audio-visualizer)
and configure it to match the PlainExt look. plaintop stays a text monitor.

**What the reconnaissance found.** Building one is possible and the path is clear — the
numbers below were all measured on s1dPC — but everything we would build already exists
there, and better:

| Measured here | Value |
|---|---|
| Bridge: `parec` capture + numpy FFT, 120 bands, ~45 fps | 4.1% of one core |
| QML client: `Canvas`, 120 ticks, 60 fps | 26.4% |
| QML client: scene items, 60 fps, with rotation | 12.3% |
| QML client: scene items, 30 fps, no rotation | 3.9% |
| HTTP poll at 45/s + JSON parse, no drawing | 6.3% |

So a working ring would cost about 8% of a core — and would still lack what the existing
widget has: it sleeps when there is no sound, pauses over a fullscreen window, offers
three styles times circle mode, and ships a C++ plugin for the data path instead of an
HTTP poll.

**What we keep from the reconnaissance.** Two facts that outlive this decision and are
recorded in `GOTCHAS.md`: `XMLHttpRequest` to `http://127.0.0.1` **is** allowed inside
`plasmashell` (only `file://` is refused), and animating a transform costs more than the
data it animates — the same ring is 3.9% standing still and 12.3% spinning.

**What we pay.** Three runtime dependencies (`cava`, `python-websockets`,
`qt6-websockets`), somebody else's release pace, and GPL-3.0: we configure that widget,
we do not copy its code into this GPL-2.0-or-later repository.

**Revisit if:** the widget stops being maintained, or its circle mode cannot be pushed
close enough to the PlainExt look.

## 4. The visualizer is ours after all — the ready-made one was expensive (2026-09-20)

**Decision:** decision 3 is reversed by measurement. We ship our own visualizer,
`spectrum/`, and keep `cava` as the source. The revisit condition written into decision 3
triggered the same day it was recorded.

**What decision 3 missed.** It weighed the data path and the feature list, and never
measured the *rendering*. Plasma Audio Visualizer draws on a QML `Canvas`: the picture is
rasterized by the CPU and uploaded as a texture every frame, so its cost scales with the
drawn area — and the target here is a ring the size of half the desktop.

Measured on s1dPC, same audio, same machine:

| | CPU | GPU |
|---|---|---|
| Ready-made widget, small, 60 bars, 30 fps | ~15% of a core | +31 points |
| Ready-made widget, leanest: 40 bars, 10 fps | ~13% | +8 points |
| `Canvas` renderer, 1100 px, 160 ticks, 60 fps | 56.4% | +31 points |
| **Ours**: scene items, 1100 px, 160 ticks | 6.8–16.4% | ~0 |
| Ours, installed: plasmashell (both widgets) + cava + relay | 21.7% total | 0.5% |

The difference is not cleverness, it is where the drawing happens: scene items are moved
by the graphics pipeline as ready-made rectangles, and a `Canvas` is repainted pixel by
pixel on the CPU first.

**Two details that cost the most and are worth keeping in mind.** `monstercat` smoothing
inside cava took 27% of a core at 110 bars — off, it is 2–3%. And interpolating between
data frames in JavaScript cost 20% of a core; the same smoothing as a Qt `Behavior`
animation costs 7%, because it runs in C++.

**Explicit choice:** the user asked for the GPU to be left alone, so the renderer stays on
scene items and no shader path is taken, even though a shader would be cheaper still.

**What we pay.** Our own code to maintain, and `cava` plus a small relay service as
runtime dependencies.

**Revisit if:** the CPU cost becomes a problem on a weaker machine — then a shader
renderer is the next step, and it is a renderer swap, not a redesign.

## 5. The visualizer gets a second host: a click-through window (2026-09-21)

**Decision:** the ring also runs as a plain window with `Qt.WindowTransparentForInput`,
with its own settings editor. The plasmoid host stays, installed but not placed once the
window is set up. The renderer and the data side move to `spectrum/shared/` and are used
by both.

**Why.** The user's own observation split the problem in half: a right-click reaches an
icon through the widget, a left-click does not. Four attempts to free the left button all
failed — the table is in `GOTCHAS.md` — because the applet container keeps it for
press-and-hold. A window with that flag caught **zero** clicks while being clicked, so it
is the only way to a desktop widget you can click straight through.

**What it costs, and what pays for it.**

| | Plasmoid host | Window host |
|---|---|---|
| Left button through the widget | never | yes |
| Settings dialog | Plasma's, for free | ours: `window/settings.qml` |
| Position and size | the containment resets it | a KWin rule, because Wayland forbids self-placement |
| Autostart | KDE keeps it in the session | our own `.desktop` |
| Drawing and data | shared files, identical | shared files, identical |

**This reverses one thing from decision 1**, which counted on Plasma's dialog making a
separate editor unnecessary. For the window host there is no such dialog, so the editor is
ours after all — 350 lines of QML with a live preview, next to the widget rather than
instead of it.

**Who owns the settings.** The relay. QML cannot write files, so the editor reads
`GET /config` and posts to `POST /config`, and only the relay writes `ring.json`. Two
writers on one file is the mistake this project already paid for with `~/.config/conky`.

**Revisit if:** KDE gives an applet a way to decline the left button — then the window
host, its KWin rule and its autostart all become unnecessary, and the editor stays useful
anyway.

⚠️ **Note, 2026-09-22.** The condition arrived, though not the way it was written: KDE
gave nothing, the plasmoid lets the left button through itself — decision 8. The reason
the window hosts were created is gone, but their placement (a KWin rule) and autostart
still differed from the plasmoid's, and whether to retire them was the user's call — for
a few hours an open question in `STATE.md`, not a decision. **Resolved the same day by
decision 9: the window hosts are retired.**

## 6. Sensors are discovered, not written down (2026-09-21)

**Decision:** no machine-specific sensor id lives in the code any more. Block parameters
carry a **preference**, the vocabulary carries the pattern that finds a replacement, and
`monitor/shared/SensorRegistry.qml` enumerates what the machine actually reports. The
editor offers that list instead of asking the user to know an id.

**Why.** Three readings went quiet at once without a single error: a reboot renumbered the
drive (`nvme-pci-0500` → `nvme-pci-0600`), the network interface was renamed
(`enp4s0` → `enp5s0`), and the per-core temperatures had been latched from the count of
physical processors instead of the count of cores. Nothing was broken — the config simply
described hardware that no longer answers by those names. The same config on anyone else's
machine describes nothing at all, which made the widget unusable outside this one desktop.

**How it resolves.** A stored id wins when the machine still has it; otherwise the pattern
picks the first match. So an id typed by hand keeps working, a stale one heals itself, and
a fresh install with empty parameters finds its own sensors.

**The editor side.** A parameter in `schema/blocks.json` may declare `pick`: `sensor` with
a `pattern`, `iface`, or `mount`. The editor reads that field and offers a searchable list
of the 664 sensors this machine reports — narrowed to the 5 that match a fan pattern — with
the highlighted sensor's live value under the list, plus the mount points from
`/proc/self/mounts` and the interfaces found in the tree. Nothing about a block type is
hardcoded in the editor: the vocabulary says what can be chosen.

⚠️ **Note, 2026-09-22.** That editor was the window host's (`window/settings.qml`), retired
by decision 9. Discovery itself is untouched — it lives in the shared `SensorRegistry` and
`MonitorData`, and an empty parameter still means "find it" — but the plasmoid's *Blocks*
page offers a plain field for these parameters, not the lists. Bringing the pick lists into
Plasma's dialog is open work, not a decision.

**What we pay.** One `Sensors.Sensor` object per non-uniform sensor instead of one shared
model — the model cannot be trusted with ids it may drop (see `GOTCHAS.md`) — and a poll of
the sensor tree that slows to once every 10 s once the list settles. Measured cost of the
monitor stayed where it was.

**Revisit if:** a machine shows up where the tree is large enough that enumerating it is
noticeable; then the registry caches to disk and refreshes on demand.

## 7. Translations — KDE's own ki18n, the language follows Plasma (2026-09-22)

**Decision:** every user-visible string goes through ki18n with gettext catalogs, one
domain per widget — `plasma_applet_org.s1dd1.plaintop` and
`plasma_applet_org.s1dd1.plainspectrum`. The source strings are English; Russian becomes a
translation like any other. Files that only the plasmoid loads call `i18n()` directly;
QML shared by both hosts and the window hosts' own files call it through a `KI18nContext`
(`import org.kde.ki18n`) with the same domain, since the bare `qml6` runner has no
`i18n()` of its own. The catalogs live in `po/`; the install compiles them with `msgfmt`
into the plasmoid package (`contents/locale`) and, for the window hosts, into
`~/.local/share/locale`.

**Why this and not a dictionary of our own.** The alternative was a JS dictionary
generated from the same `.po` files, which would have given a per-widget language switch
that works without a restart. The user dropped the switch as a requirement, and without
it ki18n wins on everything else: it is the standard path for Plasma widgets and for the
KDE Store, translators get the tools they already use, and plural forms come from each
catalog's own rules — "1 обновление, 3 обновления, 5 обновлений" needs no code of ours.

**Verified before anything was converted:** a throwaway plasmoid run in `plasmawindowed`
(the same libplasma as plasmashell) translated from its `contents/locale` through bare
`i18n()`, through `KI18nContext`, and from a separate shared component, with Russian plurals
right for 1, 3 and 5; with `LANGUAGE=en` it fell back to the English source strings.

**What we pay.**
- The language is Plasma's (System Settings → Region & Language) and changes after the
  shell and the windows restart; a widget cannot have a language of its own.
- `KI18nContext` needs KDE Frameworks 6.23 or newer; on an older Plasma 6 the window hosts
  and the shared QML will not load.
- The install needs `msgfmt` from gettext.

**Revisit if:** a per-widget language becomes a requirement, or `KI18nContext` turns out to
be missing where the widgets have to run. Then the dictionary generated from the same `.po`
files replaces ki18n, and the catalogs stay as they are.

⚠️ **Note, 2026-09-23.** One shared file now has two plasmoid hosts rather than a plasmoid
and a window: `player/shared/PlayerView.qml`, drawn by the player and by the visualizer.
It calls bare `i18n()`, which resolves through the domain of whichever plasmoid loaded the
copy, so `po/extract.py` lists `player/shared` under both domains — decision 12 and
`GOTCHAS.md`.

## 8. The left button goes through: the plasmoid disables its own wrapper outside edit mode (2026-09-22)

**Decision:** with `clickThrough` on, each plasmoid disables the container plasmashell
wraps it in — `root.parent.enabled` set to `false` from the applet's own QML — and
re-enables it while the shell's edit mode is on. Both mouse buttons then land on the
desktop; in edit mode the wrapper is enabled again (verified over DBus), so the shell's own
move, resize and configure handles apply.
`monitor/package/contents/ui/main.qml` and `spectrum/package/contents/ui/main.qml` carry
the same `Binding { target: root.parent; property: "enabled" }` driven by
`!clickThrough || shellEditMode`, where `shellEditMode` reads
`Plasmoid.containment.corona.editMode`. The representation keeps `enabled: !clickThrough`
as before, so in edit mode the wrapper takes the mouse, not the widget. The right button
needs one thing more, an empty `containmentMask` — *The right button* below.

**Why the left button never passed.** plasmashell wraps every desktop applet in an
`AppletContainer` — the QML `BasicAppletContainer` over the C++ `ItemContainer`
(`plasma-workspace/components/containmentlayoutmanager/itemcontainer.cpp`). Its
constructor does `setFiltersChildMouseEvents(true)` (line 27),
`setAcceptedMouseButtons(Qt::LeftButton)` (line 30) and `setKeepMouseGrab(true)`
(line 51). `ItemContainer::mousePressEvent` (lines 552–583) ends in `event->accept()`
(line 582) for every `editModeCondition` except `Manual`, which returns early
(lines 556–558) — but Qt pre-accepts a mouse event before delivering it
(`qquickdeliveryagent.cpp`, `deliverMatchingPointsToItem`: `pointerEvent->accept()`
right before `QCoreApplication::sendEvent`), so `Manual` keeps the press too. `Locked` —
what locking the widgets gives: the desktop containment sets it when `Plasmoid.immutable`
(`plasma-desktop/containments/desktop/package/contents/ui/main.qml` lines 321–323), and
`ItemContainer::editModeCondition()` (lines 149–153) returns it when the layout is locked
— still reaches `event->accept()`. That is all four failed attempts from `GOTCHAS.md` in
one place. The right button passes only because the container accepts `Qt::LeftButton`
alone.

**Why the desktop below is free.** Beneath the container, `AppletsLayout::mousePressEvent`
(`appletslayout.cpp` lines 606–617) calls `event->setAccepted(false)` unless some
container is in edit mode, so a press the container does not take continues to the folder
view and the containment.

**Why disabling works.** Qt's `eventTargets` (`qquickdeliveryagent.cpp`) skips a child
that is `!isVisible() || !isEnabled() || culled` — a disabled item and its whole subtree
are never mouse targets. The applet is the container's `contentItem` and a direct child
(`ItemContainer::setContentItem`: `item->setParentItem(this)`), so from the applet's root
`parent` *is* the `AppletContainer`, and `QQuickItem`'s `enabled` is a public property
writable from QML. Edit mode is readable through public properties too:
`Plasmoid.containment` (`applet.h:219`) → `.corona` (`containment.h:62`) → `.editMode`
(`corona.h:41`).

**The right button (the same day, later).** With only the wrapper disabled, a right-click
over the widget still opened the widget's own menu: the desktop builds its context menu
after a geometric lookup, not from mouse delivery. `ContainmentItem::mousePressEvent`
(libplasma, `src/plasmaquick/plasmoid/containmentitem.cpp`, under the comment "FIXME: very
inefficient appletAt() implementation") loops over every `PlasmoidItem` and takes the first
with `ai->isVisible() && ai->contains(ai->mapFromItem(this, event->position()))` — it never
looks at `enabled`. What `QQuickItem::contains()` does consult is the item's
`containmentMask` (qtdeclarative, `qquickitem.cpp`: with a `QQuickItem` as the mask,
`return quickMask->contains(point - quickMask->position())`). So both `main.qml` files set
an empty 0×0 `Item` as the `PlasmoidItem`'s `containmentMask` while click-through is on and
the shell is not in edit mode; `contains()` then answers "no", and the desktop shows its own
menu, as if the widget were not there. ⚠️ Written declaratively, `containmentMask: …` on a
`PlasmoidItem` fails to load (a QtQuick 2.11 revision the `org.kde.plasma.plasmoid` module
does not import), so it is set through a `Binding` by name — the gotcha is in `GOTCHAS.md`.
Verified: the stand got `test_09` — a `Binding` by name sets `containmentMask` on an
`ItemContainer` and `contains(Qt.point(50, 50))` flips true → false → true, 11 of 11 pass;
on the real desktop both widgets pass the right button as well, with music playing, and the
visualizer loaded without QML warnings.

**What we pay.**
- While click-through is on, the widget cannot be grabbed, right-clicked or configured
  from the desktop: the only way in is the shell's edit mode (or
  `./install.sh --clicks-off`). The hint in the monitor's settings says so.
- A private detail of plasmashell is relied on: the wrapper type and its property
  `editModeCondition`, which the `Binding`'s `when` uses as the guard — the same guard
  keeps `plasmawindowed` and previews untouched. Verified on Plasma 6.7.5 (Frameworks
  6.30, Qt 6.11.2); a newer Plasma must be re-checked with the stand.

**Verification.**
- Stand, 10 of 10 passed: a `qmltestrunner` scene that instantiates the installed
  `org.kde.plasma.private.containmentlayoutmanager` (`AppletsLayout` + `ItemContainer`)
  over a counting `MouseArea` reproduces today's behaviour (left swallowed, right passes),
  shows `Locked` and `Manual` still swallow, shows `enabled: false` on the container
  passing both buttons to the desktop and to an applet beneath, re-enabling restoring
  capture, and no press-and-hold edit mode while disabled.
- Real desktop: a throwaway applet, two instances, one with the binding. Clicked by the
  user with the real mouse, the normal one counted 30 presses, the pass-through one 0, and
  the clicks reached the desktop. Edit mode toggled over DBus (`org.kde.PlasmaShell`,
  `editMode`) re-enabled the wrapper; leaving it disabled the wrapper again.

**Revisit if:** KDE changes the wrapper — its type, its place as the applet's parent, or
`editModeCondition` goes away — or offers an official way for an applet to decline the
mouse. Then use that and drop the binding. If hover or keyboard input inside a
click-through widget is ever needed: an empty `containmentMask` on the wrapper itself
instead of `enabled: false` keeps the applet subtree enabled (research of 2026-09-22,
7 of 7 on a stand, not yet on the desktop).

⚠️ **Note, 2026-09-23.** Built: the player and the visualizer do exactly that, with a mask
over the controls row — decision 11, implemented.

## 9. The window hosts are retired — the plasmoid is the only host (2026-09-22)

**Decision:** the click-through window hosts of both widgets — `monitor/window/` and
`spectrum/window/` — are retired. In the user's words: "старые виджеты оконные отключи, к
ним больше не возвращаемся" — switch the old window widgets off, we are not coming back to
them. One host, the plasmoid; one editor, Plasma's own settings dialog. Both
`window/setup.py` got a `retire` action — it stops the window and removes the autostart
entry, the editor's menu entry, the host's own KWin rule, the deployed files under
`~/.local/share/<name>/ui` and the window's copies of the catalogs under
`~/.local/share/locale`; the settings file stays — and `install.sh` got `--windows-off`,
which runs both. Executed on s1dPC: both windows stopped, everything removed, and
`./install.sh --status` prints "retired — the plasmoid is the only host" for each.

**Why.** The window hosts existed for one reason, the left button (decision 5). Since
decision 8 the plasmoid lets both buttons through by itself, so a second host with its KWin
rule and its autostart adds nothing — and keeps costing: a rule for its place, an editor of
its own, and a second copy of the shared QML to keep from drifting. This closes the open
question left under decision 5.

**What we pay.**
- The window code lingers in the tree like `conky/`: retired, not deleted; deleting it is
  a later cleanup. `--plaintop-window`, `--plaintop-settings`, `--plaintop-export`,
  `--spectrum-window` and `--spectrum-settings` still exist in `install.sh` but are not to
  be used.
- A KWin rule and an autostart entry are no longer written; the settings files
  (`~/.config/plaintop/monitor.json`, `~/.config/plainspectrum/ring.json`) stay where they
  are.
- The pick lists of the window editor (decision 6) are gone from the installed UI until
  Plasma's dialog gets them.
- The relay is **not** retired: the plasmoid needs it for cava (`spectrum/relay.py`,
  `plainspectrum-relay.service`).

**Revisit if:** a host outside plasmashell is ever needed again — another desktop
environment, for instance. The code is still there to start from.

**Executed 2026-10-05.** The window hosts' code (`monitor/window/`, `spectrum/window/`,
their editors and `setup.py`), the conky implementation (`conky/`) and the relay's settings
storage that served the editors left the tree; `install.sh` lost `--windows-off`,
`--plaintop-window`, `--plaintop-settings`, `--plaintop-export`, `--spectrum-window`,
`--spectrum-settings`, `--conky-*` and `--check-input`, and the bare call prints the usage
instead of deploying conky. The branch `archive/2026-10-05-conky-window-hosts` holds the
last tree with all of it. The catalogs dropped the sixty strings only those files used.

## 10. The weather comes straight from QML — no relay (2026-09-23)

**Decision:** the weather widget asks Open-Meteo itself, with `XMLHttpRequest` from its
own QML: one request for the current conditions and the daily forecast every 15 minutes, a
10 s watchdog (`Timer` + `abort()`, since Qt's XHR has no timeout), backoff
1 → 2 → 4 → 8 → 15 minutes after a failure, and the last answer cached in
`Plasmoid.configuration` (`lastWeather`, `lastFetched`) so the widget draws at once after a
shell restart. No service of its own: the package is the whole install.

**What was verified first.** An https request to a public host works inside a plasmoid —
run in an isolated Plasma host on 2026-09-23. Only `file://` is refused (`GOTCHAS.md`), and
`http://127.0.0.1` was already known to work from the visualizer.

**Alternatives, and why not.**

| Approach | Why not |
|---|---|
| A relay like the visualizer's | The visualizer has one because cava is a process that has to run somewhere. The weather is an https GET that QML can make itself; a relay would add a systemd unit, a second install step and a second place to break, for nothing |
| Plasma's own weather | The applet in kdeplasma-addons compiles its QML into a C++ plugin, so nothing of it is importable; the `weather` DataEngine lives in plasma5support — the Plasma 5 compatibility layer — is bound to stations rather than coordinates, and returns pipe-separated strings |
| IP geolocation for the place | Rejected on purpose: a request to a third party that says where the machine is, and behind a tunnel it names the tunnel's exit. The place comes from a city search through Open-Meteo's geocoder (results by population, a click stores lat/lon/name), typed coordinates, or — until one is set — a one-time guess from the Plasma time engine's "Timezone City", kept apart and marked in the header |

**What we pay.**
- Qt's XHR quirks are handled in the widget: no timeout, `status` unreadable before DONE,
  an aborted request indistinguishable from a failed one — each is an entry in
  `GOTCHAS.md`.
- Every widget instance fetches on its own: two instances, two requests. One instance
  makes 96 requests a day against Open-Meteo's 10 000 free ones.
- Open-Meteo's terms: non-commercial use, and CC BY 4.0 asks for attribution — the
  "Weather data by Open-Meteo.com" line, on by default.

**Revisit if:** Plasma ever sandboxes network access for plasmoids, or several widgets need
the same data — then a relay like the visualizer's, and the widget's fetch layer becomes its
client.

⚠️ **Note, 2026-09-23.** The choice stands and now covers four hosts: the widget asks
whichever of Open-Meteo, MET Norway, WeatherAPI.com or Visual Crossing is chosen in the
settings, still straight from QML, every 15 minutes (30 for Visual Crossing) — decision 13.
Two figures above are Open-Meteo's alone, the 10 000 free requests and the CC BY 4.0
line; each source has its own terms and its own attribution line.

## 11. The player ships clickable; a partial mask is the follow-up (2026-09-23)

**Decision:** the player's *Mouse* setting is off by default, as in the other widgets, and
the widget ships that way on purpose: its controls `<<  >  >>` are `MouseArea`s under text,
and the click-through of decision 8 disables the wrapper and everything inside it, so with
the setting on the controls are dead. The hint on the Mouse page says so. A click-through
player that still takes clicks on its controls row is the follow-up, not this release.

**Why not build the refinement now.** The mechanism exists in outline only. From the
research of 2026-09-22 (decision 8, "revisit if"): a `containmentMask` on the wrapper itself
instead of `enabled: false` keeps the applet subtree enabled — 7 of 7 on the stand, not on
the desktop. The player's version would be:

- a mask rectangle in the wrapper's coordinates covering only the controls row, set on the
  wrapper through a `Binding` by name — the rest of the widget passes both buttons;
- the same rectangle as the `PlasmoidItem`'s `containmentMask`, so the desktop's
  right-click lookup (`contains()`) finds the widget only there;
- `null` in edit mode, as the current bindings already do;
- the stand extended with a sub-rectangle mask before the desktop sees it.

**What we pay.** A player with clicks passing through has no controls; the user chooses
between the two.

**Revisit when:** the passthrough stand covers a sub-rectangle mask — then the follow-up is
built and the choice goes away.

**Implemented 2026-09-23.** The stand covers the sub-rectangle mask, and the follow-up is
built in both hosts — the player widget and the visualizer with the player in its ring
(decision 12). The recipe, as sketched above: with *Mouse* on, the wrapper stays enabled
and gets a `containmentMask` that is an `Item` over the controls row `<<  >  >>`, in the
wrapper's coordinates — Qt evaluates `mask.contains(point − mask.position())`, so only the
mask's x/y and size matter, not its parent or visibility; the same rectangle is the
`PlasmoidItem`'s `containmentMask` for the right button; both `null` in edit mode; both set
through a `Binding` by name, as before. A left click inside the rectangle reaches the
button, outside it lands on the desktop or the widget beneath; hover outside goes to what
is beneath; press-and-hold on a button starts edit mode like any applet; when the row is
hidden — no player, or the controls off — the mask is 0×0 and everything passes. Proven
on `tests/passthrough.qml`, now 17 tests (19 of 19 with init and cleanup,
`./install.sh --check-passthrough`), and on a second, throwaway stand with the real
`PlayerView` inside the compiled `ItemContainer`, 11 of 11. ⚠️ The one trap the stand
found: any item that accepts the left button outside the rectangle — an ordinary `Text`
with the default `textFormat` does — becomes a pointer target, and the wrapper's child
filter arms its press-and-hold timer without checking `contains()`, so a plain click on
the text would enter edit mode after 800 ms; the cure is `textFormat: Text.PlainText` on
every `Text` (or `enabled: false`), and nothing but the buttons may accept the mouse —
`GOTCHAS.md`. Real clicks on the live desktop are still the user's check. **The *Mouse*
setting now means: everything passes except the buttons** — the choice above is gone, and
the hint on the Mouse page says so.

## 12. The player also lives inside the visualizer, as an option — and stays a separate widget (2026-09-23)

**Decision:** the visualizer gets a *Player* page with one switch, "show the player in the
centre of the ring" (`playerShow`, off by default), and under it the player widget's own
settings — filter, album, controls, font, size, width in characters (22 at least), the
three colours — with the same defaults. A `Loader` creates the view only while the switch
is on, so nothing of it, not even the MPRIS model, exists otherwise. The board, `columns`
characters by five lines, is centred on the ring's centre; in the line layout it sits along
the edge the bars reach last — above bars that grow up, below bars that hang down; the ring
keeps its size; with no player on the bus the centre stays empty. The standalone widget
`plainplayer` stays as its own product.

**Why inside the visualizer.** The user wanted the player in the centre of the ring. Two
applets cannot overlap on the desktop: the containment's layout manager hands each one a
free rectangle (`isRectAvailable`), so a player widget dropped on the ring would be pushed
aside. So the view had to be drawn by the visualizer itself.

**How, without a second copy.** The view moved to `player/shared/PlayerView.qml`, the one
source; `install.sh` copies it into `player/package/contents/ui/` (`player_prepare`) and
into `spectrum/package/contents/ui/` (`spectrum_prepare`), the copies are gitignored, and
`--status` compares both with the source — the same arrangement as `monitor/shared/`. The
strings go through a bare `i18n()`, which resolves through the domain of the plasmoid that
loaded the copy, so `po/extract.py` lists `player/shared` under both domains (the note
under decision 7). The mouse is decision 11 in both hosts: with *Mouse* on, the
visualizer's wrapper takes only the controls row.

**What we pay.**
- Two hosts to keep in step: a change to the view is tested in the player and in the ring,
  and the visualizer's `main.qml` carries the player's measuring code (`TextMetrics`, the
  hidden line probe) a second time.
- The strings live in two catalogs: a new string in the view means translating it in
  `plainplayer` and in `plainspectrum`, ten languages each.
- The view's file sits in the visualizer's package whether or not the switch is on.

**Revisit if:** Plasma ever lets applets overlap, or share a containment cell — then the
player widget could simply be placed over the ring and the option goes. Or if the two
hosts drift in behaviour: then the view becomes a QML module of its own rather than a
copied file.

## 13. Several weather sources behind one abstraction (2026-09-23)

**Decision:** the weather widget reads one of four sources, chosen on the *Location* page
(`source`, default `open-meteo`): Open-Meteo and MET Norway without a key, WeatherAPI.com
and Visual Crossing with a free key from the user's own account (`apiKey`; the field shows
only for those two). Every source is an object of one shape in
`weather/package/contents/ui/Sources.js` — `build(lat, lon, days, key, opts)` returns the
URL and headers, `parse(body, days, opts)` returns `{ current, daily }` in metric units
with WMO condition codes — and the view knows nothing else about them: one table of
condition words and one set of translations, one conversion to the user's units (the
Open-Meteo request no longer asks for units either), one cache in the config carrying the
source's id, ignored when the source differs and cleared when the source, the key or the
place changes. The attribution line follows the source — "Weather data by Open-Meteo.com",
"Weather data from MET Norway" (CC BY 4.0), "Powered by WeatherAPI.com", "Weather data
provided by Visual Crossing" — on by default, the checkbox is "show the source's line".
The geocoder stays Open-Meteo's.

Per source. **Open-Meteo:** up to 7 days, as before. **MET Norway:** Locationforecast 2.0
`complete`, an identifying `User-Agent` (`plainweather/0.1 github.com/…`, which Qt's XHR
can set), coordinates rounded to four decimals, `If-Modified-Since` → 304 keeps what is
shown, the server's `Expires` honoured (+5 s, at most an hour); the daily rows are
aggregated from the hourly and six-hourly entries by the place's local date — min and max
of the day, the day's code the worst WMO code of the day — with precipitation probability
only where MET gives it, the Nordic countries, and no "feels like". **WeatherAPI.com:**
the free plan answers three forecast days, so `days` is clamped to 3. **Visual Crossing:**
the free plan is a thousand records a day and every forecast day is one, so the request
names its dates and the source refreshes every 30 minutes instead of 15.

**Why.** Measured 2026-09-23: with the author's tunnel exiting in Russia, TCP to
`api.open-meteo.com` did not connect, while `api.met.no` and Open-Meteo's geocoding host
answered. One source is a single point of failure the user cannot route around; a second
one without a key is the way around it, and once the seam exists, the two keyed ones cost a
parser each.

**States.** A keyed source without a key: one line, "set the API key in the widget
settings". 401 or 403 from a keyed source: `· bad key` in the header and the next try at
the usual interval — the key is wrong, not the network, so no backoff spiral. 429 and
network failures: `· offline` with the backoff of decision 10.

**Alternatives considered, and why not.**

| Source | Why not |
|---|---|
| Yandex Weather | No free API: the test tariff lasts 7 days, then 54 000 ₽ a month; the "smart home" tier gives today and tomorrow only, with unpublished limits; and the agreement forbids caching, requires the Yandex logo and excludes services whose main content is the weather — the cached answer, the plain-text look and a weather widget are each ruled out |
| Gismeteo | Keys only by e-mail, to partners |
| AccuWeather, Foreca | No permanent free tier |
| Tomorrow.io | Blocks the exit IP |
| wttr.in | One person's server, and on Hetzner like Open-Meteo |
| Bright Sky | Germany only |
| NWS | The United States only |
| OpenWeatherMap | The free plan has no daily forecast; One Call needs a card |

**What we pay.**
- Four parsers to keep in step with four APIs. A change on a source's side shows up as
  `· offline` — `parse()` returns nothing the view can draw — not as "the shape changed";
  a field that went missing draws a dash.
- The two keyed sources are untested with real keys: verified are a bogus key (401 →
  `· bad key`) and the parsers on sample responses from the sources' documentation. MET
  Norway is verified live — 200, then 304 on the second request, `Expires` honoured — for
  Berlin and Yekaterinburg.
- Three sets of terms besides Open-Meteo's, each with its attribution line and its hint
  under the forecast settings.
- The place's UTC offset matters now (MET's series is UTC), and QML's JavaScript has no
  time zones: the offset comes from Plasma's `time` engine by IANA name — `GOTCHAS.md`.

**Revisit if:** a source changes its terms or its response shape, or a user reports a
broken parser — then that source is fixed or dropped, and the others keep working: the
abstraction is there so that dropping one is deleting an object. And what decision 10 says:
if Plasma sandboxes network access, a relay, and the sources move into it as they are.

## 14. Active lines in the monitor: the containment mask is a function, not a rectangle (2026-10-04)

**Decision:** the monitor's lines are active by default. A line that has something to do
carries an `action` — a title and items, each a shell command with flags (terminal, held
open, detached GUI program, editor, a question first) or the widget's settings dialog —
attached by `MonitorData` per block type: bars open System Monitor; a disk opens its folder
or a terminal there; a unit shows its status, starts, stops, restarts or opens its journal;
a process is terminated or killed after a question; the updates line runs the package
manager; the sound line toggles mute; a repository opens a terminal, the file manager, the
editor or pulls; the uptime line locks, logs out, reboots or powers off; the header opens
the settings. A left click runs the first item, a right click opens the menu — the calendar
sticker's kind of window: `PlasmaCore.Dialog`, no background, a frame of characters, the
widget's font and palette. The host runs the items (programs that must outlive the
shell detached into a systemd scope of their own, `systemd-run --user --scope` — `setsid`
alone leaves them in the shell's cgroup, which a restart kills whole; attached for quick
commands, whose stderr shows in a notice). Per
block, the fields `active` and `click` (a command of the user's own, first in the menu, with
`{name}` `{pid}` `{path}` `{unit}` `{value}` filled in); on *General*, `actions`, `terminal`,
`editor`, the menu's `frame`, `colorPaper` and `paperOpacity`.

**The mask.** While clicks pass through, the active lines must still take the mouse. The
player's recipe (decision 11) keeps the wrapper enabled and gives it a `containmentMask`
over the controls row — one rectangle. The monitor's active lines are scattered down the
column, with passive lines between them, so one rectangle would either swallow those or
miss some. Qt accepts as a mask any `QObject` with an invokable `contains(QPointF)`
(`QQuickItem::setContainmentMask` looks the method up by signature and invokes it with
the point in the masked item's coordinates). A QML `QtObject` with a typed function —
`function contains(p: point): bool` — publishes exactly that method, and its body asks the
view whether an active line's delegate lies under the point (`childAt()` on the live
columns). Two such objects: one for the wrapper (the left button's delivery), one for the
`PlasmoidItem` (the desktop's geometric lookup for the right button); both `null` in edit
mode and both set by name through a `Binding`, as before.

**Why a function and not rectangles.** A list of rectangles has no home: a mask is one
object, and an Item's `contains()` cannot be overridden from QML. Caching rectangles would
also mean refreshing them after every tick's relayout; `childAt()` reads the live geometry
at the moment of the hit test and costs a walk over some forty children per press or hover.

**What we pay.** The click-through path of the monitor changes from "wrapper disabled"
(decision 8, proven on the desktop) to "wrapper masked by a function" (seen on the
desktop since 2026-10-04) whenever the active lines are on. If Qt refuses the object — the typed function
not exposed as `contains(QPointF)` on this Qt — the mask reads back `null`, a warning is
logged and the host falls back to an `Item` over the active lines' bounding rectangle:
coarser, but click-through holds. With the active lines off, the old path is unchanged.
Hover over the wrapper now calls the function on every move.

**Alternatives considered.** A separate `MouseArea` per action with the wrapper disabled
— impossible, a disabled subtree takes no mouse (decision 8). One rectangle over the whole
column — passive lines would stop passing clicks, which is the point of click-through. A
`containmentMask` per column — still one rectangle each. Making only one block's lines
active — the user asked for lines "for every occasion"; what a line does is data per block
type, and a block can opt out.

**Verified by running:** the line stand, `tests/monitor.qml` 17–21 — actions attached per
block type, off globally and per block, the custom click first with the row filled in,
units with and without `--user`, disks, repositories with the path from the parameter, the
power menu's questions, sound's mute toggle, health's journal and reboot items, the quoting
helpers. `tests/passthrough.qml` test 18 — the function mask on the compiled
`ItemContainer` gates clicks and hover like the rectangle — passed 2026-10-04 (20 of 20).
On the desktop the same day, click-through on: no refusal in the journal; hover frames an
active line and not a separator or a blank one; clicks between the lines and beside the
text reach the wallpaper, a right click on the widget's empty space opens the desktop's
menu; a left click on CPU opens System Monitor, on a disk its folder, on a process the
question; a right click opens the framed menu under the line, keys and a click outside work;
the sound line toggles mute; edit mode moves and resizes the whole widget. Also checked:
`ProcessDataModel` has the `pid` attribute (the fourth column), the five KCM ids exist, and
a program started the way the host starts it survives a restart of the shell.

**Revisit when:** test 18 fails on a later Plasma or Qt — then the fallback rectangle is the mask and the
decision's second half is rewritten; or when a block wants more than one action per line
beyond the menu.

## 15. Reminders in the calendar: the time in the text, VALARM in the data, one sheet at a time (2026-10-04)

**Decision:** a reminder is set by writing, not by a form. A note whose first line starts
with a time — `14:30 Dentist`, `9.00-10.30 Standup` — is saved as a timed event (DTSTART and
DTEND in UTC, an hour long unless a range is given) with a VALARM `remindLead` minutes
before it; `!Buy milk` stays an all-day note with a VALARM at `remindHour` of its day; plain
text stays plain. The accounts' entries ring by their own VALARMs (relative to the start or
the end, or absolute; a relative one on an all-day entry counts from `remindHour`, the hour a
phone would use), and a timed entry without any rings `remindLead` before when
`remindEvents` says so. `notes.py` computes the schedule — every alarm from `remindMissed`
hours back to 36 hours ahead — into the document as `alarms`, each with a key naming the
account, the uid, the occurrence and the alarm's index; acknowledgements and snoozes are
local, in `reminders.json` beside the caches, never written to a server. The widget's clock
looks every half minute, takes the first due alarm, claims it (an exclusive file, so two
instances on two screens show it once) and opens the sheet; the sheet's choice goes back as
`ack`, `snooze MINUTES|ISO` or `done ACCOUNT UID KEY`, each printing the document anew, which
brings the next due alarm. One sheet at a time, in order; a late one is headed MISSED.

**The sheet.** The sticker's kind of window — `PlasmaCore.Dialog`, no background, the
character frame, the widget's font and palette — of type `Notification`: it does not take
the keyboard from what the user is typing, so it is driven by the pointer, hover marking a
row and a click choosing. Rows: the day and the time, the entry, its account, then
`> in 10 min`, `in an hour`, `tomorrow at 09:00`, `done`, and `task done` for a task, which
completes it on its server (GET, STATUS:COMPLETED, PUT with If-Match). It hangs from the
day's cell when the grid shows the day, else from the widget's first line.

**Why the text and not fields.** The project has no forms: a sticker is a sheet of text,
and "14:30 Dentist" reads in the grid as it is typed and round-trips through iCalendar (the
time back from DTSTART, the "!" back from the alarm). A field for the time would be the one
widget in the set with a widget-toolkit control on its face.

⚠️ **Correction, 2026-10-04.** On the desktop the user could not tell how to set a reminder:
the syntax was named only in a dim hint line. By the user's choice the sticker now has two
rows under the note — "time:" with a field for HH:MM, and "remind:" with the choices marked
by `>` (for a timed note none, the settings' lead, an hour before; for an all-day one none
or at the settings' hour). They write the same data: the time and the "!" go back into the
text the script reads, the lead into `--lead`, so the iCalendar and the phone's alarm are as
before, and typing "14:30 …" into the note still works. The field is a `TextInput` with an
input mask, drawn in the widget's font between the frame's characters — the one control on
the face, at the user's word. A note of yours without an alarm now stays silent: the
"events without an alarm" rule counts for the accounts' entries only. The same day, also at
the user's word: a day holds as many notes of yours as you like — the sticker lists them,
a click puts one in the editor, "+ new note" starts another; each is a VEVENT of its own
(the first keeps the uid `plaincalendar-<date>@<host>`, the others add a random suffix), so
each rings and syncs on its own. And a missed reminder cannot slip by: until it is answered
it heads the upcoming lines, marked "!" in the accent, and a click opens its sheet — the
sheet shown once and lost to a restart had no way back before; a timed entry leaves those
lines when its end is past, and the widget reads its document every minute (the accounts
are still fetched every `syncMinutes`).

**Why VALARM and not a schedule of our own.** The data already travel to Yandex, iCloud and
Google over CalDAV; a VALARM in the same resource makes the phone ring with no second
mechanism, and the desktop reads the servers' alarms by the same rule. UTC in DTSTART
avoids a VTIMEZONE for every server.

**Why local ack and snooze.** A snooze is this desktop's business; writing it to the server
would move the event or change the alarm for every device. A week's worth is kept, then
pruned.

**What we pay.** The sheet has no keyboard. A snooze on one machine does not reach another.
Alarms of all-day entries follow `remindHour`, not the server's notion. `--missed` hours of
old alarms are shown on start, one by one — long enough away and they are dropped quietly.
The optional system notification goes through `notify-send`, a dependency the user opts
into; the sound through `pw-play` or `paplay`.

**Alternatives considered.** A form with a time picker — not the project's face. KNotification
from QML (`org.kde.notification`) — needs a `.notifyrc` installed system-wide, which a
plasmoid package does not ship. A daemon of our own — the executable engine already runs the
script every few minutes, and a half-minute clock in the widget is enough.

**Verified by running:** `tests/notes.py`, 114 checks: VALARM and DURATION parsed, when each
rings (relative, off the end, absolute, a day before an all-day entry, the lead), the
schedule with acknowledged and snoozed alarms and the missed window, the timed and the "!"
notes round-tripping through iCalendar, the CLI — set, ack, snooze by minutes and by time,
claim first and second, a task completed on the fake server with If-Match. On the desktop,
2026-10-04: the Notification-type sheet opens by its visualParent — by the day's cell once
the anchor took the day's own month (it had hung from September's copy of the 4th); a
click on "in 10 min" and on "done" reached reminders.json; a snoozed alarm rang again once
a claim was made per ring (it had not); two notes on one day each rang; a missed alarm
comes with MISSED; a timed note to Yandex reached the server with its VALARM; the
notification and the sound commands ran (the sound into a null sink). Now 141 checks. **Not
yet:** that the sheet takes no focus from what is being typed (nobody watched for it), two
instances (the desktop has one), a task closed from the sheet on a real server.

**Revisit when:** the desktop shows the Notification type cannot be placed by an item, or
the sheet needs the keyboard after all — then PopupMenu with `hideOnWindowDeactivate` off.

## 16. Holidays from Plasma's calendar plugin; which are days off from the plans (2026-10-04)

**Decision:** the calendar marks holidays from Plasma's own calendar plugin
("holidaysevents", built on KHolidays: 170 countries and regions), one `Calendar` per shown
month, the regions chosen on our *Holidays* page through Plasma's own helper
(`org.kde.plasma.private.holidayevents`). A day off takes the weekends' colour, any other
holiday its own (`colorHoliday`), and the sticker names the day's holidays. "Days off only"
is the default. Which names are days off comes from the plans themselves: KHolidays marks a
line `public`, and `calendar/holidays.py` reads every plan out of the library and writes
`HolidayKinds.js` (the day-off names, and the name days — left out of "every holiday but
name days", shown with "name days too"). The world days — the UN's and UNESCO's best
known — are a short list of our own.

**Why.** The data are already on every Plasma desktop, kept by KDE, with the Easter,
Hijri, Hebrew and lunar rules a home-made list could not carry. KHolidays' QML module lists
the regions but gives no holidays for a date; the plugin does, and runs inside plasmashell
with nothing else to install. Its events say nothing about kind — a day off and a
professional day look alike, and Russia's plan alone has some two hundred lines — so the
`public` flag is taken from the plans at build time.

**What we pay.** The region choice is one file for the whole shell
(`~/.config/plasma_calendar_holiday_regions`): it is the clock calendar's choice too, and the
page says so. Holiday names arrive as the plans spell them; the day-off test matches names,
and a dozen names are a day off in one region and not in another. The day-off list must be
regenerated after a KHolidays update (the plans are Qt resources in the library, read by a
throwaway QML host allowed to read files). The plans' own gaps stay ours: Russia's day-off
transfers end in 2024.

**Alternatives considered.** Our helper parsing the plans in Python — the plans are a full
grammar (Easter, Hijri, Hebrew, conditions); not worth it. A child Qt process per widget
with its own config — per-widget regions, at the price of a Qt binary called from a stdlib
helper. A hand-made holiday list — goes stale, and covers few countries.

**Verified by running:** the generator reads all 170 plans (1507 day-off names, 732 name
days) and gives the same file twice; in a bare QML host with de_de and ru_ru chosen, the
days off of October–December 2026 are exactly the German and Russian ones, "every holiday"
adds the observances (День учителя), name days stay out; on the desktop with nothing chosen
(the locale's ru_ru) the 4th of November is in the weekends' colour, and with world days on
the 5th and the 24th of October are in the holiday colour; the sticker lists a day's
holidays under its title. The page, with real clicks in `qmltestrunner`: a tick writes the
region to the shared file and into the chosen list, its button drops it and clears the
tick; with Greece's name days and Russia chosen, November 2026 has 1, 11 and 33 entries
for the three choices.

**Revisit when:** KHolidays' QML module learns to give holidays for a date, or the plugin
marks the kind of a holiday — then the generator goes; or a per-widget choice is asked for.


## 17. Windows: the same five widgets on a bare Qt, behind QML-only shims, with one local service (2026-10-05)

**Decision:** the five widgets run on Windows 11 from this repository, with the look and
the behaviour of the plasmoids, and without a line of C++ of our own:

- **The hosts** are `qml.exe` from Qt 6.11 running `win/host/<widget>.qml` — one process
  and one window per widget: frameless, transparent, `Qt.Tool`, `Qt.WindowStaysOnBottomHint`,
  and `Qt.WindowTransparentForInput` while the *Mouse* setting lets clicks through. That is
  the archived window host of decision 5 (`monitor/window/window.qml`, 2026-09-21) on
  another OS; the reason it was retired on Plasma (decision 9: the plasmoid can let the
  mouse through itself) does not exist on Windows, where there is no plasmoid.
- **The shared QML is not touched.** `MonitorData.qml`, `MonitorView.qml`,
  `SensorRegistry.qml`, `PlayerView.qml`, `WeatherView.qml`, `CalendarView.qml`,
  `Sticker.qml`, `Reminder.qml`, `Ring.qml`, `Spectrum.qml` and the monitor's `ActionMenu.qml`
  are copied in by `win/build.py` as `install.sh` copies them into the packages. The Plasma
  modules they import exist on Windows as QML-only stand-ins under `win/host/imports/`:
  `org.kde.ksysguard.sensors` (`Sensor`, `SensorDataModel`, `SensorTreeModel`),
  `org.kde.ksysguard.process`, `org.kde.kitemmodels`, `org.kde.plasma.plasma5support`
  (`DataSource`, the `executable` and `time` engines), `org.kde.ki18n`, `org.kde.plasma.core`
  (`Dialog`, `Types`) and `org.kde.plasma.private.mpris` — the same type names, the same
  properties, the same methods and the same enumeration values the shared files use, and
  nothing more.
- **The data come from one service**, `win/service/`, Python on `127.0.0.1:8788` —
  `spectrum/relay.py` grown up. It speaks ksystemstats' vocabulary (`/monitor` publishes
  `cpu/all/usage`, `memory/physical/used`, `gpu/gpu0/temperature`… with the same units) and
  the executable engine's protocol (`/exec` answers the command lines `MonitorData` builds
  — `df`, `lscpu`, `services.sh`, `health.sh` — from Windows sources in the same output
  format), serves the relay's `/bands` from a WASAPI loopback capture with the frame in
  cava's stereo order, the System Media Transport Controls as `/player`, `notes.py` as
  `/notes` in its own process, the `holidays` package as `/holidays`, zoneinfo as `/time`.
  The whole contract is `win/PROTOCOL.md`.
- **The service owns the settings and the processes.** The keys and the defaults are each
  widget's `main.xml`, read at start; the values live in `%APPDATA%\plaintop\<widget>.ini`,
  a host polls `/settings/<widget>` once a second and a settings window of our own
  (`win/host/settings.qml`, plain QtQuick.Controls) posts to it; the service starts and
  stops the hosts, the settings windows and the tray icon (`/ui`), hands each host the port
  and a write token on its command line, and — at the user's choice — parents a host's
  window under the wallpaper's `WorkerW`, where it sits behind the desktop icons.
- **The mouse, first stage:** the *Mouse* setting is whole-window — on, every click passes
  through, the active lines and the calendar's cells included, as the Plasma widgets were
  before decision 11; off, the widget takes the mouse, a left drag moves it, the right
  button opens its menu. The monitor's active lines ship off on Windows (their items are
  Linux commands).
- **Translations** are the same `po/` catalogs, converted with `lconvert -target-language`
  and loaded with `qml -translation`; the `i18n*` functions sit on each window's root and
  go to `qsTranslate("", text, context, n)`.

**Why shims and not a split of the data files.** `MonitorData.qml` is 1 600 lines of which
the subscriptions are a tenth and the line builders the rest, in one file; the task was
"the same lines, without the ksystemstats subscriptions". Four ways were weighed:

| Way | What it costs |
|---|---|
| A data file of the Windows host's own with the builders copied in | ~1 000 lines in two places, drifting apart with the first fix — the rule the project already lives by forbids it |
| Split `MonitorData.qml` into sources and builders, the Windows host supplying its own sources | A refactor of the Plasma widget that cannot be verified on the desktop from here; `tests/monitor.qml` needs Plasma to run; the same again for `PlayerView.qml`, which carries its MPRIS model inside |
| The service emits ready-made lines | The formatting and the plural forms rewritten in Python, a second copy of the catalogs' call sites |
| **Shims** | A dozen small QML files mimicking the surface the shared files use; the shared files byte-identical on both hosts; the Plasma side untouched |

The shims also give the Plasma stands a bare-Qt runner: `tests/monitor.qml` and the others
import the same module names, so they can run without the Arch container once pointed at
`win/host/imports` — not done yet.

**Why one service and not readings from QML.** QML in a bare host may read files and
`file://`, so the hosts could have read `/proc`'s Windows equivalents — there are none to
read: CPU, memory and the rest are Win32 calls, the sound is WASAPI, the player is WinRT.
Something had to run them, and the project already had the shape for it: a relay on a
local port, polled with `XMLHttpRequest`, measured on Plasma at thirty requests a second
(decision 4). With a service there anyway, it took the rest — the settings (one owner,
decision 5), the secrets (a note's account password travels in a POST body, never on a
command line, which is why Plasma needed `inbox.ini`), the processes.

**Why no C++.** A C++ host would need a compiler on the user's machine or a build on ours,
a CMake project and a plugin to maintain; `qml.exe` is in every Qt install, and Python with
PyInstaller is the whole service. The price is listed below; it has one item that may yet
reverse this.

**What we pay.**
- The shims mimic private KDE APIs. The surface is small and named in each file, but a
  change in how a shared file uses, say, `SensorDataModel` must be mirrored in the shim by
  hand — nothing fails to compile, the Windows host just goes quiet.
- `PlayerView.qml` calls the D-Bus-named methods `Previous()`, `PlayPause()`, `Next()`, and
  QML refuses to declare a method whose name begins with a capital letter. The mpris shim
  puts those three names on `Object.prototype`, forwarding to the lowercase methods of the
  QtObject they are called on — a QObject wrapper looks an unknown name up along the
  JavaScript prototype chain (verified; `GOTCHAS.md`). The two honest alternatives failed
  by measurement: a QML-created object's wrapper is not extensible, and a `ListModel` row
  object's extra JavaScript properties vanish with the next garbage collection.
- `/exec` recognises the monitor's Linux command lines by the script's base name and the
  first word and answers them from Windows sources. A new command in `MonitorData` is a
  new case in `exec_win.py`, or it falls through to `cmd.exe` and prints nothing.
- A local HTTP service that runs commands. It binds `127.0.0.1`, every write needs the
  token it hands its own hosts, and a request carrying a browser's `Origin` header is
  refused; the token file is the user's. That is the whole protection, and it is written
  down in `win/PROTOCOL.md`.
- No hit test under click-through: the monitor's active lines, the player's controls and
  the calendar's cells are dead while clicks pass through. A per-rectangle input region is
  `WM_NCHITTEST`, which a bare `qml.exe` cannot answer. The C++-free candidate for the
  second stage: the service reports the cursor (`GetCursorPos`) on request, the host polls
  it while passing clicks and drops `Qt.WindowTransparentForInput` while the cursor is over
  an active rectangle — the mask of decision 14, polled instead of asked. Not built, not
  measured.
- Qt 6.11 or newer: Qt 6.10's QML parser refuses `h.public` in `CalendarView.qml` and
  `Sticker.qml` (a reserved word after a dot), 6.11 takes it, as the desktop's 6.11.2 does.
- A Windows host of its own for the holidays (`win/host/calendar/Holidays.qml`): the
  plasmoid's file classifies a day off by its name against KHolidays' plans, and the
  `holidays` package names its days differently (21 of 29 names match for Russia, Germany
  and the United States) but says itself which is a day off — so the Windows file asks the
  service and repeats the eleven world days of the plasmoid's list, the one duplication in
  the port.
- Two edits to shared files: `MonitorData.qml` learns the `winget` label for the updates
  line (two `case`s, inert on Plasma), `notes.py` takes `%APPDATA%` and `%LOCALAPPDATA%`
  for its folders on Windows and opens the browser without `xdg-open` (the stand's 145
  checks pass as before).
- Two runtimes to ship: Qt's `qml.exe` with its modules (`windeployqt`), and Python with
  numpy, psutil, holidays, tzdata and the optional winsdk, soundcard, pycaw.

**Verified by running.** Written in a Linux container without Windows, so what was run is
Qt 6.11.3 offscreen against a stand-in service speaking the protocol, and the service's
Python stands: `tests/win_hosts.qml`, 9 of 9 — the monitor draws its 41 lines from
`/monitor` through the shims (the frame grabbed and compared with `docs/screenshot.png`),
the player's lines come from `/player` and a click on `>>` reaches the service through the
prototype trick, the weather fetches and shows its header, the visualizer sees `/bands`
and draws the ring, the calendar gets its document from `/notes` and opens the sticker —
a window of the `Dialog` shim — by a day's cell; `tests/win_media.py` 94 checks (the SMTC
mapping through a fake backend, `notes.py` in the service's process, the holidays of
Bavaria and Russia, the time zones); `tests/win_service.py` and `tests/win_bands.py` for
the monitor's sensors, the command emulation and the spectrum's analyzer on synthetic
signals; `tests/notes.py` 145 as before. The CI job on `windows-latest` runs the same stands
on Windows with the real service. **Not verified anywhere yet:** the WASAPI capture, the
WinRT media session, LibreHardwareMonitor's JSON on a live machine, the window flags on a
real desktop (transparency, keep-below, the input transparency toggled at run time), the
`WorkerW` parenting, the tray icon, the toast — the user's desktop is the first place these
run.

**Revisit if:** the second-stage hit test turns out to need more than the polled cursor —
then a small C++ host (one `QWindow` subclass answering `WM_NCHITTEST`) replaces
`qml.exe`, and nothing else changes; or Plasma's private modules change their surface
under the shared files faster than the shims can follow — then the split of the data files
(the second row of the table) is the next step, on both hosts at once.
