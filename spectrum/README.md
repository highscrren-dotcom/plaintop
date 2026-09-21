# spectrum — audio visualizer

English · [Русский](README.ru.md)

Draws the spectrum of whatever is playing, in the same plain style as the text monitor:
one colour, square ends, no gradients, no glow. Ring, arc or line.

Why it is ours rather than an existing widget: `../docs/DECISIONS.md`, decisions 3 and 4.
Why there are two hosts for it: decision 5 — a desktop plasmoid never hands over the left
mouse button, and a plain window does.

## How it is put together

```
cava ──► relay.py ──► host ──► Ring.qml
 FFT    local HTTP     plasmoid or window
                 ▲
                 └── settings.qml (the editor) writes settings through the same relay
```

| Piece | What it does |
|---|---|
| `shared/Spectrum.qml` | polls the relay, decides whether anything is playing, hands the bands over by signal |
| `shared/Ring.qml` | draws them: a tick is a rectangle inside a zero-sized pivot, so ring, arc and line differ only in where the pivot stands |
| `relay.py` | runs `cava`, serves its bands over `http://127.0.0.1:8788`, and **owns the settings file** |
| `window/window.qml` | the click-through host: a window with `Qt.WindowTransparentForInput` |
| `window/settings.qml` | the editor for that host, with a live preview |
| `package/` | the plasmoid host, with Plasma's own settings dialog |

Both hosts load the same two shared files — `install.sh` copies them in. Two edited copies
of the same QML is how they drift apart.

⚠️ QML cannot write files, so the editor never touches `ring.json`: it reads
`GET /config` and posts changes to `POST /config`, and the relay writes the file. One
owner beats two writers — the same rule this project already learned about `~/.config/conky`.

## Install

```bash
./install.sh --spectrum            # the plasmoid host + the relay service
./install.sh --spectrum-window     # the click-through window + its KWin rule + autostart
./install.sh --spectrum-settings    # open the editor
./install.sh --status              # both hosts, the relay port, the KWin rule, the window
```

Needs `cava` and `qml6` (`qt6-declarative`). The relay's own knobs — device, band count,
frame rate, noise reduction, frequency range — are environment in the service unit;
override them in `~/.config/plainspectrum/relay.env`.

⚠️ Only one host belongs on the desktop: they draw the same ring. `--spectrum` installs
the plasmoid but does not place it once the window host is set up.

**Under Wayland a window cannot place itself**, so position, size, keep-below and
skip-taskbar come from a KWin rule matched on the window title, written by
`window/setup.py`. To move the ring, edit that rule (System Settings → Window Rules) or
re-run `--spectrum-window` with `PLAINSPECTRUM_X` / `PLAINSPECTRUM_Y` set.

## Settings

The editor groups them as the widget does: shape, appearance, behaviour.

| Setting | What it does |
|---|---|
| Layout | ring or line; a ring with a span below 360° is an arc |
| Bars, thickness, spacing | density and weight of the ticks |
| Radius, span, start angle | the ring's geometry |
| Length at silence / at maximum | how far a tick reaches |
| Growth | outward, inward, or both ways from the baseline |
| Mirror, reverse | fold the spectrum back on itself, or flip its direction |
| Element | a solid bar or a ladder of blocks |
| Block size and gap | the ladder's step; the number of blocks follows from the reach |
| Colour, second colour, opacity | flat colour, or a drift toward the second one across the spectrum |
| Guide circle | a thin static ring under the ticks |
| Data frames per second | how often the host polls the relay |
| Smoothing, ms | the Qt animation that fills the gaps between data frames |
| Fade on silence | the ring dissolves when nothing plays and grows back out of the invisible ring |
| Silence threshold, delay, fade, idle polls | when silence counts, how long to wait, how slow the fade is, how rarely to poll while hidden |

⚠️ **Blocks** draw bars × blocks items, so the cost scales with both. **Smoothing** is
deliberately a Qt animation and not a JavaScript loop: the same interpolation in JS
measured three times more expensive.

## Debugging

```bash
curl -s http://127.0.0.1:8788/state    # frames, cava restarts, source, age of the last frame
curl -s "http://127.0.0.1:8788/bands?bars=16"
journalctl --user -u plainspectrum-relay -f
```

⚠️ `/state` exists because of a real failure: cava exits when the audio device changes,
and the first version of the relay let its reading thread end and went on serving zeros.
The widget then looked merely silent. The relay now supervises cava and restarts it, and
`/state` makes "all zeros" readable instead of a guess.

## What is still ahead

- **Peak hold** — a dot that keeps the maximum and sinks slowly.
- **Source selection in the editor** — the device is still set in `relay.env`.
- **Pause under a fullscreen window** — silence already hides the ring, but a game with
  its own sound keeps it awake.
- **Frequency range in the editor** — it reaches cava, so the relay has to restart.
