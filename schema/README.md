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
                    ├─ plasmoid/generate.py ─→ package/contents/code/description.js ─→ main.qml
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

## Editing from the interface

The "Блоки" (Blocks) page in the widget settings reads that same layout: enable, disable, reorder,
add a block of any type from the dictionary, remove one, adjust the parameters — and puts the
result into the plasmoid's settings as a JSON string. As long as that is empty, the layout from the
package is used; the "Сбросить" (Reset) button brings it back.
