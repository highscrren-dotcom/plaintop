# Project decisions

English · [Русский](DECISIONS.ru.md)

Recorded with the reasoning, not just the outcome: a month later it matters more to
understand "why" than "what".

## 1. Widget engine — a KDE plasmoid, not conky (2026-09-20)

**Decision:** the target implementation is our own Plasma 6 plasmoid in QML.
The conky implementation stays working until it is replaced and lives in `conky/`.

**Why not conky.** It works, but every one of its quirks under KDE cost us time,
and none of them would be a problem for a plasmoid:

| What hurt with conky | With a plasmoid |
|---|---|
| No click-through — we killed the input region through X Shape | A desktop plasmoid does not intercept clicks by design |
| X11 only, goes through XWayland | QML natively, Wayland with no layer in between |
| Three autostart sources, three reboots to find them | KDE places the widget itself and keeps it in the session |
| `own_window_type` breaks transparency | Not an issue |
| Its own config language instead of a structure | QML plus the plasmoid's built-in config |

Details on each point — `GOTCHAS.md`.

**And the main argument.** Plasmoids have a **built-in settings window**: Plasma builds
the dialog itself from `config/main.xml` and stores the values. So the editor the project
was started for largely comes for free — instead of a separate PySide6 application that
we would have to write and maintain.

**What we pay.** We will have to build the data sources ourselves. conky ships two dozen
substitutions out of the box: CPU load, top processes, hwmon, NVIDIA, filesystems,
network. In a plasmoid that is either `QProcess`/`executable` sources, or reading `/proc`
and `/sys` from QML. Estimate: a week against a day.

**What softens the price.** Some of the sources are already written in Python and shell
and do not depend on conky: per-NUMA-node accounting (`conky/plainext.lua`), the state of
docker/ollama/updates (`conky/services.sh`). Their logic ports over almost as is.

**What the decision does NOT change.** The three-layer scheme stays: description
(`schema/widget.json`) → generator → interface. The description says *what to show*,
not *how to write it down* — so changing the engine touches only the generator. That is
exactly why the schema was introduced.

**Revisit if:** it turns out a plasmoid cannot give the text density or the refresh rate
we need without noticeable load. Then conky stays — it works.

## 2. Data — from ksystemstats sensors, not from `/proc` by hand (2026-09-20)

**Decision:** the plasmoid subscribes to sensors through `org.kde.ksysguard.sensors`.
External commands (`sensors -u`, `nvidia-smi`, `ps`) only for what the sensors do not
have, and on a rare interval.

**How we chose.** We took apart four approaches, each one verified by running it on s1dPC:

| Approach | Outcome |
|---|---|
| **ksysguard sensors** | 620 ready-made IDs: `cpu/*`, `gpu/*`, `memory/*`, `disk/*`, `network/*`, `lmsensors/*`, `os/*`. Zero command launches |
| `DataSource{engine:"executable"}` | Works, but it is a fork on every tick: `sensors -u` 25 ms, `nvidia-smi` 29 ms. The engine has no timeout at all |
| `XMLHttpRequest` to `file:///proc/stat` | **Rejected.** Inside plasmashell Qt forbids it; it turns on only with `QML_XHR_ALLOW_FILE_READ=1` for the whole shell — a system-wide setting and weaker access to save 2 ms |
| The `systemmonitor` engine | **Does not exist in Plasma 6.** Verified: `valid: false`. Monitoring moved to ksystemstats |

**What this changes in the price of decision 1.** "We will have to build the data sources
ourselves" turned out to be an overestimate: what we reached for `hwmon`, `nvidia-smi`
and `ps` for in conky, Plasma already computes and hands out by subscription. Our own
commands remain only for docker, ollama and pending updates — `services.sh` was launching
them there anyway.

**What we pay.** A dependency on the `ksystemstats` daemon: it comes up on subscription
(DBus activation) and does not answer instantly — for the first 1–1.5 s a sensor is in
the "loading" state. So at startup we draw a dash, not a zero: a zero would lie.

**On formatting, separately.** We do not use the ready-made `formattedValue` and
`Formatter`: they insert U+200B before "%" and U+2009 before "°C". In monospaced text
that pulls the columns out of line — we format it ourselves.

**Revisit if:** we need values the sensors do not have (GPU fan speed, encoder/decoder,
detailed VRAM per process) — then an `executable` with an interval of a few seconds joins
them, but not instead of the sensors.
