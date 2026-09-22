# Contributing to plaintop

English · [Русский](CONTRIBUTING.ru.md)

Forks are the point. This started as one person's desktop dashboard, and the parts that
turned out to be generally useful — the block description layer, the list of KDE/Wayland
traps — are worth more in other people's hands than in a private repo. Take it, bend it,
and send back whatever you think others should get.

## The one rule: verify by running

**A claim about behaviour is a hypothesis until it has been executed.** Not "the docs say",
not "it should", not "last time it did". Run it, read the whole output, then write it down.

This rule is not decoration. The project's own journal records three consecutive occasions
where "it does not work under KWin" was written about things that worked perfectly — they
had simply never been tried. Every line in [docs/GOTCHAS.md](docs/GOTCHAS.md) was executed
on a live system before it was written.

So: a pull request that changes behaviour says **what was run and what came out**. A one-line
reproduction beats a paragraph of reasoning.

## What fits especially well

| Contribution | Why it is easy here |
|---|---|
| **A new block type** | one entry in `schema/blocks.json` + one `case` in `main.qml`; the settings page builds itself from the vocabulary |
| **A generator for another engine** | the description layer is engine-agnostic on purpose — waybar, eww, AGS, or back to conky |
| **Hardware and distro portability** | the defaults describe one machine; every hardcoded sensor id you replace with discovery is a win |
| **A trap you hit** | a PR to `docs/GOTCHAS.md` with a reproduction is worth as much as code |
| **Translation** | docs are English + Russian mirrors (`FILE.md` / `FILE.ru.md`); the strings the user sees are still Russian |

Before adding a block type, check whether the open-ended ones already cover you: `command`
runs any shell command on its own interval, `sensor` shows any `ksystemstats` sensor by id.
Neither needs a code change — just a row in the description.

## Repository layout

| Path | What lives there |
|---|---|
| `monitor/package/` | the text monitor as a Plasma 6 widget: QML, config schema, settings pages, the services script |
| `monitor/shared/` | the monitor's data side and renderer, copied into both hosts on install |
| `monitor/window/` | the monitor's click-through window host and its editor |
| `monitor/generate.py` | description → JS module inside the package; validates before writing |
| `schema/widget.json` | the default layout: which blocks, in what order, with what parameters |
| `schema/blocks.json` | the vocabulary of block types and their parameters |
| `spectrum/package/` | the audio visualizer widget: one renderer for ring, arc and line |
| `spectrum/relay.py` | cava's bands over local HTTP, run as a systemd user service |
| `conky/` | the first implementation; frozen and switched off, kept until the plasmoid replaces it |
| `install.sh` | install, status, conky and clicks on/off — all operations idempotent |
| `docs/` | traps, decisions, the working method, the session journal |

`monitor/package/contents/code/description.js` is generated and not in git — edit
`schema/*.json` instead.

## The development cycle

```bash
qmllint -I /usr/lib/qt6/qml monitor/package/contents/ui/main.qml    # before installing
./install.sh --plasmoid                                             # generate + install + restart the shell
./install.sh --spectrum                                             # the visualizer: widget + relay service
journalctl --user -b --since "-1min" | grep -i plaintop             # QML errors land here
./install.sh --status                                               # what is installed and running
```

Three things that will otherwise waste your afternoon — all three are in
[docs/GOTCHAS.md](docs/GOTCHAS.md) with the evidence:

- **`plasmashell` caches a package's QML.** Reinstalling is not enough, and neither is
  removing and re-adding the widget. `--plasmoid` restarts the shell for you.
- **Qt sends QML logging to journald, not to stderr.** For standalone `qml6` probes use
  `QT_FORCE_STDERR_LOGGING=1`, or it looks like your code never ran.
- **systemd rate-limits restarts.** After several in a row you get "start request repeated
  too quickly" and a desktop without a panel. Recover with
  `systemctl --user reset-failed plasma-plasmashell.service`, then `start`.

## Adding a block type, start to finish

1. **Vocabulary** — add an entry to `schema/blocks.json`:

   ```json
   "fan": {
     "name": "Fan",
     "hint": "One fan by sensor id",
     "params": {
       "label": { "type": "string", "name": "Label", "default": "FAN" },
       "id":    { "type": "string", "name": "Sensor id", "default": "lmsensors/nct6779-isa-0a20/fan1" }
     }
   }
   ```

   Parameter types are `bool`, `int` (optionally `min`/`max`), `string`, `stringlist`.
   The generator rejects anything else, and the settings page renders an editor per type.

2. **Default layout** — optionally add the block to `schema/widget.json`. Users can add it
   themselves from the settings page either way.

3. **Rendering** — one `case` in the lines builder in `main.qml`:

   ```js
   case "fan": {
       const rpm = num(p.id, 0)
       out.push(kvLine(p.label || "FAN", Math.round(rpm) + " rpm"))
       break
   }
   ```

   If the block reads a sensor, its id also has to reach the subscription — see how
   `customSensorIds` collects ids from the description.

4. **Run it.** `./install.sh --plasmoid`, look at the widget, check the journal. Then say
   in the PR what you saw.

The generator needs no changes: validation is driven by the vocabulary.

## Style

- **Comments say why, not what.** The code is readable; the reason it is shaped that way
  usually is not.
- **No unverified statements in documentation.** If it can be executed, execute it.
- **Format numbers yourself.** `formattedValue` and `Formatter` insert U+200B before `%`
  and U+2009 before `°C`; in monospaced columns that shows up immediately.
- **Address `lm_sensors` chips by name**, never by `hwmon` index — indexes move between
  reboots.
- **New rules become checks first.** If a rule can live in `install.sh` as a check, put it
  there rather than in a document.
- **Comments are English. User-visible strings are not, yet.** The widget's settings
  labels, the rows it draws (`ОЗУ`, `аптайм`, `не смонтирован`) and `install.sh` output
  are still Russian. Doing that properly means real i18n — `i18n()` calls with
  translation catalogs — which is an open invitation, not a decided design.

## Commits and pull requests

- One commit per idea, with a body that says **why** and **what was verified by running it**.
  Look at `git log` for the shape.
- English is preferred for new commit messages; the existing history is Russian.
- Issues do not need a template. "This is what I ran, this is what happened, this is what I
  expected" is enough.

## License

By contributing you agree that your work is distributed under
[GPL-2.0-or-later](LICENSE), the license of the project.
