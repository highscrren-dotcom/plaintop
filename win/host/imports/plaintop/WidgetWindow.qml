import QtQuick
import QtQuick.Controls as Controls

// The window every widget host is: frameless, transparent, a tool window kept at the
// bottom of the stack, and transparent for input while the Mouse setting lets clicks
// through — the archived window hosts of 2026-09-21 (decision 5), on Windows this time.
// It also carries the two things the plasmoid got from the shell: the settings (polled
// from the service, which owns them — decision 5 again) and the i18n functions the shared
// QML calls bare (decision 7: a bare qml host has none; here they resolve through the
// context chain to this root and go to Qt's translator — I18n.js).
//
// With the mouse not passing through, a left drag moves the window and the right button
// opens a small menu: the settings, the mouse switch, the icons switch, close. That is the
// shell's edit mode of the plasmoid, as far as a bare window has one.
Window {
    id: win

    property string widget: ""
    // The settings, as /settings/<widget> gives them: every key of the plasmoid's main.xml.
    property var cfg: ({})
    property int cfgStamp: -1
    readonly property bool ready: cfgStamp >= 0
    readonly property bool passing: cfg.clickThrough === true

    visible: ready
    color: "transparent"
    title: "plaintop " + widget
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint | Qt.NoDropShadowWindowHint
           | (passing ? Qt.WindowTransparentForInput : 0)

    // ── i18n ──────────────────────────────────────────────────────────────────
    function i18n(text) { return I18n.i18n.apply(null, arguments) }
    function i18nc(context, text) { return I18n.i18nc.apply(null, arguments) }
    function i18np(singular, plural, n) { return I18n.i18np.apply(null, arguments) }
    function i18ncp(context, singular, plural, n) { return I18n.i18ncp.apply(null, arguments) }

    // ── settings ──────────────────────────────────────────────────────────────
    function num(key, fallback) {
        const v = cfg[key]
        return (v === undefined || v === null) ? fallback : v
    }
    function str(key, fallback) {
        const v = cfg[key]
        return (v === undefined || v === null) ? (fallback === undefined ? "" : fallback) : String(v)
    }
    function flag(key, fallback) {
        const v = cfg[key]
        return (v === undefined || v === null) ? (fallback === true) : v === true
    }

    signal settingsChanged()

    // ── fonts ─────────────────────────────────────────────────────────────────
    // The views lay their columns out in characters, so the face has to be fixed-pitch:
    // the setting's family when it is installed, else the first of these that is. On
    // Windows "monospace" is no family, and Qt's stand-in for an unknown one is Segoe UI
    // — on the first desk the monitor's percentages wandered and the calendar's cells
    // shifted on the bracketed day. The Nerd font still has to be installed for the icons.
    readonly property var fixedFaces: ["JetBrainsMono Nerd Font Mono", "JetBrainsMono NFM", "Cascadia Mono", "Consolas",
                                       "Lucida Console", "Courier New", "DejaVu Sans Mono", "Liberation Mono",
                                       "Noto Sans Mono", "monospace"]
    function fixedFace(key) {
        const families = Qt.fontFamilies()
        const wanted = key ? str(key) : ""
        if (wanted !== "" && families.indexOf(wanted) >= 0) return wanted
        for (let i = 0; i < fixedFaces.length; i++)
            if (families.indexOf(fixedFaces[i]) >= 0) return fixedFaces[i]
        return "monospace"
    }

    function pollSettings() {
        Service.get("/settings/" + widget + "?since=" + cfgStamp, function(status, text) {
            if (status !== 200) return
            try {
                const d = JSON.parse(text)
                if (!d || d.values === undefined) return
                const first = !win.ready
                win.cfg = d.values
                win.cfgStamp = Number(d.stamp) || 0
                if (first) win.placeFromSettings()
                win.settingsChanged()
            } catch (e) {
                console.warn("plaintop: /settings did not parse:", e)
            }
        }, 3000)
    }

    // save({key: value}): to the service, which writes the file; the poll brings it back.
    function save(values) {
        Service.postJson("/settings/" + widget, values, function(d) { if (d) win.pollSettings() })
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: win.pollSettings()
    }

    // ── position ──────────────────────────────────────────────────────────────
    // The place is a setting: set once from it, written back after a drag. Nothing
    // follows the setting while the window is shown — a plasmoid's place is the
    // containment's, a window's is the window's.
    property bool placed: false
    function placeFromSettings() {
        const screens = Qt.application.screens
        const idx = Math.min(Math.max(0, num("screen", 0)), screens.length - 1)
        if (idx >= 0) win.screen = screens[idx]
        win.x = num("winX", 60)
        win.y = num("winY", 60)
        placed = true
    }
    Timer {
        id: moveSaver
        interval: 600
        onTriggered: {
            const screens = Qt.application.screens
            let idx = 0
            for (let i = 0; i < screens.length; i++) if (screens[i] === win.screen) idx = i
            win.save({ winX: win.x, winY: win.y, screen: idx })
        }
    }
    onXChanged: if (placed && !passing) moveSaver.restart()
    onYChanged: if (placed && !passing) moveSaver.restart()

    // ── the mouse while it is not passing through ─────────────────────────────
    // A left drag anywhere moves the window. The handler belongs to the window's content
    // item, the ancestor of the view, and holds the press passively: a click still
    // reaches the view's own mouse areas (a calendar cell, a player button, an active
    // line), and a drag past the threshold takes the press over from them and hands it
    // to the system move. Before this the mover sat under the view and only the bare
    // pixels dragged — "barely moved it", the first desk said. The handler must be the
    // ancestor's: in an item above the view it swallows the press (probed on 6.8 and
    // 6.10, docs/GOTCHAS.md). The right button opens the menu from under the view, where
    // no area of the view took it.
    DragHandler {
        id: dragger
        target: null
        enabled: !win.passing
        acceptedButtons: Qt.LeftButton
        onActiveChanged: if (active) win.startSystemMove()
    }
    MouseArea {
        id: mover
        anchors.fill: parent
        z: -1
        enabled: !win.passing
        acceptedButtons: Qt.RightButton
        onPressed: menu.popup()
    }

    Controls.Menu {
        id: menu
        Controls.MenuItem {
            text: win.i18nc("the widget's window menu", "Settings…")
            onTriggered: Service.postJson("/ui", { settings: win.widget })
        }
        Controls.MenuItem {
            text: win.i18nc("the widget's window menu", "Let clicks through")
            checkable: true
            checked: win.passing
            onTriggered: win.save({ clickThrough: checked })
        }
        Controls.MenuItem {
            text: win.i18nc("the widget's window menu", "Behind the desktop icons")
            checkable: true
            checked: win.flag("behindIcons", false)
            onTriggered: { win.save({ behindIcons: checked }); Service.postJson("/ui", { behind: win.widget, on: checked }) }
        }
        Controls.MenuSeparator {}
        Controls.MenuItem {
            text: win.i18nc("the widget's window menu", "Close")
            onTriggered: Service.postJson("/ui", { show: win.widget, on: false })
        }
    }

    // A widget that cannot reach the service says so in its own words — the hosts put
    // this where the plasmoid shows "no data".
    readonly property bool serviceDown: Service.failures >= 3
}
