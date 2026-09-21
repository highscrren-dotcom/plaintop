#!/usr/bin/env bash
# Deploy plaintop into the system and start it.
#
# Source of truth: the conky/ and plasmoid/ directories of this repo. Files flow from
# here into ~/.config/conky and ~/.local/share/plasma/plasmoids, never the other way
# around: edit in the repo, then run ./install.sh.
set -uo pipefail
cd "$(dirname "$0")"
REPO=$PWD
DEST="$HOME/.config/conky"
AUTOSTART="$HOME/.config/autostart"
APPS="$HOME/.local/share/applications"
PLASMOID_ID="org.s1dd1.plaintop"
PLASMOID_SRC="$REPO/plasmoid/package"
PLASMOID_DEST="$HOME/.local/share/plasma/plasmoids/$PLASMOID_ID"
SPECTRUM_ID="org.s1dd1.plainspectrum"
SPECTRUM_SRC="$REPO/spectrum"
SPECTRUM_DEST="$HOME/.local/share/plasma/plasmoids/$SPECTRUM_ID"
RELAY_DEST="$HOME/.local/share/plainspectrum"
UNIT_DEST="$HOME/.config/systemd/user"

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

# The plasmoid installs idempotently: kpackagetool6 decides by itself whether this is
# an install or an upgrade, and the state is applied either way.
plasmoid_install() {
    echo "== Плазмоид"
    if ! command -v kpackagetool6 >/dev/null; then
        red "  ✗ kpackagetool6 не найден — плазмоид не поставить"; return 1
    fi
    # Schema -> package. A bad schema aborts the install: better to refuse here than
    # to get an empty widget and hunt for the cause in QML.
    # The renderer and the data side are shared with the standalone window host, so they
    # live in plaintop/shared/ and are copied into the package here. Two edited copies of
    # the same QML is how they drift apart.
    cp "$REPO/plaintop/shared/MonitorData.qml" "$REPO/plaintop/shared/MonitorView.qml" \
        "$REPO/plasmoid/package/contents/ui/" || { red "  ✗ общие файлы не скопировались"; return 1; }

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
    # ⚠️ Verified 2026-09-20: plasmashell caches the package QML. Reinstalling is not
    # enough, and neither is re-creating the applet — the new layout shows up only
    # after the shell restarts. So we drive the state to completion here instead of
    # leaving it to the user.
    if systemctl --user --quiet is-active plasma-plasmashell.service; then
        systemctl --user restart plasma-plasmashell.service && grn "  ✓ plasmashell перезапущен — виджет с новым QML"
    else
        dim "  plasmashell не под systemd — перезапусти оболочку сам, иначе QML останется старым"
    fi
    plasmoid_place
}

# Stop conky while the move to the plasmoid is under way — and bring it back.
# ⚠️ Use `pkill -x conky` only: the pattern `pkill -f 'conky -c'` matches the command
# line of our own shell and kills it.
conky_off() {
    echo "== Гашу conky"
    pkill -x conky && grn "  ✓ процесс остановлен" || dim "  conky и так не запущен"
    if [ -f "$AUTOSTART/conky-plainext.desktop" ]; then
        # Hidden=true is the standard XDG way to disable autostart; the file stays in place.
        grep -q "^Hidden=true$" "$AUTOSTART/conky-plainext.desktop" \
            || printf 'Hidden=true\n' >> "$AUTOSTART/conky-plainext.desktop"
        grn "  ✓ автозапуск выключен (Hidden=true)"
    else
        dim "  автозапуска и так нет"
    fi
    # excludeApps in ksmserverrc already stops the session from restoring conky at login.
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

# plasmashell scripting does not answer right after a restart — wait, do not guess.
plasmashell_ready() {
    local i
    for i in $(seq 1 30); do
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript 'print(1)' \
            >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

# Audio visualizer: the widget package plus the relay service that serves cava's
# bands over local HTTP. A service rather than a process started by the widget: it
# has to survive a shell restart and die with the session, not linger as an orphan.
spectrum_install() {
    echo "== Спектр"
    if ! command -v cava >/dev/null; then
        red "  ✗ нет cava — поставь: sudo pacman -S cava"; return 1
    fi
    # The renderer and the data side are shared with the standalone window host, so they
    # live in spectrum/shared/ and are copied into the package here. Keeping two edited
    # copies of the same QML is how they drift apart.
    cp "$SPECTRUM_SRC/shared/Ring.qml" "$SPECTRUM_SRC/shared/Spectrum.qml" \
        "$SPECTRUM_SRC/package/contents/ui/" || { red "  ✗ общие файлы не скопировались"; return 1; }

    local mode=--install
    [ -d "$SPECTRUM_DEST" ] && mode=--upgrade
    if kpackagetool6 --type Plasma/Applet $mode "$SPECTRUM_SRC/package" >/dev/null 2>&1; then
        grn "  ✓ $SPECTRUM_ID ($mode)"
    else
        red "  ✗ пакет виджета не установился"; return 1
    fi

    mkdir -p "$RELAY_DEST" "$UNIT_DEST"
    install -m 755 "$SPECTRUM_SRC/relay.py" "$RELAY_DEST/relay.py" && echo "  → $RELAY_DEST/relay.py"
    install -m 644 "$SPECTRUM_SRC/plainspectrum-relay.service" "$UNIT_DEST/" \
        && echo "  → $UNIT_DEST/plainspectrum-relay.service"

    systemctl --user daemon-reload
    # Idempotent: enable --now both starts it and adds it to the session; restart
    # afterwards picks up a relay.py that changed while the service was running.
    systemctl --user enable --now plainspectrum-relay.service >/dev/null 2>&1
    systemctl --user restart plainspectrum-relay.service
    sleep 2
    if systemctl --user --quiet is-active plainspectrum-relay.service; then
        grn "  ✓ служба реле работает"
    else
        red "  ✗ служба реле не поднялась — journalctl --user -u plainspectrum-relay"; return 1
    fi

    # ⚠️ Same reason as for the text widget: plasmashell caches a package's QML, so
    # without a restart the edit silently does not arrive.
    if systemctl --user --quiet is-active plasma-plasmashell.service; then
        systemctl --user restart plasma-plasmashell.service && grn "  ✓ plasmashell перезапущен"
    else
        dim "  plasmashell не под systemd — перезапусти оболочку сам"
    fi

    # Two hosts draw the same ring, so only one belongs on the desktop. If the
    # click-through window is set up, the plasmoid variant is installed but not placed.
    if [ -f "$HOME/.config/autostart/plainspectrum-window.desktop" ]; then
        dim "  окно со сквозными кликами настроено — плазмоид на стол не сажаю"
        return 0
    fi

    local n
    n=$(grep -c "^plugin=$SPECTRUM_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then
        dim "  уже на рабочем столе — место не трогаю"
        return 0
    fi
    plasmashell_ready || { red "  ✗ plasmashell не отвечает — добавь виджет вручную"; return 1; }
    local id
    id=$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "print(desktops()[0].addWidget(\"$SPECTRUM_ID\").id)" 2>/dev/null | tr -dc '0-9')
    [ -n "$id" ] && grn "  ✓ добавлен на рабочий стол (id=$id)" || red "  ✗ не удалось добавить на рабочий стол"
}

# Standalone (click-through) host for the visualizer. A plasmoid never hands over the
# left mouse button; a plain window with Qt.WindowTransparentForInput does — see
# docs/GOTCHAS.md. Place, size and keep-below come from a KWin rule, because under
# Wayland a window cannot position itself.
spectrum_window() {
    echo "== Спектр: окно со сквозными кликами"
    if ! command -v qml6 >/dev/null; then
        red "  ✗ нет qml6 (пакет qt6-declarative)"; return 1
    fi
    python3 "$SPECTRUM_SRC/window/setup.py" install
}

spectrum_settings() {
    python3 "$SPECTRUM_SRC/window/setup.py" settings
}

spectrum_window_status() {
    echo "== Спектр: окно"
    python3 "$SPECTRUM_SRC/window/setup.py" status
}

spectrum_status() {
    echo "== Спектр"
    if [ ! -d "$SPECTRUM_DEST" ]; then dim "  виджет не установлен"; return 0; fi
    local diff=0 f rel
    while IFS= read -r f; do
        rel=${f#"$SPECTRUM_SRC/package"/}
        cmp -s "$f" "$SPECTRUM_DEST/$rel" || { red "  ≠ $rel — РАЗОШЁЛСЯ с репо"; diff=1; }
    done < <(find "$SPECTRUM_SRC/package" -type f)
    [ $diff -eq 0 ] && grn "  ✓ виджет установлен, файлы совпадают с репо"

    if systemctl --user --quiet is-active plainspectrum-relay.service; then
        local port
        port=$(grep -oE "PLAINSPECTRUM_PORT=[0-9]+" "$UNIT_DEST/plainspectrum-relay.service" 2>/dev/null | tail -1 | cut -d= -f2)
        port=${port:-8788}
        # ⚠️ Checking that the service is "active" is not enough: what matters is that
        # the port actually returns numbers, so read it instead of trusting systemd.
        if curl -s --max-time 2 "http://127.0.0.1:$port/bands?bars=8" | grep -qE "^[0-9]+(,[0-9]+)*$"; then
            grn "  ✓ реле отвечает на порту $port"
        else
            red "  ≠ служба работает, но порт $port не отдаёт данные"
        fi
    else
        dim "  служба реле не запущена — ./install.sh --spectrum"
    fi

    local n
    n=$(grep -c "^plugin=$SPECTRUM_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then grn "  ✓ добавлен на рабочий стол ($n шт.)"
    else dim "  на рабочий стол не добавлен"; fi
}

# Click-through for both widgets at once. This is the way back: with clicks passing
# through, the widget cannot be grabbed with the mouse, so its own settings dialog is
# out of reach — the switch has to work without it.
clicks_set() {
    local value=$1 human=$2
    echo "== Клики"
    plasmashell_ready || { red "  ✗ plasmashell не отвечает"; return 1; }
    local out
    out=$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
var d = desktops()[0];
var n = 0;
for (var i = 0; i < d.widgetIds.length; i++) {
    var w = d.widgetById(d.widgetIds[i]);
    if (w.type == \"$PLASMOID_ID\" || w.type == \"$SPECTRUM_ID\") {
        w.currentConfigGroup = [\"General\"];
        w.writeConfig(\"clickThrough\", $value);
        w.reloadConfig();
        n++;
    }
}
print(n);" 2>/dev/null | tr -dc '0-9')
    if [ -n "$out" ] && [ "$out" -gt 0 ]; then
        grn "  ✓ $human — виджетов затронуто: $out"
    else
        red "  ✗ виджеты на рабочем столе не найдены"; return 1
    fi
}

# Idempotent: if the widget is already on the desktop, do nothing; otherwise place it.
plasmoid_place() {
    local n
    n=$(grep -c "^plugin=$PLASMOID_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then dim "  уже на рабочем столе — место не трогаю"; return 0; fi
    plasmashell_ready || { red "  ✗ plasmashell не отвечает — добавь виджет вручную"; return 1; }
    # ⚠️ Coordinates in addWidget are useless: position and size come from the Layout.*
    # hints inside the widget, and the container resets the position to the corner
    # anyway. The widget draws the gap from the screen edge itself (its left/top
    # offset settings).
    # Two hosts draw the same monitor, so only one belongs on the desktop.
    if [ -f "$HOME/.config/autostart/plaintop-window.desktop" ]; then
        dim "  окно со сквозными кликами настроено — плазмоид на стол не сажаю"
        return 0
    fi

    local id
    id=$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "print(desktops()[0].addWidget(\"$PLASMOID_ID\").id)" 2>/dev/null | tr -dc '0-9')
    if [ -z "$id" ]; then red "  ✗ не удалось добавить на рабочий стол"; return 1; fi
    grn "  ✓ добавлен на рабочий стол (id=$id)"
}

# Standalone (click-through) host for the text monitor, same reasoning as the ring:
# a plasmoid never hands over the left mouse button. Settings come from the plasmoid's own
# dialog through `--plaintop-export`, so there is still one editor.
plaintop_window() {
    echo "== Монитор: окно со сквозными кликами"
    if ! command -v qml6 >/dev/null; then
        red "  ✗ нет qml6 (пакет qt6-declarative)"; return 1
    fi
    python3 "$REPO/plaintop/window/setup.py" install
}

plaintop_export() {
    echo "== Монитор: настройки из плазмоида в окно"
    python3 "$REPO/plaintop/window/setup.py" export
}

plaintop_window_status() {
    echo "== Монитор: окно"
    python3 "$REPO/plaintop/window/setup.py" status
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
    # Presence on the desktop is read from the session config, not guessed.
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
            # Compare against the @HOME@-substituted text, or the check lies on every file.
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
    echo; plaintop_window_status
    echo; spectrum_status
    echo; spectrum_window_status
}

deps() {
    local miss=0
    echo "== Зависимости"
    command -v conky >/dev/null && grn "  ✓ conky $(conky --version 2>/dev/null | head -1 | awk '{print $2}')" || { red "  ✗ conky"; miss=1; }
    python3 -c "import Xlib" 2>/dev/null && grn "  ✓ python-xlib" || { red "  ✗ python-xlib (нужен для click-through)"; miss=1; }
    command -v sensors >/dev/null && grn "  ✓ lm_sensors" || { red "  ✗ lm_sensors (температуры и обороты)"; miss=1; }
    # ⚠️ No pipeline here, on purpose: under set -o pipefail the `fc-list | grep -q`
    # combination lies. grep -q exits on the first match, fc-list takes SIGPIPE, the
    # pipeline returns an error — and the check reports "not found" although the font
    # is installed.
    local fam; fam=$(fc-match -f '%{family}' 'JetBrainsMono Nerd Font Mono' 2>/dev/null)
    case "$fam" in
        *"JetBrainsMono Nerd Font Mono"*) grn "  ✓ шрифт JetBrainsMono Nerd Font Mono" ;;
        *) red "  ✗ шрифт JetBrainsMono Nerd Font Mono (ttf-jetbrains-mono-nerd)"; miss=1 ;;
    esac
    return $miss
}

# Deploy the conky files without starting it: conky may be switched off on purpose
# while the files in the repository have already moved on.
conky_deploy() {
    echo; echo "== Раскладываю"
    mkdir -p "$DEST" "$AUTOSTART" "$APPS"
    # ⚠️ Deploying files must not flip conky on. Copying the autostart entry overwrites
    # the Hidden=true put there by --conky-off, so remember it and put it back.
    local was_hidden=0
    grep -q "^Hidden=true$" "$AUTOSTART/conky-plainext.desktop" 2>/dev/null && was_hidden=1
    for f in plainext.conf plainext.lua services.sh start.sh clickthrough.py; do
        # ⚠️ @HOME@ is substituted here: conky itself does not expand environment variables
        # in the config, and hardcoding /home/<someone> into the repo is not an option.
        sed "s|@HOME@|$HOME|g" "$REPO/conky/$f" > "$DEST/$f" && echo "  → $DEST/$f"
    done
    chmod +x "$DEST"/*.sh "$DEST"/*.py
    cp "$REPO/conky/conky-plainext.desktop" "$AUTOSTART/" && echo "  → $AUTOSTART/conky-plainext.desktop"
    # A mask over /usr/share/applications/conky.desktop: otherwise KWin starts the packaged
    # conky with its default config. The user directory comes first in XDG_DATA_DIRS.
    cp "$REPO/conky/conky-mask.desktop" "$APPS/conky.desktop" && echo "  → $APPS/conky.desktop (заглушка)"

    # excludeApps must match own_window_class, or the exclusion silently does nothing.
    if command -v kwriteconfig6 >/dev/null; then
        kwriteconfig6 --file ksmserverrc --group General --key excludeApps 'conky,conky-plainext'
        echo "  → ksmserverrc: excludeApps=conky,conky-plainext"
    fi
    [ "$was_hidden" = 1 ] && printf 'Hidden=true\n' >> "$AUTOSTART/conky-plainext.desktop"
}

case "${1:-}" in
  --status)      status; exit 0 ;;
  --check-input) input_shape; exit 0 ;;
  --deps)        deps; exit $? ;;
  --plasmoid)    plasmoid_install; exit $? ;;
  --conky-files) conky_deploy; echo; status; exit 0 ;;
  --spectrum)    spectrum_install; exit $? ;;
  --spectrum-window)   spectrum_window; exit $? ;;
  --spectrum-settings) spectrum_settings; exit $? ;;
  --plaintop-window)   plaintop_window; exit $? ;;
  --plaintop-export)   plaintop_export; exit $? ;;
  --clicks-off)  clicks_set false "клики ловятся виджетами (можно настраивать мышью)"; exit $? ;;
  --clicks-on)   clicks_set true "клики проходят на рабочий стол"; exit $? ;;
  --conky-off)   conky_off; exit 0 ;;
  --conky-on)    conky_on; exit 0 ;;
  -h|--help)     echo "Использование: $0 [--status|--plasmoid|--plaintop-window|--plaintop-export|--spectrum|--spectrum-window|--spectrum-settings|--clicks-on|--clicks-off|--conky-files|--conky-off|--conky-on|--check-input|--deps]"; exit 0 ;;
esac

deps || { echo; red "Не хватает зависимостей — поставь их и повтори."; exit 1; }

conky_deploy

# A full install means "deploy and run", so the autostart entry is enabled here —
# unlike a plain deploy, which keeps whatever state it found.
sed -i '/^Hidden=true$/d' "$AUTOSTART/conky-plainext.desktop"

echo; echo "== Запускаю"
"$DEST/start.sh" >/dev/null 2>&1 &
sleep 8
echo; status
