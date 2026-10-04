#!/usr/bin/env bash
# Install the five widgets, check them, pack them, release them.
#
# Source of truth: the monitor/, spectrum/, player/, weather/ and calendar/ directories of
# this repo. Files flow from here into ~/.local/share/plasma/plasmoids and the relay's
# place, never the other way around: edit in the repo, then run ./install.sh --<widget>.
# Each switch does one thing and is idempotent; the bare call prints them.
set -uo pipefail
cd "$(dirname "$0")"
REPO=$PWD
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
CALENDAR_ID="org.s1dd1.plaincalendar"
CALENDAR_SRC="$REPO/calendar/package"
CALENDAR_DEST="$HOME/.local/share/plasma/plasmoids/$CALENDAR_ID"
RELAY_DEST="$HOME/.local/share/plainspectrum"
UNIT_DEST="$HOME/.config/systemd/user"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
dim()  { printf '\033[2m%s\033[0m\n' "$*"; }



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
    # The player's view too: the visualizer can draw it in the centre of the ring, and the
    # one source is player/shared/. Its strings translate through this package's catalog,
    # so extract.py lists player/shared under both domains.
    cp "$REPO/player/shared/PlayerView.qml" "$SPECTRUM_SRC/package/contents/ui/" \
        || { red "  ✗ player/shared/PlayerView.qml was not copied"; return 1; }
    # Catalogs, as for the monitor: contents/locale for the plasmoid (decision 7).
    python3 "$REPO/po/build.py" plasma_applet_org.s1dd1.plainspectrum "$SPECTRUM_SRC/package/contents/locale" || return 1
}

player_prepare() {
    # The view lives in player/shared/ — the visualizer draws the same file in the centre
    # of its ring — and is copied in here, as the monitor's shared QML is. Then the
    # catalogs, as for the other widgets (decision 7).
    cp "$REPO/player/shared/"*.qml "$PLAYER_SRC/contents/ui/" || { red "  ✗ shared files were not copied"; return 1; }
    python3 "$REPO/po/build.py" plasma_applet_org.s1dd1.plainplayer "$PLAYER_SRC/contents/locale" || return 1
}

weather_prepare() {
    # As for the player: no shared QML, only the catalogs (decision 7).
    python3 "$REPO/po/build.py" plasma_applet_org.s1dd1.plainweather "$WEATHER_SRC/contents/locale" || return 1
}

calendar_prepare() {
    # As for the weather: no shared QML, only the catalogs (decision 7).
    python3 "$REPO/po/build.py" plasma_applet_org.s1dd1.plaincalendar "$CALENDAR_SRC/contents/locale" || return 1
    # Bytecode from importing notes.py by hand would ride along into the package.
    rm -rf "$CALENDAR_SRC/contents/code/__pycache__"
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
    calendar_prepare || return 1
    mkdir -p "$REPO/dist"
    # What this run built: dist/ keeps the older versions too, and a release takes only these.
    PACKED=()
    local src name out root
    for src in "$PLASMOID_SRC" "$SPECTRUM_SRC/package" "$PLAYER_SRC" "$WEATHER_SRC" "$CALENDAR_SRC"; do
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
            PACKED+=("$out")
        else
            red "  ✗ dist/$name.plasmoid built, but kpackagetool6 does not install it"; rm -rf "$root"; return 1
        fi
        rm -rf "$root"
    done
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

    # The window hosts are gone (decision 9; their code left the tree 2026-10-05, branch
    # archive/2026-10-05-conky-window-hosts): an autostart entry of one would still start
    # a second ring. Say so, do not act.
    [ -f "$HOME/.config/autostart/plainspectrum-window.desktop" ] \
        && red "  ⚠ ~/.config/autostart/plainspectrum-window.desktop remains from the retired window host — delete it"

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
    # The player's view is a copy as well, from the player's own shared directory.
    cmp -s "$REPO/player/shared/PlayerView.qml" "$SPECTRUM_DEST/contents/ui/PlayerView.qml" \
        || { red "  ≠ player/shared/PlayerView.qml — DIFFERS from the repo"; diff=1; }
    [ $diff -eq 0 ] && grn "  ✓ widget installed, files match the repo"

    # The relay runs from its own copy; a port that answers says nothing about which code.
    local relay_diff=0 pair
    for pair in "$SPECTRUM_SRC/relay.py:$RELAY_DEST/relay.py" \
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
    # Same trap as the monitor: the view is copied in from player/shared/ at install time,
    # so the loop above would compare with that old copy. Compare with the source.
    for f in "$REPO/player/shared/"*.qml; do
        cmp -s "$f" "$PLAYER_DEST/contents/ui/$(basename "$f")" \
            || { red "  ≠ shared/$(basename "$f") — DIFFERS from the repo"; diff=1; }
    done
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

# The calendar: a package and nothing else — the grid comes from the locale and the clock,
# so there is nothing to fetch and no service. Placed on the desktop like the weather,
# unless it already is there.
calendar_install() {
    echo "== Calendar"
    if ! command -v kpackagetool6 >/dev/null; then
        red "  ✗ kpackagetool6 not found — cannot install the widget"; return 1
    fi
    calendar_prepare || return 1
    local mode=--install
    [ -d "$CALENDAR_DEST" ] && mode=--upgrade
    if kpackagetool6 --type Plasma/Applet $mode "$CALENDAR_SRC" >/dev/null 2>&1; then
        grn "  ✓ $CALENDAR_ID ($mode)"
    else
        red "  ✗ $CALENDAR_ID — $mode failed"; return 1
    fi
    # ⚠️ Same reason as for the other four: plasmashell caches a package's QML, so
    # without a restart the edit silently does not arrive.
    if systemctl --user --quiet is-active plasma-plasmashell.service; then
        systemctl --user restart plasma-plasmashell.service && grn "  ✓ plasmashell restarted"
    else
        dim "  plasmashell is not under systemd — restart the shell yourself"
    fi
    local n
    n=$(grep -c "^plugin=$CALENDAR_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then
        dim "  already on the desktop — leaving its place alone"
        return 0
    fi
    plasmashell_ready || { red "  ✗ plasmashell does not respond — add the widget by hand"; return 1; }
    local id
    id=$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "print(desktops()[0].addWidget(\"$CALENDAR_ID\").id)" 2>/dev/null | tr -dc '0-9')
    [ -n "$id" ] && grn "  ✓ added to the desktop (id=$id)" || red "  ✗ could not add it to the desktop"
}

calendar_status() {
    echo "== Calendar"
    if [ ! -d "$CALENDAR_DEST" ]; then dim "  widget not installed"; return 0; fi
    local diff=0 f rel
    while IFS= read -r f; do
        rel=${f#"$CALENDAR_SRC"/}
        cmp -s "$f" "$CALENDAR_DEST/$rel" || { red "  ≠ $rel — DIFFERS from the repo"; diff=1; }
    done < <(find "$CALENDAR_SRC" -type f)
    [ $diff -eq 0 ] && grn "  ✓ widget installed, files match the repo"
    local n
    n=$(grep -c "^plugin=$CALENDAR_ID$" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)
    if [ "${n:-0}" -gt 0 ]; then grn "  ✓ added to the desktop (instances: $n)"
    else dim "  not added to the desktop"; fi
}

# Click-through for every plaintop widget on the desktop at once. This is the way back:
# with clicks passing through, the widget cannot be grabbed with the mouse, so its own
# settings dialog is out of reach — the switch has to work without it.
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
    if (w.type == \"$PLASMOID_ID\" || w.type == \"$SPECTRUM_ID\" || w.type == \"$PLAYER_ID\"
            || w.type == \"$WEATHER_ID\" || w.type == \"$CALENDAR_ID\") {
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

# Palettes: palettes/<name>.json holds the colour keys of all five widgets, "stock" is
# their main.xml defaults. The keys are checked against main.xml before anything is written.
palette() {
    local command=$1 name=$2
    echo "== Palette"
    [ -n "$name" ] || { python3 "$REPO/palettes/palette.py" list; return 1; }
    plasmashell_ready || { red "  ✗ plasmashell does not respond"; return 1; }
    python3 "$REPO/palettes/palette.py" "$command" "$name"
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

# The monitor's line-builder stand: MonitorData with the machine's sensors replaced by
# values pushed in by hand, every block type's lines read back. Same runner and the same
# traps as the click-through stand above.
check_monitor() {
    echo "== Monitor line stand"
    local runner=/usr/lib/qt6/bin/qmltestrunner
    if [ ! -x "$runner" ]; then
        red "  ✗ $runner is missing (package qt6-declarative)"; return 1
    fi
    local out rc
    out=$(QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen "$runner" -input "$REPO/tests/monitor.qml" 2>&1); rc=$?
    printf '%s\n' "$out" | grep -vE 'detached root|GC memory statistics|unloaded library|propertyCache' | sed 's/^/  /'
    if [ $rc -eq 0 ]; then
        grn "  ✓ the lines come out as the blocks say"
    else
        red "  ✗ the stand failed (exit $rc)"
    fi
    return $rc
}

# The calendar's notes script: its iCalendar parser, recurrence rules, the local vdir and
# the CalDAV client against a fake server, all in Python — no Qt needed.
check_notes() {
    echo "== Calendar notes stand"
    if python3 "$REPO/tests/notes.py"; then
        grn "  ✓ notes.py does what the stand says"
    else
        red "  ✗ the stand failed"; return 1
    fi
}

# The relay's pure functions: the stereo fold, the resampling, cava's configuration. Python
# only, no cava, no Qt.
check_relay() {
    echo "== Relay stand"
    if python3 "$REPO/tests/relay.py"; then
        grn "  ✓ relay.py folds, resamples and configures as the stand says"
    else
        red "  ✗ the stand failed"; return 1
    fi
}

# The weather sources: the four APIs' answers into the one shape the view draws. Plain
# JavaScript under QtTest; nothing of Plasma is imported.
check_weather() {
    echo "== Weather sources stand"
    local runner=/usr/lib/qt6/bin/qmltestrunner
    if [ ! -x "$runner" ]; then
        red "  ✗ $runner is missing (package qt6-declarative)"; return 1
    fi
    local out rc
    out=$(QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen "$runner" -input "$REPO/tests/weather.qml" 2>&1); rc=$?
    printf '%s\n' "$out" | grep -vE 'detached root|GC memory statistics|unloaded library|propertyCache' | sed 's/^/  /'
    if [ $rc -eq 0 ]; then
        grn "  ✓ every source parses and builds as the stand says"
    else
        red "  ✗ the stand failed (exit $rc)"
    fi
    return $rc
}

# A GitHub release: the five packages as --pack builds them, their checksums, an annotated
# tag pushed, the release created with gh. Wants a clean, pushed main and gh signed in. The
# KDE Store upload stays a browser job — docs/STORE.md has the fields.
release() {
    local version=${1:-}
    [ -n "$version" ] || { red "  ✗ usage: $0 --release VERSION   (e.g. 0.5 → tag v0.5)"; return 1; }
    echo "== Release v$version"
    command -v gh >/dev/null || { red "  ✗ gh (the GitHub CLI) is missing"; return 1; }
    gh auth status >/dev/null 2>&1 || { red "  ✗ gh is not signed in — run: gh auth login"; return 1; }
    [ -z "$(git status --porcelain)" ] || { red "  ✗ the working tree is not clean — commit first"; return 1; }
    [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { red "  ✗ not on main"; return 1; }
    git rev-parse -q --verify "refs/tags/v$version" >/dev/null && { red "  ✗ the tag v$version exists"; return 1; }
    git fetch -q origin main || { red "  ✗ cannot reach origin"; return 1; }
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { red "  ✗ main is not pushed, or behind origin — push first"; return 1; }
    pack || return 1
    (cd "$REPO/dist" && sha256sum "${PACKED[@]##*/}" > SHA256SUMS) || { red "  ✗ no checksums"; return 1; }
    local notes="$REPO/dist/RELEASE-v$version.md" f
    {
        echo "plaintop v$version — the five widgets as .plasmoid packages, the same files that go to the KDE Store."
        echo
        echo "| Package | sha256 |"
        echo "|---|---|"
        for f in "${PACKED[@]}"; do
            printf '| %s | `%s` |\n' "$(basename "$f")" "$(sha256sum "$f" | cut -c1-64)"
        done
        echo
        echo 'Install one with `kpackagetool6 --type Plasma/Applet --install NAME.plasmoid`, or through *Get New Widgets*.'
        echo 'What changed — docs/STORE.md (per widget) and docs/JOURNAL.md.'
    } > "$notes"
    git tag -a "v$version" -m "plaintop v$version" || return 1
    git push -q origin "v$version" || { red "  ✗ the tag did not push"; return 1; }
    gh release create "v$version" "${PACKED[@]}" "$REPO/dist/SHA256SUMS" \
        --title "plaintop v$version" --notes-file "$notes" || { red "  ✗ gh release create failed — the tag is pushed, create the release by hand"; return 1; }
    grn "  ✓ released v$version: $(gh release view "v$version" --json url -q .url 2>/dev/null)"
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
    # The window hosts are gone (decision 9; code removed 2026-10-05): an autostart entry
    # of one would still start a second monitor. Say so, do not act.
    [ -f "$HOME/.config/autostart/plaintop-window.desktop" ] \
        && red "  ⚠ ~/.config/autostart/plaintop-window.desktop remains from the retired window host — delete it"

    local id
    id=$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "print(desktops()[0].addWidget(\"$PLASMOID_ID\").id)" 2>/dev/null | tr -dc '0-9')
    if [ -z "$id" ]; then red "  ✗ could not add it to the desktop"; return 1; fi
    grn "  ✓ added to the desktop (id=$id)"
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
    plasmoid_status
    echo; spectrum_status
    echo; player_status
    echo; weather_status
    echo; calendar_status
}

deps() {
    local miss=0
    echo "== Dependencies"
    command -v kpackagetool6 >/dev/null && grn "  ✓ kpackagetool6" || { red "  ✗ kpackagetool6 (plasma-workspace)"; miss=1; }
    command -v msgfmt >/dev/null && grn "  ✓ msgfmt" || { red "  ✗ msgfmt (gettext, for the translations)"; miss=1; }
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

usage() {
    cat <<EOF
Usage: $0 SWITCH

  --plasmoid | --spectrum | --player | --weather | --calendar   install one widget (and restart the shell)
  --status                       what is installed, what runs, what differs from the repo
  --deps                         the tools the widgets need
  --pack                         .plasmoid files into dist/, each test-installed
  --release VERSION              tag vVERSION, push it, GitHub release with the packages and checksums
  --clicks-on | --clicks-off     clicks through to the desktop, or the widgets take them
  --palette NAME | --palette-save NAME   colours of the five widgets at once (palettes/)
  --check-passthrough | --check-monitor | --check-notes | --check-relay | --check-weather   the stands

One switch per call; installing several widgets means several calls — each restarts
plasmashell, and systemd rate-limits restarts (docs/GOTCHAS.md).
EOF
}

case "${1:-}" in
  --status)      status; exit 0 ;;
  --check-passthrough) check_passthrough; exit $? ;;
  --check-monitor) check_monitor; exit $? ;;
  --check-notes) check_notes; exit $? ;;
  --check-relay) check_relay; exit $? ;;
  --check-weather) check_weather; exit $? ;;
  --deps)        deps; exit $? ;;
  --plasmoid)    plasmoid_install; exit $? ;;
  --pack)        pack; exit $? ;;
  --release)     release "${2:-}"; exit $? ;;
  --spectrum)    spectrum_install; exit $? ;;
  --player)      player_install; exit $? ;;
  --weather)     weather_install; exit $? ;;
  --calendar)    calendar_install; exit $? ;;
  --clicks-off)  clicks_set false "widgets catch clicks (can be configured with the mouse)"; exit $? ;;
  --clicks-on)   clicks_set true "clicks pass through to the desktop"; exit $? ;;
  --palette)      palette apply "${2:-}"; exit $? ;;
  --palette-save) palette save "${2:-}"; exit $? ;;
  -h|--help|"")  usage; exit 0 ;;
  *)             red "unknown switch: $1"; usage; exit 1 ;;
esac
