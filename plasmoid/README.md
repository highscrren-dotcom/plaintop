# plasmoid — the target implementation

English · [Русский](README.ru.md)

A plasmoid of our own for Plasma 6, written in QML. Why this one — `../docs/DECISIONS.md`, decision 1.
Where the data comes from — same file, decision 2.

## What is already there

A minimal working package: it installs, shows up on the desktop, displays live data, and
settings from the stock dialog do reach the QML.

```
package/
  metadata.json                the org.s1dd1.plaintop identifier
  contents/
    ui/main.qml                the widget itself: builds the lines from the description, sensor subscriptions
    ui/configGeneral.qml       the "Общее" (General) page: font, type size, size, padding, interval
    ui/configBlocks.qml        the "Блоки" (Blocks) page: which blocks, their order and their parameters
    config/main.xml            the value schema — Plasma builds the dialog and the store from it
    config/config.qml          the list of settings pages
    code/description.js        layout and dictionary generated from schema/ (not in git)
    code/services.sh           docker / ollama / updates in one batch
```

Shows the same things as the conky implementation: a header with the hostname, clock, date,
system, CPU load overall and per NUMA node, the processor model with temperatures and fan
speeds, top processes by CPU and by memory, RAM, GPU with VRAM, disks with NVMe temperature,
uptime, network, the state of docker/ollama/updates and the hardware spec sheet.

**Which blocks and in what order comes from the description** (`../schema/widget.json`), edited
on the "Блоки" (Blocks) page in the settings: enable, disable, reorder, change parameters, add a
block of your own — from an arbitrary command or from any ksystemstats sensor.

## Installation

```bash
./install.sh --plasmoid   # install/update the package and restart the shell
./install.sh --status     # the "Плазмоид" (Plasmoid) section at the end
```

⚠️ The shell restart in that command is not there for looks: plasmashell keeps the package's QML
in a cache, and without it the widget stays on the old layout. Verified — `../docs/GOTCHAS.md`.

Adding it to the desktop works like any other widget, or by script:

```bash
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
  'desktops()[0].addWidget("org.s1dd1.plaintop", 60, 800, 420, 220)'
```

## Data sources

The data comes from **ksystemstats** via `org.kde.ksysguard.sensors` — 620 ready-made sensors on
this machine, without a single external command being launched. The rejected approaches and what
each one costs — `../docs/DECISIONS.md`, decision 2.

Subscribed to so far: `cpu/all/usage`, `cpu/all/averageTemperature`,
`memory/physical/usedPercent`, `os/system/uptime`, `os/system/hostname`.

## What is still ahead

- **Colors into the settings** — for now the palette is hardcoded in `main.qml` as constants from PlainExt.
- **Per-package CPU temperatures** — currently the maximum across a node's cores is taken; the
  sensors have no `coretemp-isa-000N`, so packages will have to be fetched from `sensors -u` by an
  occasional call.
- **Disk reads and writes** in the "/" line — conky had `R:` and `W:` there.
- **A generator for conky** — the description layer was meant to be shared by both engines;
  right now there is only one generator.
