# schema — the widget description

English · [Русский](README.ru.md)

Two files, both **independent of the engine**:

- **`widget.json`** — the layout: which blocks, in what order, with what parameters.
- **`blocks.json`** — the dictionary of block types: which ones exist, what parameters they take.
  The settings dialog is built from it rather than from a list in the code — otherwise a new block
  type would mean editing the interface.

A block entry:

```json
{ "id": "cpu", "type": "cpu", "enabled": true,
  "params": { "per_socket": true, "model_line": true, "top_processes": 5 } }
```

## How this gets into the widget

```
schema/widget.json ─┐
                    ├─ monitor/generate.py ──→ package/contents/code/description.js ─→ main.qml
schema/blocks.json ─┘
```

The generator validates the description (unknown block type, undeclared parameter, wrong value
type) and fills in the defaults from the dictionary. An invalid description stops the installation —
better a refusal than an empty widget and a hunt for the cause in QML.

⚠️ Why JS and not reading the JSON from QML: in plasmashell `XMLHttpRequest` to `file://` is
forbidden (`../docs/GOTCHAS.md`), while importing a `.js` file works.

`description.js` is generated and is not kept in git — only `schema/*.json` gets edited.

## Open-ended block types

Two types are not tied to a particular quantity and make the dictionary extensible without code changes:

- **`command`** — a line from the output of an arbitrary command, with its own interval;
- **`sensor`** — any ksystemstats sensor by its id, with a bar or without one.

## Parameters the machine fills in itself

A parameter in the dictionary may say what kind of thing it holds, so the editor can offer the
machine's own list instead of asking for an id:

```json
"nvmeSensor": { "type": "string", "name": "NVMe temperature sensor (empty — find it)",
                "default": "", "pick": "sensor",
                "pattern": "^lmsensors/nvme-[^/]+/temp\\d+$" }
```

- **`pick`** — `sensor` (a searchable list of everything ksystemstats reports, with the highlighted
  sensor's live value), `iface` (the network interfaces found in the sensor tree), or `mount`
  (the mount points from `/proc/self/mounts`).
- **`pattern`** — narrows the list, and is what the widget itself falls back to.

A stored value is a **preference**, not a requirement: it wins while the machine has it, and when it
does not, `pattern` finds the replacement. An empty value means "find it yourself" from the start —
which is why the layout shipped in `widget.json` carries no sensor ids of the machine it was written
on. See decision 6 in `../docs/DECISIONS.md`.

## Editing from the interface

The *Blocks* page in the widget settings reads that same layout: enable, disable, reorder,
add a block of any type from the dictionary, remove one, adjust the parameters — and puts the
result into the plasmoid's settings as a JSON string. As long as that is empty, the layout from the
package is used; the *Reset* button brings it back.
