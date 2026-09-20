#!/usr/bin/env bash
# Разложить plaintop в систему и запустить.
#
# Источник истины — каталог widget/ этого репозитория. В ~/.config/conky файлы
# попадают отсюда, а не наоборот: правки делаются в репо, затем ./install.sh.
set -uo pipefail
cd "$(dirname "$0")"
REPO=$PWD
DEST="$HOME/.config/conky"
AUTOSTART="$HOME/.config/autostart"
APPS="$HOME/.local/share/applications"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
dim()  { printf '\033[2m%s\033[0m\n' "$*"; }

input_shape() {
    python3 - <<'PY'
import sys
try:
    from Xlib import display
    from Xlib.ext import shape
except ImportError:
    print("  python-xlib не установлен — проверить область ввода нечем"); sys.exit(0)
d = display.Display(); root = d.screen().root
def walk(w, out):
    try: cls = w.get_wm_class()
    except Exception: cls = None
    if cls and any("conky" in c.lower() for c in cls): out.append((w, cls))
    try:
        for c in w.query_tree().children: walk(c, out)
    except Exception: pass
    return out
ws = walk(root, [])
if not ws:
    print("  окон conky нет"); sys.exit(0)
for w, cls in ws:
    g = w.get_geometry()
    n = len(list(w.shape_get_rectangles(shape.SK.Input).rectangles))
    verdict = "клики проходят" if n == 0 else "ЛОВИТ КЛИКИ"
    print(f"  {hex(w.id)}  class={cls[0]}  {g.width}x{g.height}  input={n} → {verdict}")
PY
}

status() {
    echo "== Процессы"
    if pgrep -x conky >/dev/null; then pgrep -ax conky | sed 's/^/  /'; else dim "  conky не запущен"; fi
    echo "== Окно и область ввода"; input_shape
    echo "== Разложено"
    for f in plainext.conf plainext.lua services.sh start.sh clickthrough.py; do
        if [ -f "$DEST/$f" ]; then
            if cmp -s "$REPO/widget/$f" "$DEST/$f"; then grn "  ✓ $f — совпадает с репо"
            else red "  ≠ $f — РАЗОШЁЛСЯ с репо"; fi
        else red "  ✗ $f — не разложен"; fi
    done
    [ -f "$AUTOSTART/conky-plainext.desktop" ] && grn "  ✓ автозапуск" || red "  ✗ автозапуск не настроен"
    [ -f "$APPS/conky.desktop" ] && grn "  ✓ заглушка пакетного conky.desktop" || red "  ✗ заглушки нет"
}

deps() {
    local miss=0
    echo "== Зависимости"
    command -v conky >/dev/null && grn "  ✓ conky $(conky --version 2>/dev/null | head -1 | awk '{print $2}')" || { red "  ✗ conky"; miss=1; }
    python3 -c "import Xlib" 2>/dev/null && grn "  ✓ python-xlib" || { red "  ✗ python-xlib (нужен для click-through)"; miss=1; }
    command -v sensors >/dev/null && grn "  ✓ lm_sensors" || { red "  ✗ lm_sensors (температуры и обороты)"; miss=1; }
    # ⚠️ Без конвейера намеренно: при set -o pipefail связка `fc-list | grep -q` врёт.
    # grep -q выходит на первом совпадении, fc-list ловит SIGPIPE, конвейер возвращает
    # ошибку — и проверка уходит в «не найдено», хотя шрифт есть.
    local fam; fam=$(fc-match -f '%{family}' 'JetBrainsMono Nerd Font Mono' 2>/dev/null)
    case "$fam" in
        *"JetBrainsMono Nerd Font Mono"*) grn "  ✓ шрифт JetBrainsMono Nerd Font Mono" ;;
        *) red "  ✗ шрифт JetBrainsMono Nerd Font Mono (ttf-jetbrains-mono-nerd)"; miss=1 ;;
    esac
    return $miss
}

case "${1:-}" in
  --status)      status; exit 0 ;;
  --check-input) input_shape; exit 0 ;;
  --deps)        deps; exit $? ;;
  -h|--help)     echo "Использование: $0 [--status|--check-input|--deps]"; exit 0 ;;
esac

deps || { echo; red "Не хватает зависимостей — поставь их и повтори."; exit 1; }

echo; echo "== Раскладываю"
mkdir -p "$DEST" "$AUTOSTART" "$APPS"
for f in plainext.conf plainext.lua services.sh start.sh clickthrough.py; do
    cp "$REPO/widget/$f" "$DEST/$f" && echo "  → $DEST/$f"
done
chmod +x "$DEST"/*.sh "$DEST"/*.py
cp "$REPO/widget/conky-plainext.desktop" "$AUTOSTART/" && echo "  → $AUTOSTART/conky-plainext.desktop"
# Заглушка поверх /usr/share/applications/conky.desktop: иначе KWin поднимет пакетный
# conky с дефолтным конфигом. Каталог пользователя идёт раньше в XDG_DATA_DIRS.
cp "$REPO/widget/conky-mask.desktop" "$APPS/conky.desktop" && echo "  → $APPS/conky.desktop (заглушка)"

# excludeApps должен совпадать с own_window_class, иначе исключение молча не сработает.
if command -v kwriteconfig6 >/dev/null; then
    kwriteconfig6 --file ksmserverrc --group General --key excludeApps 'conky,conky-plainext'
    echo "  → ksmserverrc: excludeApps=conky,conky-plainext"
fi

echo; echo "== Запускаю"
"$DEST/start.sh" >/dev/null 2>&1 &
sleep 8
echo; status
