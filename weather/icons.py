#!/usr/bin/env python3
"""Text-art weather icons for plainweather — the generator.

Writes package/contents/ui/Icons.js next to this file (the widget loads that file; it is
committed, not built at install time), so after an edit here run

    python3 weather/icons.py

from the repository root and commit both files. No dependencies beyond the standard library;
the output is deterministic, so a second run changes nothing. `--show` prints the icons.

Every icon is 48 columns by 24 rows of characters, background spaces, drawn by the widget
as one Text in its own monospace font at a few pixels per character, with the rows packed
at the font's pixel size: each character is one dot of the picture. A cell of JetBrains
Mono is then 0.6 wide for 1 tall (1.8 x 3 px at 3 px — measured with TextMetrics in the
offscreen host, 2026-09-23), so x is scaled by ASPECT in every distance, and a disc that is
round in cells here comes out round on the screen.

Palette: '#' outline and bolt, ':' cloud fill, '=' dense fill (sun disc, overcast, fog),
rays '\\ | / -', rain '/', snow '*', fog '~', drizzle '.' and ''', hail 'o'.
"""
import math
import os

W, H = 48, 24
ASPECT = 0.6            # cell width / row height in the widget's font

# WMO code -> icon id, in the order the table is written; the same codes
# WeatherView.condition() names.
CODES = [
    ("clear", [0]),
    ("mostly-clear", [1]),
    ("partly", [2]),
    ("overcast", [3]),
    ("fog", [45, 48]),
    ("drizzle", [51, 53, 55, 56, 57]),
    ("rain", [61, 63, 65, 66, 67]),
    ("showers", [80, 81, 82]),
    ("snow", [71, 73, 77]),
    ("snow-heavy", [75, 85, 86]),
    ("thunder", [95]),
    ("thunder-hail", [96, 99]),
]


def blank():
    return [[" "] * W for _ in range(H)]


def put(g, x, y, ch):
    if 0 <= x < W and 0 <= y < H:
        g[y][x] = ch


# ── Shapes ────────────────────────────────────────────────────────────────────
# A shape is a function (x, y) -> bool: whether the cell is inside. Distances are in rows,
# x scaled by ASPECT. It is rasterised into a mask, and the outline is the inside cells
# with an outside neighbour — a row up or down, or one or two cells (about a row) to the
# side — so a union of discs has no seams and the line is one row thick either way.

NEAR = ((1, 0), (-1, 0), (2, 0), (-2, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1))


def disc(cx, cy, r):
    return lambda x, y: ((x - cx) * ASPECT) ** 2 + (y - cy) ** 2 <= r * r


def rect(x0, x1, y0, y1):
    return lambda x, y: x0 <= x <= x1 and y0 <= y <= y1


def union(*shapes):
    return lambda x, y: any(s(x, y) for s in shapes)


def cloud_shape(cx, cy, s=1.0):
    """Three bumps on a base with rounded ends, centred at (cx, cy), about 30 x 12 cells at
    s = 1: the bumps' centres and radii are in rows, the base a stadium two discs wide."""
    def at(u, v):
        return cx + u * s / ASPECT, cy + v * s
    parts = []
    for u, v, r in ((-5.5, 1.5, 3.7), (0.0, -1.0, 4.7), (5.0, 1.5, 3.7), (-6.5, 3.5, 2.2), (6.5, 3.5, 2.2)):
        px, py = at(u, v)
        parts.append(disc(px, py, r * s))
    (x0, y0), (x1, y1) = at(-6.5, 1.5), at(6.5, 5.7)
    parts.append(rect(x0, x1, y0, y1))
    return union(*parts)


def mask_of(shape):
    return [[bool(shape(x, y)) for x in range(W)] for y in range(H)]


def near(m, x, y, value):
    """Whether a cell near (x, y) — see NEAR — has `value` in the mask (the frame counts as
    the mask's own value, so the picture's edge draws no outline)."""
    for dx, dy in NEAR:
        nx, ny = x + dx, y + dy
        if 0 <= nx < W and 0 <= ny < H and m[ny][nx] == value:
            return True
    return False


def draw(g, shape, fill=":", edge="#", halo=False):
    """Paints the shape: `fill` inside, `edge` on the outline. With `halo`, the cells just
    outside are cleared, so a shape drawn earlier (the sun) stands apart from this one."""
    m = mask_of(shape)
    for y in range(H):
        for x in range(W):
            if m[y][x]:
                put(g, x, y, edge if near(m, x, y, False) else fill)
            elif halo and near(m, x, y, True):
                put(g, x, y, " ")


def cloud(g, cx, cy, s=1.0, fill=":", edge="#", halo=False):
    draw(g, cloud_shape(cx, cy, s), fill, edge, halo)


RAY_CHARS = ("-", "\\", "|", "/", "-", "\\", "|", "/")   # by eighth of a turn, clockwise from right


def ray(g, x, y, ch):
    if 0 <= x < W and 0 <= y < H and g[y][x] == " ":
        g[y][x] = ch


def sun(g, cx, cy, r, rays=range(8)):
    """A dense disc and, a row and a half off its rim, rays about a row and a half long:
    three cells across, two rows up and down, two dots on the diagonals. `rays` picks them
    by eighth of a turn (0 right, 2 down, 4 left, 6 up). Drawn on empty cells only."""
    draw(g, disc(cx, cy, r), fill="=", edge="#")
    for a in rays:
        ch = RAY_CHARS[a]
        if a in (0, 4):
            sign = 1 if a == 0 else -1
            for k in range(math.ceil((r + 1.5) / ASPECT), math.floor((r + 3.0) / ASPECT) + 1):
                ray(g, round(cx + sign * k), round(cy), ch)
        elif a in (2, 6):
            sign = 1 if a == 2 else -1
            for k in (r + 1.5, r + 2.5):
                ray(g, round(cx), round(cy + sign * k), ch)
        else:
            # Two dots: the first a row and three quarters off the rim, the second one cell
            # and one row further out — a diagonal step, whatever the rounding of the first.
            t = a * math.pi / 4
            k = r + 1.75
            x, y = round(cx + k * math.cos(t) / ASPECT), round(cy + k * math.sin(t))
            sx, sy = (1 if math.cos(t) > 0 else -1), (1 if math.sin(t) > 0 else -1)
            ray(g, x, y, ch)
            ray(g, x + sx, y + sy, ch)


def strokes(g, xs, y0, rows, ch="/"):
    """Slanted rain strokes: each starts at (x, y0) and runs down-left `rows` dots."""
    for x in xs:
        for k in range(rows):
            put(g, x - k, y0 + k, ch)


def scatter(g, rows, ch, x1=39):
    """Dots on the given rows, up to column x1: each row is (y, first x, step)."""
    for y, x0, step in rows:
        for x in range(x0, x1, step):
            put(g, x, y, ch)


def bolt(g, x0, y0):
    """A zigzag two cells thick, seven rows tall: down-left, a ledge to the right, down-left
    again, narrowing to a point."""
    for k in range(3):                       # upper stroke
        put(g, x0 - k, y0 + k, "#")
        put(g, x0 - k + 1, y0 + k, "#")
    for x in range(x0 - 2, x0 + 3):          # the ledge
        put(g, x, y0 + 2, "#")
    for k in range(4):                       # lower stroke
        x = x0 + 1 - k
        put(g, x, y0 + 3 + k, "#")
        if k < 3:
            put(g, x + 1, y0 + 3 + k, "#")


# ── The set ───────────────────────────────────────────────────────────────────

def icons():
    out = {}

    g = blank()
    sun(g, 24, 12, 5.7)
    out["clear"] = g

    g = blank()
    sun(g, 20, 9, 4.7)
    cloud(g, 33, 17, 0.62, halo=True)
    out["mostly-clear"] = g

    g = blank()
    sun(g, 33, 6, 3.7, rays=(5, 6, 7, 0))   # the rays the cloud would hide are not drawn
    cloud(g, 22, 15, 1.0, halo=True)
    out["partly"] = g

    g = blank()
    cloud(g, 30, 9, 0.8, fill=" ")
    cloud(g, 21, 15, 1.0, fill="=", halo=True)
    out["overcast"] = g

    g = blank()
    cloud(g, 24, 7, 1.0, fill="=")
    for y, x0, x1 in ((16, 10, 38), (18, 8, 34), (20, 12, 40), (22, 9, 33)):
        for x in range(x0, x1):
            put(g, x, y, "~")
    out["fog"] = g

    g = blank()
    cloud(g, 24, 8, 1.0)
    scatter(g, ((17, 13, 8), (19, 17, 8), (21, 15, 8)), "'")
    scatter(g, ((18, 19, 8), (20, 12, 8), (22, 21, 8)), ".")
    out["drizzle"] = g

    g = blank()
    cloud(g, 24, 8, 1.0)
    strokes(g, (14, 21, 28, 35), 17, 3)
    out["rain"] = g

    g = blank()
    cloud(g, 24, 8, 1.0)
    strokes(g, (13, 17, 21, 25, 29, 33, 37), 17, 4)
    out["showers"] = g

    g = blank()
    cloud(g, 24, 8, 1.0)
    scatter(g, ((17, 14, 8), (19, 10, 8), (21, 14, 8)), "*")
    out["snow"] = g

    g = blank()
    cloud(g, 24, 8, 1.0)
    scatter(g, ((16, 12, 6), (17, 15, 6), (18, 12, 6), (19, 15, 6), (20, 12, 6), (21, 15, 6), (22, 12, 6)), "*")
    out["snow-heavy"] = g

    g = blank()
    cloud(g, 24, 8, 1.0)
    bolt(g, 24, 16)
    out["thunder"] = g

    g = blank()
    cloud(g, 24, 8, 1.0)
    bolt(g, 24, 16)
    for x, y in ((12, 18), (16, 21), (14, 23), (34, 18), (37, 21), (33, 23)):
        put(g, x, y, "o")
    out["thunder-hail"] = g

    return {k: ["".join(r) for r in v] for k, v in out.items()}


# ── Output ────────────────────────────────────────────────────────────────────

def render_js(icons_by_id):
    lines = [
        ".pragma library",
        "// Generated by weather/icons.py — DO NOT EDIT: edit the generator and run",
        "//     python3 weather/icons.py",
        "// from the repository root. Text-art weather icons, %d columns by %d rows each, drawn" % (W, H),
        "// by the widget as one Text in its own monospace font at a few pixels per character.",
        "",
        "var WIDTH = %d" % W,
        "var HEIGHT = %d" % H,
        "// The empty picture: what the widget measures its icon's box on when it has none to draw.",
        "var BLANK = new Array(HEIGHT).fill(\" \".repeat(WIDTH))",
        "",
        "var ICONS = {",
    ]
    ids = [i for i, _ in CODES]
    for n, i in enumerate(ids):
        rows = icons_by_id[i]
        assert len(rows) == H and all(len(r) == W for r in rows), i
        lines.append('    "%s": [' % i)
        for m, r in enumerate(rows):
            lines.append('        "%s"%s' % (r.replace("\\", "\\\\"), "," if m < H - 1 else ""))
        lines.append("    ]%s" % ("," if n < len(ids) - 1 else ""))
    lines += [
        "}",
        "",
        "// WMO weather code -> icon id, or null when there is no icon for it (the codes are",
        "// the ones WeatherView.condition() names).",
        "function forCode(wmo) {",
        "    // Number(null) is 0 — and a source that gave no code did not say \"clear\".",
        "    if (wmo === null || wmo === undefined || wmo === \"\")",
        "        return null",
        "    switch (Number(wmo)) {",
    ]
    for i, codes in CODES:
        lines.append("    %s return \"%s\"" % (" ".join("case %d:" % c for c in codes), i))
    lines += [
        "    default: return null",
        "    }",
        "}",
        "",
    ]
    return "\n".join(lines)


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "package", "contents", "ui", "Icons.js")
    text = render_js(icons())
    old = open(out, encoding="utf-8").read() if os.path.exists(out) else None
    if old == text:
        print("Icons.js is up to date")
        return
    with open(out, "w", encoding="utf-8") as f:
        f.write(text)
    print("wrote", os.path.relpath(out))


if __name__ == "__main__":
    import sys
    if "--show" in sys.argv:
        for k, v in icons().items():
            print(k)
            print("\n".join("|" + r + "|" for r in v))
    else:
        main()
