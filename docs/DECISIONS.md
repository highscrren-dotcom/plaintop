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
mouse. Then use that and drop the binding.

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
