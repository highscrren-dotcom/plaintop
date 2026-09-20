#!/usr/bin/env python3
"""Сделать окно conky прозрачным для мыши.

У conky нет настройки click-through: в конфиге только шесть ключей own_window_*.
Поэтому ставим пустой input-region через расширение X Shape — окно продолжает
рисоваться, но events мыши сквозь него уходят на рабочий стол.

Тип окна при этом обязан остаться 'normal': с 'desktop' и 'override' KWin
перестаёт композитить окно и фон становится чёрным непрозрачным.
"""
import sys
import time

from Xlib import X, display
from Xlib.ext import shape


def find_conky(win, out):
    try:
        cls = win.get_wm_class()
    except Exception:
        cls = None
    if cls and any("conky" in c.lower() for c in cls):
        out.append(win)
    try:
        for child in win.query_tree().children:
            find_conky(child, out)
    except Exception:
        pass
    return out


def main():
    deadline = time.time() + float(sys.argv[1] if len(sys.argv) > 1 else 20)
    d = display.Display()
    if not d.has_extension("SHAPE"):
        print("расширение SHAPE недоступно", file=sys.stderr)
        return 1
    root = d.screen().root
    while time.time() < deadline:
        wins = find_conky(root, [])
        if wins:
            for w in wins:
                # пустой список прямоугольников = пустая область ввода
                w.shape_rectangles(shape.SO.Set, shape.SK.Input, X.YXBanded, 0, 0, [])
            d.sync()
            print(f"input-shape очищен у окон: {[hex(w.id) for w in wins]}")
            return 0
        time.sleep(0.5)
    print("окно conky не найдено", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
