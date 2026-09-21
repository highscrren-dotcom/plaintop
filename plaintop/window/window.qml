import QtQuick
import QtCore

// The block description generated from schema/, deployed next to this file.
import "description.js" as Description

// Standalone host for the text monitor: the same lines, in a window that lets every click
// through. A desktop plasmoid never hands over the left button — see docs/GOTCHAS.md.
//
// ⚠️ Under Wayland a window cannot place itself: x and y are ignored. Position, size,
// keep-below and skip-taskbar come from the KWin rule that setup.py writes.
Window {
    id: win

    visible: true
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowStaysOnBottomHint
    title: "plaintop"           // the KWin rule matches on this title

    width: win.num("widgetWidth", 500)
    height: win.num("widgetHeight", 950)

    // Settings and the block description come from one JSON file. Reading a local file
    // needs QML_XHR_ALLOW_FILE_READ=1, which the launcher sets — inside plasmashell that
    // switch is not ours to make, here it is.
    //
    // ⚠️ The path comes from StandardPaths, not from a launcher argument: `qml6 file --
    // /home/user` puts "--" in arguments[2], and the config silently never loaded.
    readonly property string configPath:
        StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/plaintop/monitor.json"

    property var cfg: ({})
    property string lastRaw: ""

    function num(key, fallback) {
        const v = cfg[key]
        return (v === undefined || v === null) ? fallback : v
    }

    function loadConfig() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            const raw = xhr.responseText || ""
            if (raw.length === 0 || raw === win.lastRaw)
                return
            try {
                win.cfg = JSON.parse(raw)
                win.lastRaw = raw
            } catch (e) {
                console.warn("plaintop: monitor.json does not parse:", e)
            }
        }
        xhr.open("GET", win.configPath)
        xhr.send()
    }

    Component.onCompleted: loadConfig()

    // Re-read the file: hand edits and `--plaintop-export` both land here.
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: win.loadConfig()
    }

    MonitorData {
        id: monitorData
        // No blocks in the config (a first start, or a file that did not parse) is not a
        // reason to show nothing: the packaged description is the fallback, as in the
        // plasmoid host.
        blocks: (win.cfg.blocks !== undefined && win.cfg.blocks.length > 0)
                ? win.cfg.blocks : Description.BLOCKS
        rate: win.num("updateInterval", 1000)
    }

    MonitorView {
        anchors.fill: parent
        lines: monitorData.lines

        fontFamily: win.num("fontFamily", "JetBrainsMono Nerd Font Mono")
        fontSize: win.num("fontSize", 10)
        padLeft: win.num("padLeft", 48)
        padTop: win.num("padTop", 44)

        colorFg: win.num("colorFg", "#C8CCD4")
        colorAccent: win.num("colorAccent", "#E05561")
        colorDim: win.num("colorDim", "#6B7280")
        colorValue: win.num("colorValue", "#8FB6E0")
    }
}
