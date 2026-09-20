# spectrum — audio visualizer

English · [Русский](README.ru.md)

A Plasma 6 widget that draws the spectrum of whatever is playing, in the same plain style
as the text monitor: single colour, square ends, no gradients, no glow.

Why it is ours rather than an existing widget: `../docs/DECISIONS.md`, decisions 3 and 4 —
the short version is that the established widget rasterizes on the CPU through a QML
`Canvas`, which costs about 31 points of GPU and half a core at the size wanted here.

## How it is put together

```
cava  ──►  relay.py  ──►  widget
 FFT       local HTTP      scene items
```

- **`cava`** does the spectrum. It is packaged, tuned and cheap: 2–3% of one core.
- **`relay.py`** serves cava's bands over `http://127.0.0.1:8788` as a comma-separated
  line. A relay is needed because cava streams and never exits, while Plasma's
  `executable` data engine only reports a command's output once it finishes, and QML may
  not read a local file. Local HTTP is allowed — see `../docs/GOTCHAS.md`.
  It runs as a systemd **user service**, so it survives a shell restart and dies with the
  session instead of lingering as an orphan.
- **The widget** asks for the number of bars it draws (`?bars=N`, the relay downsamples)
  and moves ready-made rectangles. Nothing is rasterized per frame, so the GPU stays at
  about half a percent.

## Install

```bash
./install.sh --spectrum    # widget + relay service + place it on the desktop
./install.sh --status      # the "Спектр" (Spectrum) section reads the port, not just systemd
```

Needs `cava` (`sudo pacman -S cava`). The relay's own settings — device, band count,
frame rate, noise reduction, frequency range — live in the service environment;
override them in `~/.config/plainspectrum/relay.env`.

## Shape and appearance

One renderer covers several shapes because a tick is a rectangle in a zero-sized pivot:
only where the pivot stands and how far it is turned changes.

| Setting | What it does |
|---|---|
| Layout | ring or line; a ring with a span below 360° is an arc |
| Bars, thickness, spacing | density and weight of the ticks |
| Radius, span, start angle | the ring's geometry |
| Length at silence / at maximum | how far a tick reaches |
| Growth | outward, inward, or both ways from the baseline |
| Mirror, reverse | fold the spectrum back on itself, or flip its direction |
| Element | a solid bar or a stack of blocks |
| Colour, second colour, opacity | flat colour, or a drift toward the second one across the spectrum |
| Guide circle | a thin static ring under the ticks |
| Data frames per second | how often the widget polls the relay |
| Smoothing, ms | the Qt animation that fills the gaps between data frames |
| Mouse | clicks pass through to the desktop; `install.sh --clicks-off` is the way back |

⚠️ Two settings are worth understanding before turning them up. **Blocks** draw
bars × blocks items, so the cost scales with both. **Smoothing** is deliberately a Qt
animation and not a JavaScript loop: the same interpolation in JS measured three times
more expensive.

## What is still ahead

- **Peak hold** — a dot that keeps the maximum and sinks slowly.
- **Source selection in the dialog** — right now the device is set in `relay.env`.
- **Pause under a fullscreen window**, and a quiet mode that hides the widget.
- **Frequency range in the dialog** — it reaches cava, so it needs the relay restarted.
- **A shader renderer** — cheaper still, but it moves the work to the GPU, which was
  explicitly not wanted here.
