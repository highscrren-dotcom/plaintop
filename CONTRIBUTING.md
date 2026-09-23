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
| **Translation** | all four widgets speak through gettext catalogs in `po/`: a new language is one command and a `.po` file — see [Translations](#translations) |

Before adding a block type, check whether the open-ended ones already cover you: `command`
runs any shell command on its own interval, `sensor` shows any `ksystemstats` sensor by id.
Neither needs a code change — just a row in the description.

## Repository layout

| Path | What lives there |
|---|---|
| `monitor/package/` | the text monitor as a Plasma 6 widget: QML, config schema, settings pages, the services script |
| `monitor/shared/` | the monitor's data side and renderer, copied into the package on install |
| `monitor/window/` | the monitor's former window host and its editor — retired (decision 9), kept for reference |
| `monitor/generate.py` | description → JS module inside the package; validates before writing |
| `schema/widget.json` | the default layout: which blocks, in what order, with what parameters |
| `schema/blocks.json` | the vocabulary of block types and their parameters |
| `spectrum/package/` | the audio visualizer as a Plasma 6 widget, with its settings page |
| `spectrum/shared/` | the visualizer's renderer — one for ring, arc and line — copied into the package |
| `spectrum/window/` | the visualizer's former window host and its editor — retired (decision 9), kept for reference |
| `spectrum/relay.py` | cava's bands over local HTTP, run as a systemd user service; the visualizer reads it |
| `player/package/` | the "now playing" widget as a Plasma 6 widget: host, settings pages, catalogs — no service |
| `player/shared/` | the player's view — the MPRIS model, the lines, the controls — copied into `player/package/` and into `spectrum/package/` on install: the visualizer draws it in the centre of its ring |
| `weather/package/` | the weather widget: a Plasma 6 widget that asks one of four sources itself over https — the sources are objects in `contents/ui/Sources.js` — no shared files, no service |
| `po/` | translation catalogs, one domain per widget, four in all; `extract.py` refreshes them and starts a missing one, `build.py` compiles |
| `conky/` | the first implementation; frozen and switched off, kept until the plasmoid replaces it |
| `install.sh` | install, status, `.plasmoid` builds, conky and clicks on/off — all operations idempotent |
| `docs/` | traps, decisions, the working method, the session journal, the KDE Store texts |

Generated and not in git: `monitor/package/contents/code/description.js` (edit
`schema/*.json` instead), the packages' `contents/locale/` (edit `po/`), the packages'
copies of the shared QML (edit `monitor/shared/`, `spectrum/shared/`, `player/shared/`;
`--status` says when a copy differs), `dist/`.

## The development cycle

```bash
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml monitor/package/contents/ui/main.qml   # before installing — the Qt 6 one
./install.sh --plasmoid                                             # generate + install + restart the shell
./install.sh --spectrum                                             # the visualizer: widget + relay service
./install.sh --player                                               # the player
./install.sh --weather                                              # the weather
journalctl --user -b --since "-1min" | grep -i plaintop             # QML errors land here
./install.sh --status                                               # what is installed and running
./install.sh --pack                                                 # .plasmoid files for a release → dist/
./install.sh --check-passthrough                                    # the click-through stand: 17 tests against the shell's compiled applet wrapper
```

Four things that will otherwise waste your afternoon — all four are in
[docs/GOTCHAS.md](docs/GOTCHAS.md) with the evidence:

- **`plasmashell` caches a package's QML.** Reinstalling is not enough, and neither is
  removing and re-adding the widget. `--plasmoid` restarts the shell for you.
- **Qt sends QML logging to journald, not to stderr.** For standalone `qml6` probes use
  `QT_FORCE_STDERR_LOGGING=1`, or it looks like your code never ran.
- **systemd rate-limits restarts.** After several in a row you get "start request repeated
  too quickly" and a desktop without a panel. Recover with
  `systemctl --user reset-failed plasma-plasmashell.service`, then `start`.
- **`/usr/bin/qmllint` is the Qt 5 one** — as are `/usr/bin/qml` and `qmltestrunner`. On
  Qt 6 syntax it prints nothing and exits 255, so a check that ignores the exit code
  passes. The Qt 6 tools are in `/usr/lib/qt6/bin/`.

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

## Adding a widget

The player and the weather were added this way; copy whichever is closer to yours.

1. **Package** — `<name>/package/`: `metadata.json` (id `org.s1dd1.plain<name>`, category,
   version), `contents/config/main.xml` and `config.qml` (the settings schema and its
   pages), `contents/ui/main.qml` — the host: the size from `Layout.*` on the root, constant
   for the given settings, and the two click-through `Binding`s copied as they are —
   the wrapper disabled (decision 8), or, when a part of the widget must stay clickable,
   a `containmentMask` over that part, as the player does (decision 11) — and the view
   next to it, with the lines and the drawing. A view that another widget draws too goes
   to `<name>/shared/` instead, as the player's does. Strings go through `i18n()`.
2. **`install.sh`** — the `<NAME>_ID` / `_SRC` / `_DEST` variables, `<name>_prepare` (the
   catalogs, and the copy of any shared QML into the package — `player_prepare` copies
   `player/shared/PlayerView.qml` into the player's package, `spectrum_prepare` the same
   file into the visualizer's; the copies are gitignored and `<name>_status` compares them
   with the source), `<name>_install` and `<name>_status`, the source in the list in
   `pack()`, the call in `status`, the `--<name>` key in the `case` and in the usage line.
3. **`po/extract.py`** — an entry in `DOMAINS`; a shared directory drawn by two widgets is
   listed under both their domains, as `player/shared` is. `python3 po/extract.py` then
   writes the template and a catalog for every language the project has.
4. **README** — a row in the directory table, an install line, a paragraph; the same in
   `README.ru.md`.
5. **Run it** — `./install.sh --<name>`, look at the desktop, read the journal, say in the
   PR what you saw.

## Adding a weather source

The four sources — Open-Meteo, MET Norway, WeatherAPI.com, Visual Crossing — are objects of
one shape in `weather/package/contents/ui/Sources.js`, and the view knows nothing else
about them (decision 13). A fifth is:

1. **The object** — `id`, `needsKey`, `maxDays`, `refreshMin`, `build(lat, lon, days, key,
   opts)` returning `{ url, headers }`, and `parse(body, days, opts)` returning the common
   shape: `{ current: { temp, feels, code, wind, windDir, humidity }, daily: [ { date, min,
   max, code, pop }, … ] }`. Add it to `all` and `ids`. Rules: **codes map to WMO weather
   codes**, so the one table of condition words (and its translations) serves it; **values
   are metric** — °C, km/h, % — the view converts to the user's units; a field the source
   does not have is `null`, never 0, and the view leaves it out. `opts.utcOffsetMin` is
   the place's UTC offset, for a source whose series is in UTC (MET Norway) or that names
   dates (Visual Crossing).
2. **The settings page**, `configLocation.qml` — the id in `sourceIds`, the item in the
   *Source* `ComboBox` at the same index, the id in `needsKey` if a key is required, the
   hint saying where a free key comes from, and the `terms()` string: what the source's
   terms ask for, in one or two lines under the forecast settings.
3. **The attribution line** — a case in `attributionText()` in `WeatherView.qml`, with the
   wording the source's terms ask for. Every source so far asks for one.
4. **Terms first.** Read them before the parser: attribution, a required `User-Agent`
   (MET Norway), rate limits and what counts as a request (Visual Crossing bills a record
   per forecast day, so the request names its dates), coordinate precision.
5. **A key only through the settings field.** `apiKey` is the user's own, from their own
   account; never a key in the code, in a default or in a test file — the repository is
   public.
6. **Strings and catalogs** — `python3 po/extract.py`, then the new strings in ten
   languages.
7. **Run it** — `./install.sh --weather`, read the journal, and say in the PR what was
   verified live and what only on a sample response from the source's documentation: for
   a keyed source without a key that is the honest state (decision 13).

## Translations

The widgets use KDE's own ki18n with gettext catalogs, one domain per widget —
`plasma_applet_org.s1dd1.plaintop` for the monitor, `plasma_applet_org.s1dd1.plainspectrum`
for the visualizer, `plasma_applet_org.s1dd1.plainplayer` for the player,
`plasma_applet_org.s1dd1.plainweather` for the weather. The language is Plasma's
(System Settings → Region & Language); dates and decimal separators follow its Formats.
Why this design and what it costs — `docs/DECISIONS.md`, decision 7. There are ten
languages in `po/`; all but English (the source) and Russian are machine translations
waiting for a native speaker — a review of one is as welcome as a new one.

```bash
python3 po/extract.py            # refresh po/*.pot from the sources, merge into every language
python3 po/extract.py --init uk  # start a new language
lokalize po/uk/plasma_applet_org.s1dd1.plaintop.po   # or Poedit, or any .po editor
./install.sh --plasmoid          # builds the monitor's .mo files into its package
./install.sh --spectrum          # the same for the visualizer
./install.sh --player            # … the player
./install.sh --weather           # … the weather
```

`extract.py` also starts what is missing: a new domain gets a catalog in every language the
project already has, through `msginit`. ⚠️ Two things to do before translating a merged
catalog. `msgmerge` fills it with fuzzy guesses — old translations attached to new strings —
which are skipped at run time and mislead the translator; clear them first:
`msgattrib --clear-fuzzy --empty -o file.po file.po`. And a catalog `msginit` wrote for
Chinese carries `Plural-Forms: nplurals=INTEGER`, which `msgfmt --check` refuses — fix the
header by hand (`docs/GOTCHAS.md`).

Rules for the source strings:

- **They are English.** Russian is a translation like any other.
- **Placeholders are `%1`, `%2`**, never a string glued to a number: "shown %1 of %2",
  not `"shown " + a + " of " + b`. A translator needs the whole sentence.
- **Numbers with a noun use the plural call**, `i18np` / `i18ncp`: Russian, Ukrainian and
  Polish have three forms, and the catalog's own rules pick them.
- **Give context where a word is ambiguous**: `i18nc("palette: colour of", "Header:")`.
- **Files only the plasmoid loads call `i18n()`**; the shared QML in `monitor/shared/` and
  `spectrum/shared/` calls `tr.i18n()` through a `KI18nContext` — a habit from the retired
  window hosts, whose bare `qml6` runner had no `i18n()` of its own.
- **A shared file with two plasmoid hosts calls bare `i18n()`.** `player/shared/PlayerView.qml`
  is loaded by the player and by the visualizer, and a bare `i18n()` resolves through the
  domain of the plasmoid that loads the copy: the same file translates from the player's
  catalog inside plainplayer and from the visualizer's inside plainspectrum (verified
  2026-09-23). So `po/extract.py` lists `player/shared` under both domains, and a new
  string there lands in two catalogs. A `KI18nContext` with a hard-wired domain would pin
  the file to one.
- **Do not translate keys**: sensor ids, config keys, block ids.
- **The menu and autostart entries** the retired window hosts' `setup.py` wrote are marked
  with `N_(context, text)`; the strings stay in the catalogs as long as the code does.

`msgfmt --check` runs on every install, so a translation that drops a `%1` fails there
instead of on screen. To see the widget in another language without changing yours, run
it in a window: `LANGUAGE=de plasmawindowed org.s1dd1.plaintop`. For that locale's dates
and numbers too, set `LANG`/`LC_ALL` to it and give it an empty `XDG_CONFIG_HOME`, since
KDE applies your own Formats over `LANG`. ⚠️ The locale
must be generated (`locale -a`), or gettext falls back to C and shows English — without
root, `localedef -i de_DE -f UTF-8 $DIR/de_DE.UTF-8` and `LOCPATH=$DIR` do it (see
`docs/GOTCHAS.md`).

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
  catalogs, see [Translations](#translations). Terminal output — `install.sh`, the setup
  scripts, the generator — is plain English and is not translated: whoever installs
  from the repository reads it.

## Commits and pull requests

- One commit per idea, with a body that says **why** and **what was verified by running it**.
  Look at `git log` for the shape.
- English is preferred for new commit messages; the existing history is Russian.
- Issues do not need a template. "This is what I ran, this is what happened, this is what I
  expected" is enough.

## License

By contributing you agree that your work is distributed under
[GPL-2.0-or-later](LICENSE), the license of the project.
