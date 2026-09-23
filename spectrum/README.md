# spectrum — audio visualizer

English · [Русский](README.ru.md)

Draws the spectrum of whatever is playing, in the same plain style as the text monitor:
one colour, square ends, no gradients, no glow. Ring, arc or line — and, since 0.3, the
player widget's "now playing" lines in the centre of the ring, as an option (decision 12).

Why it is ours rather than an existing widget: `../docs/DECISIONS.md`, decisions 3 and 4.
For a while it had a second host, a click-through window, born of the left button
(decision 5 — a desktop plasmoid would not hand it over, a plain window does). Since the
plasmoid lets both buttons through by itself (decision 8, `../docs/GOTCHAS.md`) that host
is retired (decision 9): one host, the plasmoid; the code stays in `window/` but is not
installed.

## How it is put together

```
cava ──► relay.py ──► plasmoid ──► Ring.qml
 FFT    local HTTP
```

| Piece | What it does |
|---|---|
| `shared/Spectrum.qml` | polls the relay, decides whether anything is playing, hands the bands over by signal |
| `shared/Ring.qml` | draws them: a tick is a rectangle inside a zero-sized pivot, so ring, arc and line differ only in where the pivot stands |
| `../player/shared/PlayerView.qml` | the player widget's view, copied in as well: drawn in the centre of the ring when the *Player* page says so |
| `relay.py` | runs `cava`, serves its bands over `http://127.0.0.1:8788`, and **owns the settings file** |
| `window/window.qml` | the retired window host: a window with `Qt.WindowTransparentForInput` (decision 9) |
| `window/settings.qml` | that host's editor, with a live preview — retired with it |
| `package/` | the plasmoid host, with Plasma's own settings dialog |

The plasmoid loads the three shared files — `install.sh` copies them into the package,
and `./install.sh --status` compares the copies with the sources. An edited copy is how it
drifts.

⚠️ QML cannot write files, so the retired host's editor never touched `ring.json`: it read
`GET /config` and posted changes to `POST /config`, and the relay wrote the file. One
owner beats two writers — the same rule this project already learned about `~/.config/conky`.
The plasmoid keeps its settings in Plasma's own store instead.

## Install

```bash
./install.sh --spectrum            # the plasmoid + the relay service
./install.sh --windows-off         # retire the window host of an earlier setup (decision 9)
./install.sh --status              # the plasmoid, the relay port, the retired window
```

`--spectrum-window` and `--spectrum-settings` still exist but belong to the retired host and
are not to be used.

Needs `cava` and `msgfmt` (gettext, for the translations).
The relay's own knobs — device, band count, frame rate, noise reduction, frequency range,
how soon cava sleeps in silence — are environment in the service unit; override them in
`~/.config/plainspectrum/relay.env`.
After three seconds of silence cava stops computing and looks at the input once a second
(`PLAINSPECTRUM_SLEEP`, `0` turns it off): 3.9% of a core in silence becomes 0.35%, and
the ring appears up to a second later when the sound returns.

`--spectrum` places the plasmoid on the desktop; it holds off only while a not-yet-retired
window host is still set up — run `--windows-off` first. The ring is moved like any widget,
in the desktop's edit mode.

## Settings

Right-click → *Configure*. Two pages: *Ring* — shape, appearance, behaviour, silence — and
*Player*.

| Setting | What it does |
|---|---|
| Layout | ring or line; a ring with a span below 360° is an arc |
| Bars, thickness, spacing | density and weight of the ticks |
| Radius, span, start angle | the ring's geometry |
| Length at silence / at maximum | how far a tick reaches |
| Growth | from the baseline: outward, inward or both ways on a ring; up, down or both ways on a line |
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

### The player in the ring

The *Player* page has one switch — *In the ring: show the player in the centre of the
ring* (`playerShow`, off by default) — and under it the player widget's own settings with
the same defaults: font, size, width in characters (22 at least), the three colours, the
player filter, the album line, the controls row. What is drawn is the player widget's
view itself, `../player/shared/PlayerView.qml`, loaded only while the switch is on: a
board `columns` characters wide and five lines tall, centred on the ring's centre; on a
line it goes along the edge the bars reach last — above bars that grow up, below bars
that hang down. The ring keeps its size whatever the board's; with no player on the bus
the centre stays empty, and the "no relay" notice steps aside from the board.

With *Mouse* on, the player's controls row `<<  >  >>` is the one place the widget takes
the mouse: a click there reaches the button, anywhere else it goes through to the desktop,
and so does the hover (decision 11; the mechanism and the stand — `../docs/GOTCHAS.md`).
The standalone player widget stays its own product; this is the same view in a second
host, and its strings sit in this widget's catalog too.

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
