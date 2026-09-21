# plaintop — the text monitor's shared parts and its click-through host

English · [Русский](README.ru.md)

The text monitor runs in two hosts. The renderer and the data side live here, so both draw
the same thing from the same code.

| Path | What it is |
|---|---|
| `shared/MonitorData.qml` | subscriptions, one-shot readings, the slow commands, and the lines built from the description |
| `shared/MonitorView.qml` | draws those lines; the palette lives here, and every part of a line carries a role rather than a colour |
| `window/window.qml` | the click-through host: a window with `Qt.WindowTransparentForInput` |
| `window/setup.py` | deploys it, writes the KWin rule and the autostart entry, and exports settings from the plasmoid |
| `../plasmoid/package/` | the plasmoid host, with Plasma's own settings dialog |

`install.sh` copies the two shared files into whichever host it is setting up. Two edited
copies of the same QML is how they drift apart.

## Why two hosts

A desktop plasmoid never hands over the left mouse button — four ways were tried, see
`../docs/GOTCHAS.md`. A plain window with `Qt.WindowTransparentForInput` does, so the
monitor can sit over the desktop without stealing clicks from the icons under it.

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

## Settings

`~/.config/plaintop/monitor.json` — appearance and the block description in one file:
font, size, padding, widget size, update interval, the four palette colours, and `blocks`.
The window re-reads it every two seconds, so an edit shows up without a restart.

**The editor is still the plasmoid's dialog.** `--plaintop-export` reads what that dialog
stored and writes it here, which keeps one editor for both hosts until the window host
gets one of its own — the visualizer already has that pattern in
`../spectrum/window/settings.qml`.

To move the monitor, edit the KWin rule (System Settings → Window Rules) or re-run
`--plaintop-window` with `PLAINTOP_X` / `PLAINTOP_Y` set. The gap from the screen edge is
drawn inside the widget instead (`padLeft`, `padTop`), which is why the rule pins the
window at `0,0`.

## What is still ahead

- **An editor for the window host**, like the visualizer's, so the plasmoid is not needed
  as a settings dialog.
- **One name for one widget.** The plasmoid host lives in `../plasmoid/` for historical
  reasons while its shared parts live here; `monitor/package`, `monitor/shared`,
  `monitor/window` would read better, and the rename is mechanical.
