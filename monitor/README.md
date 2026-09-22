# monitor — the text monitor

English · [Русский](README.ru.md)

A text system monitor for the Plasma 6 desktop, in QML. It runs in two hosts — a plasmoid
and a click-through window — and both draw the same thing from the same code. Why a
plasmoid at all — `../docs/DECISIONS.md`, decision 1; where the data comes from — decision 2.

| Path | What it is |
|---|---|
| `shared/MonitorData.qml` | subscriptions, one-shot readings, the slow commands, and the lines built from the description |
| `shared/MonitorView.qml` | draws those lines; the palette lives here, and every part of a line carries a role rather than a colour |
| `shared/SensorRegistry.qml` | what sensors this machine has; finds the machine-specific ids and ranks the network interfaces |
| `package/` | the plasmoid host, with Plasma's own settings dialog |
| `window/window.qml` | the click-through host: a window with `Qt.WindowTransparentForInput` |
| `window/settings.qml` | the window host's editor, with a live preview in the real renderer |
| `window/setup.py` | deploys the window, writes the KWin rule and the autostart entry, and exports settings from the plasmoid |
| `generate.py` | `../schema/*.json` → `package/contents/code/description.js`; validates before writing |

`install.sh` copies the shared files into whichever host it is setting up. Two edited
copies of the same QML is how they drift apart; `./install.sh --status` compares each host
with `shared/` itself.

## What it shows

A header with the hostname, clock, date, system, CPU load overall and per NUMA node, the
processor model with temperatures and fan speeds, top processes by CPU and by memory, RAM,
GPU with VRAM, disks with NVMe temperature, uptime, network, the state of
docker/ollama/updates and the hardware spec sheet — everything the conky implementation
showed.

**Which blocks and in what order comes from the description** (`../schema/widget.json`):
enable, disable, reorder, change parameters, add a block of your own — from an arbitrary
command or from any ksystemstats sensor. Both hosts edit it: the plasmoid on the "Блоки"
(Blocks) page of its dialog, the window in its editor.

## Why two hosts

A desktop plasmoid never hands over the left mouse button — four ways were tried, see
`../docs/GOTCHAS.md`; the *"Мышь"* (Mouse) setting only frees the right one. A plain window
with `Qt.WindowTransparentForInput` hands over both, so the monitor can sit over the
desktop without stealing clicks from the icons under it.

What the window host pays for that: no Plasma settings dialog, no session handling, and no
self-placement — under Wayland a window cannot position itself, so position, size,
keep-below and skip-taskbar come from a KWin rule matched on the window title.

## Install

```bash
./install.sh --plaintop-window     # deploy, write the KWin rule and autostart, start it
./install.sh --plaintop-export     # push the plasmoid's current settings into the window's config
./install.sh --plasmoid            # the plasmoid host (not placed on the desktop once the window exists)
./install.sh --status              # both hosts
```

Only one host belongs on the desktop: they draw the same monitor.

⚠️ `--plasmoid` restarts the shell, and not for looks: plasmashell keeps the package's QML
in a cache, and without the restart the widget stays on the old layout —
`../docs/GOTCHAS.md`. The plasmoid is added to the desktop like any other widget, or by
script:

```bash
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
  'desktops()[0].addWidget("org.s1dd1.plaintop", 60, 800, 420, 220)'
```

## Settings

**The plasmoid** keeps its settings in Plasma's store: `package/contents/config/main.xml`
is the schema, and the dialog has two pages — *"Общее"* (General: font, sizes, padding,
the four palette colours, mouse, intervals) and *"Блоки"* (Blocks), where the header
text lives too — empty by default, so a fresh install shows only the hostname.

**The window** reads `~/.config/plaintop/monitor.json` — appearance and the block
description in one file: font, size, padding, widget size, update interval, the four
palette colours, and `blocks`. It re-reads the file every two seconds, so an edit shows up
without a restart. `processInterval` is how often, in seconds, the process list behind the
top lists is read: it is the most expensive thing collected — about 3% of a core at the
default 2 s, about 1.3% at 10 s, measured with ~900 processes.

**The window's editor is `window/settings.qml`**, started from the menu entry
"plaintop — монитор" or with `./install.sh --plaintop-settings`. It shows the layout in the
**real renderer** side by side with the settings — the same `MonitorView` the desktop
draws, fed by a second `MonitorData`, so an edit is visible before it is saved. QML cannot
write files, so the editor reads `GET /config?widget=monitor` from the relay and posts
changes back; the relay stays the only writer. `--plaintop-export` still imports what the
plasmoid's dialog stored.

**Nothing has to be typed in by hand.** A parameter that holds a machine-specific id is
offered as a list of what this machine reports: sensors from the sensor tree with the
highlighted one's live value, network interfaces, mount points from `/proc/self/mounts`.
The editor learns which parameters those are from `pick` in the vocabulary, so a new block
type needs no editor change. An empty value means "find it yourself", and a stored one is
only a preference — see decision 6 in `../docs/DECISIONS.md`. Under the interface menu the
editor says which interface discovery landed on, and says so as well when the saved one is
no longer on the machine.

To move the window, edit the KWin rule (System Settings → Window Rules) or re-run
`--plaintop-window` with `PLAINTOP_X` / `PLAINTOP_Y` set. The gap from the screen edge is
drawn inside the widget instead (`padLeft`, `padTop`), which is why the rule pins the
window at `0,0`.

## Data sources

The data comes from **ksystemstats** via `org.kde.ksysguard.sensors` — hundreds of
ready-made sensors — and the process lists from `org.kde.ksysguard.process`. Commands fill
in only what the sensors lack: the NUMA layout, CPU model and board are read once at start
(`/sys`, `lscpu`), usage by mount point comes from `df` every 10 s, docker/ollama/pending
updates from `package/contents/code/services.sh`, plus whatever custom command blocks you
add. The rejected approaches and what each one costs — `../docs/DECISIONS.md`, decision 2.

## What is still ahead

- **Per-package CPU temperatures** — currently the maximum across a node's cores is taken;
  the sensors have no `coretemp-isa-000N`, so packages will have to be fetched from
  `sensors -u` by an occasional call.
- **Disk reads and writes** in the "/" line — conky had `R:` and `W:` there.
- **A generator for conky** — the description layer was meant to be shared by both
  engines; right now there is only one generator.
