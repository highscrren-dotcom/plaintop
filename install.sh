#!/usr/bin/env bash
# Разложить plaintop в систему и запустить.
#
# Источник истины — каталоги conky/ и plasmoid/ этого репозитория. В ~/.config/conky
# и ~/.local/share/plasma/plasmoids файлы попадают отсюда, а не наоборот:
# правки делаются в репо, затем ./install.sh.
set -uo pipefail
cd "$(dirname "$0")"
REPO=$PWD
DEST="$HOME/.config/conky"
AUTOSTART="$HOME/.config/autostart"
APPS="$HOME/.local/share/applications"
PLASMOID_ID="org.s1dd1.plaintop"
PLASMOID_SRC="$REPO/plasmoid/package"
PLASMOID_DEST="$HOME/.local/share/plasma/plasmoids/$PLASMOID_ID"

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

# Плазмоид ставится идемпотентно: kpackagetool6 сам решает, установка это или
# обновление, а состояние применяется в любом случае.
plasmoid_install() {
    echo "== Плазмоид"
    if ! command -v kpackagetool6 >/dev/null; then
        red "  ✗ kpackagetool6 не найден — плазмоид не поставить"; return 1
    fi
    # Описание → пакет. Негодное описание останавливает установку: лучше
    # отказаться здесь, чем увидеть пустой виджет и искать причину в QML.
    if ! python3 "$REPO/plasmoid/generate.py"; then
        red "  ✗ описание в schema/ не прошло проверку — пакет не обновлён"; return 1
    fi
    local mode=--install
    [ -d "$PLASMOID_DEST" ] && mode=--upgrade
    if kpackagetool6 --type Plasma/Applet $mode "$PLASMOID_SRC" >/dev/null 2>&1; then
        grn "  ✓ $PLASMOID_ID ($mode)"
    else
        red "  ✗ $PLASMOID_ID — $mode не прошёл"; return 1
    fi
    # ⚠️ Проверено 20.09.2026: plasmashell держит QML пакета в кэше. Переустановки мало,
    # пересоздания апплета тоже — новая разметка появляется только после перезапуска
    # оболочки. Поэтому состояние доводится до конца здесь, а не оставляется пользователю.
    if systemctl --user --quiet is-active plasma-plasmashell.service; then
        systemctl --user restart plasma-plasmashell.service && grn "  ✓ plasmashell перезапущен — виджет с новым QML"
    else
        dim "  plasmashell не под systemd — перезапусти оболочку сам, иначе QML останется старым"
    fi
    plasmoid_place
}

# Погасить conky, пока идёт перенос на плазмоид, — и вернуть обратно.
# ⚠️ Только `pkill -x conky`: шаблон `pkill -f 'conky -c'` совпадает с командной
# строкой собственной оболочки и убивает её.
conky_off() {
    echo "== Гашу conky"
    pkill -x conky && grn "  ✓ процесс остановлен" || dim "  conky и так не запущен"
    if [ -f "$AUTOSTART/conky-plainext.desktop" ]; then
        # Hidden=true — штатный способ XDG выключить автозапуск, файл остаётся на месте.
        grep -q "^Hidden=true$" "$AUTOSTART/conky-plainext.desktop" \
            || printf 'Hidden=true\n' >> "$AUTOSTART/conky-plainext.desktop"
        grn "  ✓ автозапуск выключен (Hidden=true)"
    else
        dim "  автозапуска и так нет"
    fi
    # excludeApps в ksmserverrc уже не даёт сессии восстановить conky при входе.
    echo; status
}

conky_on() {
    echo "== Возвращаю conky"
    if [ -f "$AUTOSTART/conky-plainext.desktop" ]; then
        sed -i '/^Hidden=true$/d' "$AUTOSTART/conky-plainext.desktop"
        grn "  ✓ автозапуск включён"
    else
        cp "$REPO/conky/conky-plainext.desktop" "$AUTOSTART/" && grn "  ✓ автозапуск восстановлен"
    fi
    pgrep -x conky >/dev/null || "$DEST/start.sh" >/dev/null 2>&1 &
    sleep 8
    echo; status
}

# Скриптинг plasmashell отвечает не сразу после перезапуска — ждём, а не гадаем.
plasmashell_ready() {
    local i
    for i in $(seq 1 30); do
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript 'print(1)' \
            >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

# Идемпотентно: если виджет уже на рабочем столе — ничего не делаем, иначе сажаем на место.
plasmoid_place() {
    local n
    n=$(grep -c "^plugin=$PLASMOID_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then dim "  уже на рабочем столе — место не трогаю"; return 0; fi
    plasmashell_ready || { red "  ✗ plasmashell не отвечает — добавь виджет вручную"; return 1; }
    # ⚠️ Координаты в addWidget бесполезны: место и размер задаются подсказками
    # Layout.* внутри виджета, а положение контейнер всё равно сбрасывает в угол.
    # Зазор от края рисуется самим виджетом (настройки «Отступ слева/сверху»).
    local id
    id=$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "print(desktops()[0].addWidget(\"$PLASMOID_ID\").id)" 2>/dev/null | tr -dc '0-9')
    if [ -z "$id" ]; then red "  ✗ не удалось добавить на рабочий стол"; return 1; fi
    grn "  ✓ добавлен на рабочий стол (id=$id)"
}

plasmoid_status() {
    echo "== Плазмоид"
    if [ ! -d "$PLASMOID_DEST" ]; then red "  ✗ не установлен"; return 0; fi
    local diff=0 f rel
    while IFS= read -r f; do
        rel=${f#"$PLASMOID_SRC"/}
        cmp -s "$f" "$PLASMOID_DEST/$rel" || { red "  ≠ $rel — РАЗОШЁЛСЯ с репо"; diff=1; }
    done < <(find "$PLASMOID_SRC" -type f)
    [ $diff -eq 0 ] && grn "  ✓ установлен, файлы совпадают с репо"
    # Присутствие на рабочем столе читается из конфига сессии, а не угадывается.
    local n; n=$(grep -c "^plugin=$PLASMOID_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then grn "  ✓ добавлен на рабочий стол ($n шт.)"
    else dim "  на рабочий стол не добавлен"; fi
}

status() {
    echo "== Процессы"
    if pgrep -x conky >/dev/null; then pgrep -ax conky | sed 's/^/  /'; else dim "  conky не запущен"; fi
    echo "== Окно и область ввода"; input_shape
    echo "== Разложено"
    for f in plainext.conf plainext.lua services.sh start.sh clickthrough.py; do
        if [ -f "$DEST/$f" ]; then
            # Сравниваем с подставленным @HOME@, иначе проверка врёт на каждом файле.
            if sed "s|@HOME@|$HOME|g" "$REPO/conky/$f" | cmp -s - "$DEST/$f"; then grn "  ✓ $f — совпадает с репо"
            else red "  ≠ $f — РАЗОШЁЛСЯ с репо"; fi
        else red "  ✗ $f — не разложен"; fi
    done
    if [ -f "$AUTOSTART/conky-plainext.desktop" ]; then
        if grep -q "^Hidden=true$" "$AUTOSTART/conky-plainext.desktop"; then
            dim "  • автозапуск выключен (Hidden=true) — вернуть: ./install.sh --conky-on"
        else grn "  ✓ автозапуск"; fi
    else red "  ✗ автозапуск не настроен"; fi
    [ -f "$APPS/conky.desktop" ] && grn "  ✓ заглушка пакетного conky.desktop" || red "  ✗ заглушки нет"
    echo; plasmoid_status
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
  --plasmoid)    plasmoid_install; exit $? ;;
  --conky-off)   conky_off; exit 0 ;;
  --conky-on)    conky_on; exit 0 ;;
  -h|--help)     echo "Использование: $0 [--status|--check-input|--deps|--plasmoid|--conky-off|--conky-on]"; exit 0 ;;
esac

deps || { echo; red "Не хватает зависимостей — поставь их и повтори."; exit 1; }

echo; echo "== Раскладываю"
mkdir -p "$DEST" "$AUTOSTART" "$APPS"
for f in plainext.conf plainext.lua services.sh start.sh clickthrough.py; do
    # ⚠️ @HOME@ подставляется здесь: сам conky переменные окружения в конфиге
    # не раскрывает, а зашивать /home/<кто-то> в репозиторий нельзя.
    sed "s|@HOME@|$HOME|g" "$REPO/conky/$f" > "$DEST/$f" && echo "  → $DEST/$f"
done
chmod +x "$DEST"/*.sh "$DEST"/*.py
cp "$REPO/conky/conky-plainext.desktop" "$AUTOSTART/" && echo "  → $AUTOSTART/conky-plainext.desktop"
# Заглушка поверх /usr/share/applications/conky.desktop: иначе KWin поднимет пакетный
# conky с дефолтным конфигом. Каталог пользователя идёт раньше в XDG_DATA_DIRS.
cp "$REPO/conky/conky-mask.desktop" "$APPS/conky.desktop" && echo "  → $APPS/conky.desktop (заглушка)"

# excludeApps должен совпадать с own_window_class, иначе исключение молча не сработает.
if command -v kwriteconfig6 >/dev/null; then
    kwriteconfig6 --file ksmserverrc --group General --key excludeApps 'conky,conky-plainext'
    echo "  → ksmserverrc: excludeApps=conky,conky-plainext"
fi

echo; echo "== Запускаю"
"$DEST/start.sh" >/dev/null 2>&1 &
sleep 8
echo; status
