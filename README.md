# plaintop

English · [Русский](README.ru.md)

A text system monitor for the KDE Plasma desktop: monospaced text drawn straight onto the
wallpaper — load bars made of slashes, process tops, no frames, no rounded corners.

The look comes from the Rainmeter skin
[PlainExt](https://vsthemes.org/en/skins/rainmeter/41409-plainext.html); the name is
*plain* from there plus *top* from `htop`/`btop`.

![plaintop on the desktop](docs/screenshot.png)

## What it shows

Clock, date, distro and kernel, total CPU load and load per NUMA node, CPU model with
per-node temperatures and fan speeds, top processes by CPU and by memory, RAM, GPU with
VRAM, temperature and power draw, filesystems with NVMe temperature, uptime, network
throughput, the state of docker / ollama / pending updates, and a static hardware
passport.

Which of those appear, in what order, and with what parameters is **data, not code** —
see [Three layers](#three-layers) below.

## Status

Built and used on one machine: CachyOS, Plasma 6.7.5, KWin on Wayland. It should work on
any Plasma 6 desktop, but nothing else has been tested — reports welcome.

What is in the repository:

| Directory | What it is | State |
|---|---|---|
| **`monitor/`** | the text monitor: a plasmoid host, a click-through window host and the renderer they share | works |
| **`spectrum/`** | the audio visualizer: a widget plus a relay service that serves cava's bands | works |
| **`conky/`** | the first implementation on [conky](https://github.com/brndnmtthws/conky) | switched off, kept until the plasmoid fully replaces it |

⚠️ **About the mouse.** A plasmoid hands over the right button and never the left one —
four ways around it were tried and failed, see [docs/GOTCHAS.md](docs/GOTCHAS.md). So both
widgets also have a **window host**: a plain window with `Qt.WindowTransparentForInput`,
which every click passes through. That is what runs on the author's desktop now. It costs
the stock settings dialog and needs a KWin rule for its place, since under Wayland a window
cannot position itself.

Why the engine changed: [docs/DECISIONS.md](docs/DECISIONS.md).

## Install

```bash
git clone https://github.com/highscrren-dotcom/plaintop.git
cd plaintop
./install.sh --plasmoid          # the monitor as a plasmoid: generate, install, restart the shell
./install.sh --plaintop-window   # …or as a click-through window, with its own editor
./install.sh --spectrum          # the audio visualizer: plasmoid + relay service
./install.sh --spectrum-window   # …and its click-through window
./install.sh --status            # what is installed and what is running
```

One host per widget belongs on the desktop — they draw the same thing. The plasmoid lands
in `~/.local/share/plasma/plasmoids/org.s1dd1.plaintop/`; the installer places it on the
desktop unless that widget's window host is set up, and *Add Widgets* works as usual.
`./install.sh --pack` builds the same packages as `.plasmoid` files into `dist/`, for the
KDE Store or a release.

⚠️ `--plasmoid` restarts `plasmashell` on purpose: the shell caches a package's QML, and
without a restart your edit silently does not arrive. That and a dozen other traps are in
[docs/GOTCHAS.md](docs/GOTCHAS.md).

The conky implementation has its own switches: `./install.sh` deploys and starts it,
`--conky-files` deploys without starting (useful while it is switched off),
`--conky-off` and `--conky-on` turn it off and back on.

**Requirements:** Plasma 6 with `ksystemstats` (ships with Plasma) and KDE Frameworks
6.23 or newer (for `KI18nContext`, decision 7), `python3` for the generator, the setup
scripts and the relay, `msgfmt` from gettext for the translations, `qml6`
(qt6-declarative) for the window hosts, and a monospace font — `JetBrainsMono Nerd Font
Mono` by default. The visualizer additionally needs `cava`; the conky implementation needs
`conky`, `python-xlib` and `lm_sensors`.

## Adapting it to your hardware

Nothing about the author's machine is baked into the layout. Hardware-specific values are
found on the machine the widget runs on:

| What | How it is chosen | Change it in |
|---|---|---|
| Network interface | among the connected hardware interfaces: the one with a gateway, then the one that carried the most traffic | editor → *Blocks* → *Network*, a menu of the interfaces found |
| Fan and NVMe sensors | by pattern among the sensors this machine reports | editor → *Blocks* → *Processor* / *Disks*, a searchable list with live values |
| Mount points | `/` only — a mount point is a choice, not something to guess | editor → *Blocks* → *Disks*, a list of what is mounted now |
| Header text | yours to write; empty by default, so only the hostname shows | editor → *Blocks* → *Header* |

A value you pick is kept as a preference: while the machine still reports it, it wins; when
a reboot renames the chip or the interface, the widget falls back to discovery instead of
going quiet. Decision 6 in `docs/DECISIONS.md` explains why.

⚠️ If you ever write a sensor id by hand, address `lm_sensors` chips **by name**
(`nct6779-isa-0a20`), never by `hwmon` index — indexes move between reboots.

## The audio visualizer

`spectrum/` draws the spectrum of whatever is playing — a ring, an arc or a line of ticks,
in the same flat style. `cava` does the spectrum, a small systemd user service serves its
bands over local HTTP, and the widget moves ready-made rectangles: the GPU stays at about
half a percent because nothing is rasterized per frame.

It comes with **two hosts** for the same renderer. The plasmoid has Plasma's settings
dialog; the window host (`Qt.WindowTransparentForInput`) is the one you can click straight
through, and it brings its own editor with a live preview. Details, settings and the
measured cost: **[spectrum/README.md](spectrum/README.md)**.

## Three layers

```
schema/widget.json  ─┐                                    ┌─ settings dialog edits it
                     ├─ generator ─→ engine (QML)         │
schema/blocks.json  ─┘                                    └─ or edit the JSON directly
```

- **Description** — `schema/widget.json`: which blocks, in what order, with what
  parameters. Says *what* to show, not *how* to write it, so it does not depend on the
  engine.
- **Vocabulary** — `schema/blocks.json`: the block types and the parameters each accepts.
  The settings dialog is built from it, so a new block type needs no interface code.
- **Generator** — `monitor/generate.py`: validates the description and turns it into a JS
  module inside the package. A bad description stops the install instead of producing an
  empty widget.

Details: [schema/README.md](schema/README.md).

## Settings

Right-click the widget → *Configure plaintop…*. Two pages:

- *General* — font, size, edge padding, widget size, the four palette colours,
  the mouse, update interval, how often the process list is read.
- *Blocks* — enable, disable, reorder, edit parameters, add a block of any type
  from the vocabulary, remove one.

The window hosts have no Plasma dialog; each brings an editor with a live preview in the
real renderer — the menu entries "plaintop — monitor settings" and "plainspectrum —
settings", or `./install.sh --plaintop-settings` / `--spectrum-settings`.

**About the mouse.** The *Mouse* setting — and the
`./install.sh --clicks-on` / `--clicks-off` switches behind it — turns input off on the
widget's own representation. That is enough for the right button, which then reaches the
desktop through the widget, and never enough for the left one, which the applet container
keeps for itself. `docs/GOTCHAS.md` lists the four attempts and what each one did.

Two block types are deliberately open-ended:

- **`command`** — one line (or several) from the output of any command, with its own interval;
- **`sensor`** — any `ksystemstats` sensor by id, with or without a bar.

So a new reading usually means a new row in the description, not a patch to the code.

## Languages

Both widgets, their editors and their menu entries follow Plasma's language (System
Settings → Region & Language); dates and decimal separators follow its Formats. There are
ten: English, Russian, Ukrainian, German, French, Spanish, Brazilian Portuguese, Polish,
Simplified Chinese and Japanese. Everything but English and Russian is a machine
translation — corrections are welcome as pull requests, and a new language is one command:
see [CONTRIBUTING.md → Translations](CONTRIBUTING.md#translations).

## Fork it, bend it, send it back

This is a personal dashboard that turned out to be a reasonable starting point for anyone
who wants text on their Plasma desktop. **Fork it and make it yours** — the architecture
was chosen so that most changes are data:

- **Your own rows** — add a `command` or `sensor` block in the settings. No build step.
- **A new block type** — one entry in `schema/blocks.json` plus one `case` in
  `monitor/shared/MonitorData.qml`. Both settings pages pick it up on their own.
- **Another engine** — the description layer is engine-agnostic on purpose. Writing a
  generator for waybar, eww, AGS or back to conky does not touch the description.
- **Another machine** — different sensors, different distro, different everything: if the
  defaults fight you, that is a bug worth reporting.

Pull requests and issues are both welcome, and so is a fork that never comes back —
that is what the license is for. Read [CONTRIBUTING.md](CONTRIBUTING.md) first; it is
short and mostly about one rule: **claims about behaviour must be verified by running
them, not by reading the docs.**

## Why it is built this way

Under KDE on Wayland almost every obvious answer turns out to be wrong. The two documents
that make the rest of the code legible:

- **[docs/GOTCHAS.md](docs/GOTCHAS.md)** — traps that cost real time: window type and
  transparency for conky, click-through, the QML cache, applet size and placement, why
  `XMLHttpRequest` to `file://` is refused inside `plasmashell`. Every line was verified by
  running it.
- **[docs/DECISIONS.md](docs/DECISIONS.md)** — decisions with their reasoning, their price,
  and the condition that would reverse them.

## How the project is run

State travels between working sessions in two files: **[STATE.md](STATE.md)** — where the
project stands and what the next step is; **[docs/JOURNAL.md](docs/JOURNAL.md)** — how it
got here, one entry per session, failures included. The method itself is in
[docs/WORKFLOW.md](docs/WORKFLOW.md).

Those three are written in Russian: they are the working log, and translating a log is
busywork. Everything a contributor needs is in English.

## License

[GPL-2.0-or-later](LICENSE), matching the license declared in the plasmoid's
`metadata.json`.
