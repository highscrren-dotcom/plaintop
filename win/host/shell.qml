import QtQuick
import plaintop

// The one-process host: every widget window and the tray in a single QML engine.
//
// Why: each `qml.exe` pays for a whole Qt Quick stack — its own scene graph, render thread
// and font database — so five widgets meant five times the memory for one desktop. Here one
// engine carries five windows and the tray, and the service starts only this process
// (win/service/ui.py, `oneProcess`, the Windows default). The windows are the same hosts,
// unchanged: created when their `shown` setting is on, destroyed when it is not.
//
// The shell is told what to show by the service it already talks to: GET /ui answers the
// five `shown` flags next to the palette and the process list, so the tray's checkbox, the
// window's own menu and the settings window all keep working through the same route. The
// poll is two seconds — cheap, and the tray re-polls on its own click anyway.
//
// `oneProcess=false` in the ini keeps the old path (one process per widget); the service
// also falls back to it by itself if this shell dies three times in a row (ui.py).
QtObject {
    id: shell

    readonly property var widgets: ["monitor", "spectrum", "player", "weather", "calendar"]
    // widget → the created window, kept so a widget turned off is destroyed, not hidden.
    property var windows: ({})
    property bool trayMade: false
    property bool trayTried: false
    // A window that would not load is not tried again on every poll (which would fill the
    // log with the same warning twice a second); it is only reported once.
    property var failed: ({})

    function sync() {
        Service.getJson("/ui", function(d) {
            if (!d) return
            const shown = d.shown || {}
            for (let i = 0; i < shell.widgets.length; i++) {
                const w = shell.widgets[i]
                const want = shown[w] !== false
                const have = shell.windows[w] !== undefined
                if (want && !have && !shell.failed[w]) shell.create(w)
                else if (!want && have) shell.drop(w)
            }
            if (!shell.trayMade) shell.makeTray()
        })
    }

    function create(w) {
        const comp = Qt.createComponent(Qt.resolvedUrl(w + ".qml"))
        if (comp.status === Component.Error) {
            console.warn("plaintop shell: " + w + " did not load: " + comp.errorString())
            const bad = Object.assign({}, shell.failed)
            bad[w] = true
            shell.failed = bad
            return
        }
        const obj = comp.createObject(null)
        if (obj === null) {
            console.warn("plaintop shell: " + w + " did not create")
            const bad = Object.assign({}, shell.failed)
            bad[w] = true
            shell.failed = bad
            return
        }
        const next = Object.assign({}, shell.windows)
        next[w] = obj
        shell.windows = next
    }

    function drop(w) {
        const obj = shell.windows[w]
        if (obj === undefined) return
        const next = Object.assign({}, shell.windows)
        delete next[w]
        shell.windows = next
        obj.destroy()
    }

    function makeTray() {
        if (shell.trayMade || shell.trayTried) return
        shell.trayTried = true            // not tried twice a second if it cannot be made
        const comp = Qt.createComponent(Qt.resolvedUrl("tray.qml"))
        if (comp.status === Component.Error) {
            console.warn("plaintop shell: the tray did not load: " + comp.errorString())
            return
        }
        if (comp.createObject(null) === null) {
            console.warn("plaintop shell: the tray did not create")
            return
        }
        shell.trayMade = true
    }

    Component.onCompleted: shell.sync()

    property Timer poll: Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: shell.sync()
    }
}
