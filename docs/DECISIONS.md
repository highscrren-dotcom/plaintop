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

**What we pay.** One `Sensors.Sensor` object per non-uniform sensor instead of one shared
model — the model cannot be trusted with ids it may drop (see `GOTCHAS.md`) — and a poll of
the sensor tree that slows to once every 10 s once the list settles. Measured cost of the
monitor stayed where it was.

**Revisit if:** a machine shows up where the tree is large enough that enumerating it is
noticeable; then the registry caches to disk and refreshes on demand.
