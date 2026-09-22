# monitor — the text monitor

English · [Русский](README.ru.md)

A text system monitor for the Plasma 6 desktop, in QML. It runs as a plasmoid; the
click-through window host it had for a while is retired (decision 9) and stays in
`window/` for reference. Why a plasmoid at all — `../docs/DECISIONS.md`, decision 1;
where the data comes from — decision 2.

| Path | What it is |
|---|---|
| `shared/MonitorData.qml` | subscriptions, one-shot readings, the slow commands, and the lines built from the description |
| `shared/MonitorView.qml` | draws those lines; the palette lives here, and every part of a line carries a role rather than a colour |
| `shared/SensorRegistry.qml` | what sensors this machine has; finds the machine-specific ids and ranks the network interfaces |
| `package/` | the plasmoid host, with Plasma's own settings dialog |
| `window/window.qml` | the retired window host: a window with `Qt.WindowTransparentForInput` (decision 9) |
| `window/settings.qml` | that host's editor, with a live preview in the real renderer — retired with it |
| `window/setup.py` | deployed the window, its KWin rule and autostart; what matters now is `retire`, behind `./install.sh --windows-off` |
| `generate.py` | `../schema/*.json` → `package/contents/code/description.js`; validates before writing |

`install.sh` copies the shared files into the plasmoid package. An edited copy is how it
drifts from `shared/`; `./install.sh --status` compares the installed files with `shared/`
itself.

## What it shows

A header with the hostname, clock, date, system, CPU load overall and per NUMA node, the
processor model with temperatures and fan speeds, top processes by CPU and by memory, RAM,
GPU with VRAM, disks with NVMe temperature, uptime, network, the state of
docker/ollama/updates and the hardware spec sheet — everything the conky implementation
showed.

**Which blocks and in what order comes from the description** (`../schema/widget.json`):
enable, disable, reorder, change parameters, add a block of your own — from an arbitrary
command or from any ksystemstats sensor. It is edited on the *Blocks* page of the
plasmoid's dialog.

## Why there was a second host, and why it is retired

The window host was born of the mouse: a desktop plasmoid would not hand over the left
button, four ways were tried (`../docs/GOTCHAS.md`), and a plain window with
`Qt.WindowTransparentForInput` hands over both, so the monitor could sit over the desktop
without stealing clicks from the icons under it. Since then the plasmoid has learned it
too: the *Mouse* setting disables the applet container the shell wraps it in and masks the
widget out of the desktop's context-menu lookup, both buttons reach the desktop, and the
widget takes the mouse only in the desktop's edit mode — which is also where its settings
are. That left the window host with nothing to add and its price still to pay: no Plasma
settings dialog, no session handling, and no self-placement (under Wayland a window cannot
position itself, so position, size, keep-below and skip-taskbar came from a KWin rule
matched on the window title). So it is retired (decision 9): one host, the plasmoid. The
code stays in `window/` but is not installed; `./install.sh --windows-off` retires an
existing setup.

## Install

```bash
./install.sh --plasmoid            # generate, install, restart the shell, place it on the desktop
./install.sh --windows-off         # retire the window host of an earlier setup (decision 9)
./install.sh --status              # what is installed and running
```

`--plaintop-window`, `--plaintop-export` and `--plaintop-settings` still exist but belong to
the retired host and are not to be used.

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
is the schema, and the dialog has two pages — *General* (font, sizes, padding, the four
palette colours, mouse, intervals) and *Blocks*, where the header
text lives too — empty by default, so a fresh install shows only the hostname.

The process-list interval is the setting worth knowing about: the process list behind the
top lists is the most expensive thing collected — about 3% of a core at the default 2 s,
about 1.3% at 10 s, measured with ~900 processes.

**Machine-specific ids need not be typed in.** A parameter that holds one — a fan or NVMe
sensor, the network interface — may be left empty: it then means "find it yourself", and a
stored value is only a preference that discovery replaces when the machine no longer
reports it — see decision 6 in `../docs/DECISIONS.md`. The vocabulary marks such
parameters with `pick`; the retired window editor turned that into searchable lists with
live values, interfaces and mount points, while the plasmoid's dialog offers a plain
field. The gap from the screen edge is drawn inside the widget (`padLeft`, `padTop`).

**The retired window host** read `~/.config/plaintop/monitor.json` — appearance and the
block description in one file, re-read every two seconds — and had an editor of its own,
`window/settings.qml`: the layout in the **real renderer** side by side with the settings,
writing through the relay (`GET`/`POST /config`) because QML cannot write files. Both stay
in the tree for reference (decision 9); the settings file is left where it is.

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
