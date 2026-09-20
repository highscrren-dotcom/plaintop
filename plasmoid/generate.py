#!/usr/bin/env python3
"""Генератор: описание виджета → то, что понимает плазмоид.

Слой описания (`schema/widget.json` + `schema/blocks.json`) от движка не зависит.
Здесь оно проверяется и превращается в JS-модуль внутри пакета: читать файл
из QML нельзя — в plasmashell запрещён XHR к file://, а импорт .js работает.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "schema"
OUT = ROOT / "plasmoid" / "package" / "contents" / "code" / "description.js"

TYPES = {
    "bool": lambda v: isinstance(v, bool),
    "int": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "string": lambda v: isinstance(v, str),
    "stringlist": lambda v: isinstance(v, list) and all(isinstance(x, str) for x in v),
}


def load(name):
    with (SCHEMA / name).open(encoding="utf-8") as f:
        return json.load(f)


def check(widget, vocab):
    """Возвращает список ошибок. Пустой список — описание годное."""
    errors = []
    seen = set()
    for i, block in enumerate(widget.get("blocks", [])):
        where = f"блок {i} (id={block.get('id', '?')})"
        bid = block.get("id")
        if not bid:
            errors.append(f"{where}: нет id")
        elif bid in seen:
            errors.append(f"{where}: id повторяется")
        else:
            seen.add(bid)

        btype = block.get("type")
        spec = vocab.get(btype)
        if spec is None:
            errors.append(f"{where}: неизвестный тип «{btype}» — его нет в blocks.json")
            continue

        params = spec.get("params", {})
        for key, value in (block.get("params") or {}).items():
            if key not in params:
                errors.append(f"{where}: параметр «{key}» не объявлен у типа «{btype}»")
                continue
            want = params[key]["type"]
            if not TYPES[want](value):
                errors.append(f"{where}: параметр «{key}» должен быть {want}, а это {value!r}")
    return errors


def fill(widget, vocab):
    """Проставляет параметрам значения по умолчанию из словаря."""
    out = []
    for block in widget["blocks"]:
        spec = vocab[block["type"]]
        params = {k: v["default"] for k, v in spec.get("params", {}).items()}
        params.update(block.get("params") or {})
        out.append({
            "id": block["id"],
            "type": block["type"],
            "enabled": block.get("enabled", True),
            "params": params,
        })
    return out


def main():
    widget = load("widget.json")
    vocab = {k: v for k, v in load("blocks.json").items() if not k.startswith("_")}

    errors = check(widget, vocab)
    if errors:
        print("Описание не годится:", file=sys.stderr)
        for e in errors:
            print("  ✗ " + e, file=sys.stderr)
        return 1

    blocks = fill(widget, vocab)
    dump = lambda o: json.dumps(o, ensure_ascii=False, indent=2)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        ".pragma library\n"
        "// Сгенерировано plasmoid/generate.py из schema/*.json — руками не править.\n"
        f"var BLOCKS = {dump(blocks)}\n\n"
        f"var VOCAB = {dump(vocab)}\n",
        encoding="utf-8",
    )
    print(f"  ✓ описание: {len(blocks)} блоков → {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
