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
| **A new block type** | one entry in `schema/blocks.json` + one `case` in `monitor/shared/MonitorData.qml`; the settings pages build themselves from the vocabulary |
| **A generator for another engine** | the description layer is engine-agnostic on purpose — waybar, eww, AGS, or back to conky |
| **Hardware and distro portability** | the defaults describe one machine; every hardcoded sensor id you replace with discovery is a win |
| **A trap you hit** | a PR to `docs/GOTCHAS.md` with a reproduction is worth as much as code |
| **Translation** | both widgets speak through gettext catalogs in `po/`: a new language is one command and a `.po` file — see [Translations](#translations) |

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
./install.sh --pack                                                 # .plasmoid files for a release → dist/
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
   Names and hints are English source strings: `python3 po/extract.py` puts them into the
   catalogs, and the editors translate them where they are shown.

2. **Default layout** — optionally add the block to `schema/widget.json`. Users can add it
   themselves from the settings page either way.

3. **Rendering** — one `case` in the lines builder in `monitor/shared/MonitorData.qml`,
   which both hosts share. Any word it shows goes through `tr.i18n()`:

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

## Translations

The widgets use KDE's own ki18n with gettext catalogs, one domain per widget —
`plasma_applet_org.s1dd1.plaintop` for the monitor, `plasma_applet_org.s1dd1.plainspectrum`
for the visualizer. The language is Plasma's
(System Settings → Region & Language); dates and decimal separators follow its Formats.
Why this design and what it costs — `docs/DECISIONS.md`, decision 7.

```bash
python3 po/extract.py            # refresh po/*.pot from the sources, merge into every language
python3 po/extract.py --init uk  # start a new language
lokalize po/uk/plasma_applet_org.s1dd1.plaintop.po   # or Poedit, or any .po editor
./install.sh --plasmoid          # builds the monitor's .mo files into its package
./install.sh --plaintop-window   # and into ~/.local/share/locale for its window host
./install.sh --spectrum          # the same for the visualizer, --spectrum-window for its window
```

Rules for the source strings:

- **They are English.** Russian is a translation like any other.
- **Placeholders are `%1`, `%2`**, never a string glued to a number: "shown %1 of %2",
  not `"shown " + a + " of " + b`. A translator needs the whole sentence.
- **Numbers with a noun use the plural call**, `i18np` / `i18ncp`: Russian, Ukrainian and
  Polish have three forms, and the catalog's own rules pick them.
- **Give context where a word is ambiguous**: `i18nc("palette: colour of", "Header:")`.
- **Files only the plasmoid loads call `i18n()`**; QML shared by both hosts and the window
  hosts' own files call `tr.i18n()` through a `KI18nContext`, since the bare `qml6`
  runner has no `i18n()` of its own.
- **Do not translate keys**: window titles the KWin rules match (`plaintop`), sensor ids,
  config keys, block ids.

`msgfmt --check` runs on every install, so a translation that drops a `%1` fails there
instead of on screen. To see the widget in another language without changing yours, run
the editor (`~/.local/share/plaintop/ui/settings.qml`) with `LANGUAGE=de` — and with an
empty `XDG_CONFIG_HOME` if its live preview should take that locale's dates and numbers
too, since KDE applies your own Formats over `LANG`. The editor reads its settings from
the relay, so an empty config directory costs it nothing.

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
- **Comments are English, and so are the source strings users see** — through the
  catalogs, see [Translations](#translations). The output of `install.sh` and the setup
  scripts in the terminal is still Russian.

## Commits and pull requests

- One commit per idea, with a body that says **why** and **what was verified by running it**.
  Look at `git log` for the shape.
- English is preferred for new commit messages; the existing history is Russian.
- Issues do not need a template. "This is what I ran, this is what happened, this is what I
  expected" is enough.

## License

By contributing you agree that your work is distributed under
[GPL-2.0-or-later](LICENSE), the license of the project.
