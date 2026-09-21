import QtQuick

// Standalone host: the same ring, in a window that lets every click through.
//
// Why this exists next to the plasmoid: a desktop plasmoid never hands over the left
// button — four ways were tried, see docs/GOTCHAS.md. A plain window with
// Qt.WindowTransparentForInput does, verified with a counter that stayed at zero.
//
// ⚠️ Under Wayland a window cannot place itself: x and y are ignored. Position, size,
// keep-below and skip-taskbar come from the KWin rule that install.sh writes.
Window {
    id: win

    visible: true
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowStaysOnBottomHint
    title: "plainspectrum"      // the KWin rule matches on this title

    width: ring.implicitWidth
    height: ring.implicitHeight

    // Settings come from the relay, not from the file: QML cannot write files, so the
    // relay owns ring.json and both this window and the settings editor talk to that one
    // owner. The port is the only thing known up front.
    readonly property int port: 8788

    property var cfg: ({})
    property string lastRaw: ""

    function loadConfig() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200)
                return
            const raw = xhr.responseText || ""
            if (raw.length === 0 || raw === win.lastRaw)
                return
            try {
                win.cfg = JSON.parse(raw)
                win.lastRaw = raw
            } catch (e) {
                console.warn("plainspectrum: the relay returned unparseable settings:", e)
            }
        }
        xhr.open("GET", "http://127.0.0.1:" + port + "/config")
        xhr.send()
    }

    function num(key, fallback) {
        const v = cfg[key]
        return (v === undefined || v === null) ? fallback : v
    }

    Component.onCompleted: loadConfig()

    // Re-read the settings often enough that the editor feels live.
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: win.loadConfig()
    }

    Spectrum {
        id: spectrum
        relayPort: win.port
        bars: win.num("bars", 160)
        dataRate: win.num("dataRate", 30)
        idleRate: win.num("idleRate", 4)
        hideWhenQuiet: win.num("hideWhenQuiet", true)
        quietThreshold: win.num("quietThreshold", 2)
        quietDelayMs: win.num("quietDelayMs", 900)
        mirror: win.num("mirror", false)
        reverse: win.num("reverse", false)
    }

    Ring {
        id: ring
        source: spectrum

        layoutMode: win.num("layout", 0)
        bars: win.num("bars", 160)
        radius: win.num("radius", 360)
        span: win.num("span", 360)
        startAngle: win.num("startAngle", 0)
        spacing: win.num("spacing", 2)
        thickness: win.num("thickness", 5)
        minLength: win.num("minLength", 10)
        maxLength: win.num("maxLength", 170)
        growth: win.num("growth", 0)
        element: win.num("element", 0)
        blockSize: win.num("blockSize", 6)
        blockGap: win.num("blockGap", 3)
        rounded: win.num("rounded", false)
        tint: win.num("color", "#C8CCD4")
        tintHigh: win.num("colorHigh", "")
        opacityPercent: win.num("opacityPercent", 100)
        guide: win.num("guide", false)
        smoothMs: win.num("smoothMs", 70)
        fadeMs: win.num("fadeMs", 500)
        hideWhenQuiet: win.num("hideWhenQuiet", true)
    }
}
