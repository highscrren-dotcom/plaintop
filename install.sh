#!/usr/bin/env bash
# Deploy plaintop into the system and start it.
#
# Source of truth: the conky/, monitor/, spectrum/, player/ and weather/ directories of
# this repo. Files flow from here into ~/.config/conky, ~/.local/share/plasma/plasmoids
# and the rest, never the other way around: edit in the repo, then run ./install.sh.
set -uo pipefail
cd "$(dirname "$0")"
REPO=$PWD
DEST="$HOME/.config/conky"
AUTOSTART="$HOME/.config/autostart"
APPS="$HOME/.local/share/applications"
PLASMOID_ID="org.s1dd1.plaintop"
PLASMOID_SRC="$REPO/monitor/package"
PLASMOID_DEST="$HOME/.local/share/plasma/plasmoids/$PLASMOID_ID"
SPECTRUM_ID="org.s1dd1.plainspectrum"
SPECTRUM_SRC="$REPO/spectrum"
SPECTRUM_DEST="$HOME/.local/share/plasma/plasmoids/$SPECTRUM_ID"
PLAYER_ID="org.s1dd1.plainplayer"
PLAYER_SRC="$REPO/player/package"
PLAYER_DEST="$HOME/.local/share/plasma/plasmoids/$PLAYER_ID"
WEATHER_ID="org.s1dd1.plainweather"
WEATHER_SRC="$REPO/weather/package"
WEATHER_DEST="$HOME/.local/share/plasma/plasmoids/$WEATHER_ID"
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
    print("  python-xlib is not installed — cannot check the input region"); sys.exit(0)
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
    print("  no conky windows"); sys.exit(0)
for w, cls in ws:
    g = w.get_geometry()
    n = len(list(w.shape_get_rectangles(shape.SK.Input).rectangles))
    verdict = "clicks pass through" if n == 0 else "CATCHES CLICKS"
    print(f"  {hex(w.id)}  class={cls[0]}  {g.width}x{g.height}  input={n} → {verdict}")
PY
}

# Make the monitor package complete: install and pack both start here, so what gets
# installed and what gets published cannot differ.
monitor_prepare() {
    # The renderer and the data side live in monitor/shared/ (once shared with the window
    # host, retired by decision 9) and are copied into the package here: one source, one copy.
    cp "$REPO/monitor/shared/"*.qml "$PLASMOID_SRC/contents/ui/" || { red "  ✗ shared files were not copied"; return 1; }
    # Schema -> package. A bad schema aborts the install: better to refuse here than
    # to get an empty widget and hunt for the cause in QML.
    if ! python3 "$REPO/monitor/generate.py"; then
        red "  ✗ the description in schema/ failed validation — package not updated"; return 1
    fi
    # Catalogs po/*/<domain>.po → contents/locale, where libplasma looks for the applet's
    # translations (decision 7).
    python3 "$REPO/po/build.py" plasma_applet_org.s1dd1.plaintop "$PLASMOID_SRC/contents/locale" || return 1
}

spectrum_prepare() {
    # Same as the monitor: the shared QML lives in spectrum/shared/ and is copied in.
    cp "$SPECTRUM_SRC/shared/Ring.qml" "$SPECTRUM_SRC/shared/Spectrum.qml" \
        "$SPECTRUM_SRC/package/contents/ui/" || { red "  ✗ shared files were not copied"; return 1; }
    # Catalogs, as for the monitor: contents/locale for the plasmoid (decision 7).
    python3 "$REPO/po/build.py" plasma_applet_org.s1dd1.plainspectrum "$SPECTRUM_SRC/package/contents/locale" || return 1
}

player_prepare() {
    # Nothing to copy in: the player has no shared QML and never had a window host. Only
    # the catalogs, as for the other two (decision 7).
    python3 "$REPO/po/build.py" plasma_applet_org.s1dd1.plainplayer "$PLAYER_SRC/contents/locale" || return 1
}

weather_prepare() {
    # As for the player: no shared QML, only the catalogs (decision 7).
    python3 "$REPO/po/build.py" plasma_applet_org.s1dd1.plainweather "$WEATHER_SRC/contents/locale" || return 1
}

# The plasmoid installs idempotently: kpackagetool6 decides by itself whether this is
# an install or an upgrade, and the state is applied either way.
plasmoid_install() {
    echo "== Plasmoid"
    if ! command -v kpackagetool6 >/dev/null; then
        red "  ✗ kpackagetool6 not found — cannot install the plasmoid"; return 1
    fi
    monitor_prepare || return 1
    local mode=--install
    [ -d "$PLASMOID_DEST" ] && mode=--upgrade
    if kpackagetool6 --type Plasma/Applet $mode "$PLASMOID_SRC" >/dev/null 2>&1; then
        grn "  ✓ $PLASMOID_ID ($mode)"
    else
        red "  ✗ $PLASMOID_ID — $mode failed"; return 1
    fi
    # ⚠️ Verified 2026-09-20: plasmashell caches the package QML. Reinstalling is not
    # enough, and neither is re-creating the applet — the new layout shows up only
    # after the shell restarts. So we drive the state to completion here instead of
    # leaving it to the user.
    if systemctl --user --quiet is-active plasma-plasmashell.service; then
        systemctl --user restart plasma-plasmashell.service && grn "  ✓ plasmashell restarted — the widget runs the new QML"
    else
        dim "  plasmashell is not under systemd — restart the shell yourself, or the old QML stays"
    fi
    plasmoid_place
}

# A .plasmoid per widget, for the KDE Store or a GitHub release: the package exactly as
# the install lays it out, zipped with metadata.json at the root — the layout
# kpackagetool6 and "Get New Widgets" expect. Python's zipfile does the packing, since
# zip itself is not always installed. Each archive is then installed into a throwaway
# package root: a file that does not install must not reach the store.
pack() {
    echo "== Building .plasmoid → dist/"
    command -v kpackagetool6 >/dev/null || { red "  ✗ kpackagetool6 not found — cannot check the archives"; return 1; }
    monitor_prepare || return 1
    spectrum_prepare || return 1
    player_prepare || return 1
    weather_prepare || return 1
    mkdir -p "$REPO/dist"
    local src name out root
    for src in "$PLASMOID_SRC" "$SPECTRUM_SRC/package" "$PLAYER_SRC" "$WEATHER_SRC"; do
        name=$(python3 -c 'import json, sys
k = json.load(open(sys.argv[1]))["KPlugin"]
print(k["Name"] + "-" + k["Version"])' "$src/metadata.json") \
            || { red "  ✗ $src/metadata.json cannot be read"; return 1; }
        out="$REPO/dist/$name.plasmoid"
        rm -f "$out"
        (cd "$src" && python3 -m zipfile -c "$out" metadata.json contents) \
            || { red "  ✗ $out failed to build"; return 1; }
        root=$(mktemp -d)
        if kpackagetool6 --type Plasma/Applet --install "$out" --packageroot "$root" >/dev/null 2>&1; then
            grn "  ✓ dist/$name.plasmoid — installs"
        else
            red "  ✗ dist/$name.plasmoid built, but kpackagetool6 does not install it"; rm -rf "$root"; return 1
        fi
        rm -rf "$root"
    done
}

# Stop conky while the move to the plasmoid is under way — and bring it back.
# ⚠️ Use `pkill -x conky` only: the pattern `pkill -f 'conky -c'` matches the command
# line of our own shell and kills it.
conky_off() {
    echo "== Stopping conky"
    pkill -x conky && grn "  ✓ process stopped" || dim "  conky was not running"
    if [ -f "$AUTOSTART/conky-plainext.desktop" ]; then
        # Hidden=true is the standard XDG way to disable autostart; the file stays in place.
        grep -q "^Hidden=true$" "$AUTOSTART/conky-plainext.desktop" \
            || printf 'Hidden=true\n' >> "$AUTOSTART/conky-plainext.desktop"
        grn "  ✓ autostart disabled (Hidden=true)"
    else
        dim "  no autostart entry anyway"
    fi
    # excludeApps in ksmserverrc already stops the session from restoring conky at login.
    echo; status
}

conky_on() {
    echo "== Bringing conky back"
    if [ -f "$AUTOSTART/conky-plainext.desktop" ]; then
        sed -i '/^Hidden=true$/d' "$AUTOSTART/conky-plainext.desktop"
        grn "  ✓ autostart enabled"
    else
        cp "$REPO/conky/conky-plainext.desktop" "$AUTOSTART/" && grn "  ✓ autostart restored"
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
    echo "== Spectrum"
    if ! command -v cava >/dev/null; then
        red "  ✗ cava is missing — install it: sudo pacman -S cava"; return 1
    fi
    spectrum_prepare || return 1

    local mode=--install
    [ -d "$SPECTRUM_DEST" ] && mode=--upgrade
    if kpackagetool6 --type Plasma/Applet $mode "$SPECTRUM_SRC/package" >/dev/null 2>&1; then
        grn "  ✓ $SPECTRUM_ID ($mode)"
    else
        red "  ✗ the widget package did not install"; return 1
    fi

    mkdir -p "$RELAY_DEST" "$UNIT_DEST"
    install -m 755 "$SPECTRUM_SRC/relay.py" "$RELAY_DEST/relay.py" && echo "  → $RELAY_DEST/relay.py"
    # The relay reads the defaults next to itself, and it is the only writer of both
    # settings files. Without them a first install comes up with an empty editor. Each
    # file is taken from the widget it belongs to, so there is one copy to edit.
    install -m 644 "$SPECTRUM_SRC/window/ring.default.json" "$RELAY_DEST/ring.default.json" \
        && echo "  → $RELAY_DEST/ring.default.json"
    install -m 644 "$REPO/monitor/window/monitor.default.json" "$RELAY_DEST/monitor.default.json" \
        && echo "  → $RELAY_DEST/monitor.default.json"
    install -m 644 "$SPECTRUM_SRC/plainspectrum-relay.service" "$UNIT_DEST/" \
        && echo "  → $UNIT_DEST/plainspectrum-relay.service"

    systemctl --user daemon-reload
    # Idempotent: enable --now both starts it and adds it to the session; restart
    # afterwards picks up a relay.py that changed while the service was running.
    systemctl --user enable --now plainspectrum-relay.service >/dev/null 2>&1
    systemctl --user restart plainspectrum-relay.service
    sleep 2
    if systemctl --user --quiet is-active plainspectrum-relay.service; then
        grn "  ✓ relay service is running"
    else
        red "  ✗ relay service did not come up — journalctl --user -u plainspectrum-relay"; return 1
    fi

    # ⚠️ Same reason as for the text widget: plasmashell caches a package's QML, so
    # without a restart the edit silently does not arrive.
    if systemctl --user --quiet is-active plasma-plasmashell.service; then
        systemctl --user restart plasma-plasmashell.service && grn "  ✓ plasmashell restarted"
    else
        dim "  plasmashell is not under systemd — restart the shell yourself"
    fi

    # A window host not yet retired (decision 9) would draw the same ring: while its
    # autostart entry exists, the plasmoid is installed but not placed. --windows-off retires it.
    if [ -f "$HOME/.config/autostart/plainspectrum-window.desktop" ]; then
        dim "  click-through window is set up — not placing the plasmoid on the desktop"
        return 0
    fi

    local n
    n=$(grep -c "^plugin=$SPECTRUM_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then
        dim "  already on the desktop — leaving its place alone"
        return 0
    fi
    plasmashell_ready || { red "  ✗ plasmashell does not respond — add the widget by hand"; return 1; }
    local id
    id=$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "print(desktops()[0].addWidget(\"$SPECTRUM_ID\").id)" 2>/dev/null | tr -dc '0-9')
    [ -n "$id" ] && grn "  ✓ added to the desktop (id=$id)" || red "  ✗ could not add it to the desktop"
}

# Standalone (click-through) host for the visualizer — retired (decision 9). It predates the
# plasmoid's own click-through (decision 8): the plasmoid now lets both buttons through by
# itself (see check_passthrough), so a second host with its KWin rule and autostart adds
# nothing. Kept for reference, not to be used; `--windows-off` retires an existing setup.
spectrum_window() {
    echo "== Spectrum: click-through window"
    if ! command -v qml6 >/dev/null; then
        red "  ✗ qml6 is missing (package qt6-declarative)"; return 1
    fi
    python3 "$SPECTRUM_SRC/window/setup.py" install
}

spectrum_settings() {
    python3 "$SPECTRUM_SRC/window/setup.py" settings
}

spectrum_window_status() {
    echo "== Spectrum: window"
    python3 "$SPECTRUM_SRC/window/setup.py" status
}

spectrum_status() {
    echo "== Spectrum"
    if [ ! -d "$SPECTRUM_DEST" ]; then dim "  widget not installed"; return 0; fi
    local diff=0 f rel
    while IFS= read -r f; do
        rel=${f#"$SPECTRUM_SRC/package"/}
        cmp -s "$f" "$SPECTRUM_DEST/$rel" || { red "  ≠ $rel — DIFFERS from the repo"; diff=1; }
    done < <(find "$SPECTRUM_SRC/package" -type f)
    # Same trap as the text widget: shared QML is copied into the package only on install.
    for f in "$SPECTRUM_SRC/shared/"*.qml; do
        cmp -s "$f" "$SPECTRUM_DEST/contents/ui/$(basename "$f")" \
            || { red "  ≠ shared/$(basename "$f") — DIFFERS from the repo"; diff=1; }
    done
    [ $diff -eq 0 ] && grn "  ✓ widget installed, files match the repo"

    # The relay runs from its own copy; a port that answers says nothing about which code.
    local relay_diff=0 pair
    for pair in "$SPECTRUM_SRC/relay.py:$RELAY_DEST/relay.py" \
                "$SPECTRUM_SRC/window/ring.default.json:$RELAY_DEST/ring.default.json" \
                "$REPO/monitor/window/monitor.default.json:$RELAY_DEST/monitor.default.json" \
                "$SPECTRUM_SRC/plainspectrum-relay.service:$UNIT_DEST/plainspectrum-relay.service"; do
        cmp -s "${pair%%:*}" "${pair#*:}" \
            || { red "  ≠ $(basename "${pair#*:}") — relay differs from the repo: ./install.sh --spectrum"; relay_diff=1; }
    done
    [ $relay_diff -eq 0 ] && grn "  ✓ relay deployed, files match the repo"

    if systemctl --user --quiet is-active plainspectrum-relay.service; then
        local port
        port=$(grep -oE "PLAINSPECTRUM_PORT=[0-9]+" "$UNIT_DEST/plainspectrum-relay.service" 2>/dev/null | tail -1 | cut -d= -f2)
        port=${port:-8788}
        # ⚠️ Checking that the service is "active" is not enough: what matters is that
        # the port actually returns numbers, so read it instead of trusting systemd.
        if curl -s --max-time 2 "http://127.0.0.1:$port/bands?bars=8" | grep -qE "^[0-9]+(,[0-9]+)*$"; then
            grn "  ✓ relay answers on port $port"
        else
            red "  ≠ service is running, but port $port returns no data"
        fi
    else
        dim "  relay service is not running — ./install.sh --spectrum"
    fi

    local n
    n=$(grep -c "^plugin=$SPECTRUM_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then grn "  ✓ added to the desktop (instances: $n)"
    else dim "  not added to the desktop"; fi
}

# The player: a package and nothing else — its data is Plasma's own MPRIS module, so
# there is no service to deploy. Placed on the desktop like the visualizer, unless it
# already is there.
player_install() {
    echo "== Player"
    if ! command -v kpackagetool6 >/dev/null; then
        red "  ✗ kpackagetool6 not found — cannot install the widget"; return 1
    fi
    player_prepare || return 1
    local mode=--install
    [ -d "$PLAYER_DEST" ] && mode=--upgrade
    if kpackagetool6 --type Plasma/Applet $mode "$PLAYER_SRC" >/dev/null 2>&1; then
        grn "  ✓ $PLAYER_ID ($mode)"
    else
        red "  ✗ $PLAYER_ID — $mode failed"; return 1
    fi
    # ⚠️ Same reason as for the other two: plasmashell caches a package's QML, so
    # without a restart the edit silently does not arrive.
    if systemctl --user --quiet is-active plasma-plasmashell.service; then
        systemctl --user restart plasma-plasmashell.service && grn "  ✓ plasmashell restarted"
    else
        dim "  plasmashell is not under systemd — restart the shell yourself"
    fi
    local n
    n=$(grep -c "^plugin=$PLAYER_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then
        dim "  already on the desktop — leaving its place alone"
        return 0
    fi
    plasmashell_ready || { red "  ✗ plasmashell does not respond — add the widget by hand"; return 1; }
    local id
    id=$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "print(desktops()[0].addWidget(\"$PLAYER_ID\").id)" 2>/dev/null | tr -dc '0-9')
    [ -n "$id" ] && grn "  ✓ added to the desktop (id=$id)" || red "  ✗ could not add it to the desktop"
}

player_status() {
    echo "== Player"
    if [ ! -d "$PLAYER_DEST" ]; then dim "  widget not installed"; return 0; fi
    local diff=0 f rel
    while IFS= read -r f; do
        rel=${f#"$PLAYER_SRC"/}
        cmp -s "$f" "$PLAYER_DEST/$rel" || { red "  ≠ $rel — DIFFERS from the repo"; diff=1; }
    done < <(find "$PLAYER_SRC" -type f)
    [ $diff -eq 0 ] && grn "  ✓ widget installed, files match the repo"
    local n
    n=$(grep -c "^plugin=$PLAYER_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then grn "  ✓ added to the desktop (instances: $n)"
    else dim "  not added to the desktop"; fi
}

# The weather: a package and nothing else — it asks Open-Meteo itself over https, so there
# is no service to deploy. Placed on the desktop like the player, unless it already is there.
weather_install() {
    echo "== Weather"
    if ! command -v kpackagetool6 >/dev/null; then
        red "  ✗ kpackagetool6 not found — cannot install the widget"; return 1
    fi
    weather_prepare || return 1
    local mode=--install
    [ -d "$WEATHER_DEST" ] && mode=--upgrade
    if kpackagetool6 --type Plasma/Applet $mode "$WEATHER_SRC" >/dev/null 2>&1; then
        grn "  ✓ $WEATHER_ID ($mode)"
    else
        red "  ✗ $WEATHER_ID — $mode failed"; return 1
    fi
    # ⚠️ Same reason as for the other three: plasmashell caches a package's QML, so
    # without a restart the edit silently does not arrive.
    if systemctl --user --quiet is-active plasma-plasmashell.service; then
        systemctl --user restart plasma-plasmashell.service && grn "  ✓ plasmashell restarted"
    else
        dim "  plasmashell is not under systemd — restart the shell yourself"
    fi
    local n
    n=$(grep -c "^plugin=$WEATHER_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then
        dim "  already on the desktop — leaving its place alone"
        return 0
    fi
    plasmashell_ready || { red "  ✗ plasmashell does not respond — add the widget by hand"; return 1; }
    local id
    id=$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "print(desktops()[0].addWidget(\"$WEATHER_ID\").id)" 2>/dev/null | tr -dc '0-9')
    [ -n "$id" ] && grn "  ✓ added to the desktop (id=$id)" || red "  ✗ could not add it to the desktop"
}

weather_status() {
    echo "== Weather"
    if [ ! -d "$WEATHER_DEST" ]; then dim "  widget not installed"; return 0; fi
    local diff=0 f rel
    while IFS= read -r f; do
        rel=${f#"$WEATHER_SRC"/}
        cmp -s "$f" "$WEATHER_DEST/$rel" || { red "  ≠ $rel — DIFFERS from the repo"; diff=1; }
    done < <(find "$WEATHER_SRC" -type f)
    [ $diff -eq 0 ] && grn "  ✓ widget installed, files match the repo"
    local n
    n=$(grep -c "^plugin=$WEATHER_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then grn "  ✓ added to the desktop (instances: $n)"
    else dim "  not added to the desktop"; fi
}

# Click-through for both widgets at once. This is the way back: with clicks passing
# through, the widget cannot be grabbed with the mouse, so its own settings dialog is
# out of reach — the switch has to work without it.
clicks_set() {
    local value=$1 human=$2
    echo "== Clicks"
    plasmashell_ready || { red "  ✗ plasmashell does not respond"; return 1; }
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
        grn "  ✓ $human — widgets affected: $out"
    else
        red "  ✗ no widgets found on the desktop"; return 1
    fi
}

# Left-button click-through on the desktop is not the applet's call: plasmashell wraps every
# desktop applet in an ItemContainer that accepts the left button before the applet sees it
# (the right one passes — the container takes only Qt::LeftButton). The widgets get through
# by disabling that container while clicks pass through, a Binding on root.parent.enabled in
# each main.qml. The right button needs one thing more: the desktop finds the applet for its
# context menu geometrically (ContainmentItem::mousePressEvent asks every PlasmoidItem
# contains(pos) and never looks at enabled), so each main.qml also sets an empty
# containmentMask — by name, through a Binding — and contains() answers "no".
# tests/passthrough.qml proves the container trick and the mask's effect on contains()
# against the compiled containmentlayoutmanager module the running shell uses. The stand
# tests Plasma's behaviour, not ours, so run it after a Plasma or Qt upgrade.
check_passthrough() {
    echo "== Click-through stand"
    local runner=/usr/lib/qt6/bin/qmltestrunner
    # ⚠️ /usr/bin/qmltestrunner is the Qt 5 runner: it cannot read a Qt 6 qmldir.
    if [ ! -x "$runner" ]; then
        red "  ✗ $runner is missing (package qt6-declarative)"; return 1
    fi
    # ⚠️ Qt logs to journald when stderr is not a terminal, so a pipe sees nothing without
    # QT_FORCE_STDERR_LOGGING=1. Capture first, filter after: in a pipeline the runner's
    # exit status gets mixed up with grep's (see the pipefail note in deps).
    local out rc
    out=$(QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen "$runner" -input "$REPO/tests/passthrough.qml" 2>&1); rc=$?
    # Every PASS/FAIL/Totals line is shown; only Qt's own chatter is dropped.
    printf '%s\n' "$out" | grep -vE 'detached root|GC memory statistics|unloaded library|propertyCache' | sed 's/^/  /'
    if [ $rc -eq 0 ]; then
        grn "  ✓ disabled, the container hands both buttons over — the widgets' assumption holds"
    else
        red "  ✗ the stand failed (exit $rc) — Plasma no longer behaves the way the widgets assume"
    fi
    return $rc
}

# Idempotent: if the widget is already on the desktop, do nothing; otherwise place it.
plasmoid_place() {
    local n
    n=$(grep -c "^plugin=$PLASMOID_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then dim "  already on the desktop — leaving its place alone"; return 0; fi
    plasmashell_ready || { red "  ✗ plasmashell does not respond — add the widget by hand"; return 1; }
    # ⚠️ Coordinates in addWidget are useless: position and size come from the Layout.*
    # hints inside the widget, and the container resets the position to the corner
    # anyway. The widget draws the gap from the screen edge itself (its left/top
    # offset settings).
    # A window host not yet retired (decision 9) would draw the same monitor: while its
    # autostart entry exists, the plasmoid is not placed. --windows-off retires it.
    if [ -f "$HOME/.config/autostart/plaintop-window.desktop" ]; then
        dim "  click-through window is set up — not placing the plasmoid on the desktop"
        return 0
    fi

    local id
    id=$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "print(desktops()[0].addWidget(\"$PLASMOID_ID\").id)" 2>/dev/null | tr -dc '0-9')
    if [ -z "$id" ]; then red "  ✗ could not add it to the desktop"; return 1; fi
    grn "  ✓ added to the desktop (id=$id)"
}

# Standalone (click-through) host for the text monitor — retired (decision 9), same story
# as the ring: it predates the plasmoid's own click-through (decision 8; the plasmoid now
# lets both buttons through by itself — see check_passthrough), so it has nothing left to
# add. Kept for reference, not to be used; `--windows-off` retires an existing setup.
plaintop_window() {
    echo "== Monitor: click-through window"
    if ! command -v qml6 >/dev/null; then
        red "  ✗ qml6 is missing (package qt6-declarative)"; return 1
    fi
    python3 "$REPO/monitor/window/setup.py" install
}

# The window hosts are retired (decision 9): the plasmoids let both mouse buttons through by
# themselves, so a second host with its KWin rule and autostart has nothing left to add.
# This stops both windows and takes their pieces out; the settings files stay.
windows_off() {
    echo "== Monitor: window host retired"
    python3 "$REPO/monitor/window/setup.py" retire || return 1
    echo "== Spectrum: window host retired"
    python3 "$SPECTRUM_SRC/window/setup.py" retire || return 1
}

plaintop_export() {
    echo "== Monitor: settings from the plasmoid to the window"
    python3 "$REPO/monitor/window/setup.py" export
}

plaintop_window_status() {
    echo "== Monitor: window"
    python3 "$REPO/monitor/window/setup.py" status
}

plasmoid_status() {
    echo "== Plasmoid"
    if [ ! -d "$PLASMOID_DEST" ]; then red "  ✗ not installed"; return 0; fi
    local diff=0 f rel
    while IFS= read -r f; do
        rel=${f#"$PLASMOID_SRC"/}
        cmp -s "$f" "$PLASMOID_DEST/$rel" || { red "  ≠ $rel — DIFFERS from the repo"; diff=1; }
    done < <(find "$PLASMOID_SRC" -type f)
    # ⚠️ The shared QML reaches the package only as a copy made at install time, so the
    # loop above compares the installed file with that old copy and passes after any edit
    # in monitor/shared/. Compare with the source itself.
    for f in "$REPO/monitor/shared/"*.qml; do
        cmp -s "$f" "$PLASMOID_DEST/contents/ui/$(basename "$f")" \
            || { red "  ≠ shared/$(basename "$f") — DIFFERS from the repo"; diff=1; }
    done
    [ $diff -eq 0 ] && grn "  ✓ installed, files match the repo"
    # Presence on the desktop is read from the session config, not guessed.
    local n; n=$(grep -c "^plugin=$PLASMOID_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then grn "  ✓ added to the desktop (instances: $n)"
    else dim "  not added to the desktop"; fi
}

status() {
    echo "== Processes"
    if pgrep -x conky >/dev/null; then pgrep -ax conky | sed 's/^/  /'; else dim "  conky is not running"; fi
    echo "== Window and input region"; input_shape
    echo "== Deployed"
    for f in plainext.conf plainext.lua services.sh start.sh clickthrough.py; do
        if [ -f "$DEST/$f" ]; then
            # Compare against the @HOME@-substituted text, or the check lies on every file.
            if sed "s|@HOME@|$HOME|g" "$REPO/conky/$f" | cmp -s - "$DEST/$f"; then grn "  ✓ $f — matches the repo"
            else red "  ≠ $f — DIFFERS from the repo"; fi
        else red "  ✗ $f — not deployed"; fi
    done
    if [ -f "$AUTOSTART/conky-plainext.desktop" ]; then
        if grep -q "^Hidden=true$" "$AUTOSTART/conky-plainext.desktop"; then
            dim "  • autostart disabled (Hidden=true) — to re-enable: ./install.sh --conky-on"
        else grn "  ✓ autostart"; fi
    else red "  ✗ autostart not set up"; fi
    [ -f "$APPS/conky.desktop" ] && grn "  ✓ mask over the packaged conky.desktop" || red "  ✗ no mask"
    echo; plasmoid_status
    echo; plaintop_window_status
    echo; spectrum_status
    echo; spectrum_window_status
    echo; player_status
    echo; weather_status
}

deps() {
    local miss=0
    echo "== Dependencies"
    command -v conky >/dev/null && grn "  ✓ conky $(conky --version 2>/dev/null | head -1 | awk '{print $2}')" || { red "  ✗ conky"; miss=1; }
    python3 -c "import Xlib" 2>/dev/null && grn "  ✓ python-xlib" || { red "  ✗ python-xlib (needed for click-through)"; miss=1; }
    command -v sensors >/dev/null && grn "  ✓ lm_sensors" || { red "  ✗ lm_sensors (temperatures and fan speeds)"; miss=1; }
    # ⚠️ No pipeline here, on purpose: under set -o pipefail the `fc-list | grep -q`
    # combination lies. grep -q exits on the first match, fc-list takes SIGPIPE, the
    # pipeline returns an error — and the check reports "not found" although the font
    # is installed.
    local fam; fam=$(fc-match -f '%{family}' 'JetBrainsMono Nerd Font Mono' 2>/dev/null)
    case "$fam" in
        *"JetBrainsMono Nerd Font Mono"*) grn "  ✓ font JetBrainsMono Nerd Font Mono" ;;
        *) red "  ✗ font JetBrainsMono Nerd Font Mono (ttf-jetbrains-mono-nerd)"; miss=1 ;;
    esac
    return $miss
}

# Deploy the conky files without starting it: conky may be switched off on purpose
# while the files in the repository have already moved on.
conky_deploy() {
    echo; echo "== Deploying"
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
    cp "$REPO/conky/conky-mask.desktop" "$APPS/conky.desktop" && echo "  → $APPS/conky.desktop (mask)"

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
  --check-passthrough) check_passthrough; exit $? ;;
  --deps)        deps; exit $? ;;
  --plasmoid)    plasmoid_install; exit $? ;;
  --pack)        pack; exit $? ;;
  --conky-files) conky_deploy; echo; status; exit 0 ;;
  --spectrum)    spectrum_install; exit $? ;;
  --player)      player_install; exit $? ;;
  --weather)     weather_install; exit $? ;;
  --spectrum-window)   spectrum_window; exit $? ;;
  --spectrum-settings) spectrum_settings; exit $? ;;
  --plaintop-window)   plaintop_window; exit $? ;;
  --plaintop-export)   plaintop_export; exit $? ;;
  --plaintop-settings) python3 "$REPO/monitor/window/setup.py" settings; exit $? ;;
  --windows-off) windows_off; exit $? ;;
  --clicks-off)  clicks_set false "widgets catch clicks (can be configured with the mouse)"; exit $? ;;
  --clicks-on)   clicks_set true "clicks pass through to the desktop"; exit $? ;;
  --conky-off)   conky_off; exit 0 ;;
  --conky-on)    conky_on; exit 0 ;;
  -h|--help)     echo "Usage: $0 [--status|--plasmoid|--pack|--plaintop-window|--plaintop-settings|--plaintop-export|--spectrum|--spectrum-window|--spectrum-settings|--player|--weather|--windows-off|--clicks-on|--clicks-off|--conky-files|--conky-off|--conky-on|--check-input|--check-passthrough|--deps]"; exit 0 ;;
esac

deps || { echo; red "Missing dependencies — install them and try again."; exit 1; }

conky_deploy

# A full install means "deploy and run", so the autostart entry is enabled here —
# unlike a plain deploy, which keeps whatever state it found.
sed -i '/^Hidden=true$/d' "$AUTOSTART/conky-plainext.desktop"

echo; echo "== Starting"
"$DEST/start.sh" >/dev/null 2>&1 &
sleep 8
echo; status
