import QtQuick

// Data side of the visualizer, with no visuals of its own: polls the relay, decides
// whether anything is playing, and hands the bands over by signal.
//
// Both hosts use this file — the plasmoid and the standalone window — so the polling
// rules live in one place. Two copies of this logic would drift apart silently.
QtObject {
    id: source

    // Set by the host.
    property int relayPort: 8788
    property int bars: 160
    property int dataRate: 30
    property int idleRate: 4
    property bool hideWhenQuiet: true
    property int quietThreshold: 2
    property int quietDelayMs: 900
    property bool mirror: false
    property bool reverse: false

    // Read by the host.
    property bool relayUp: false
    property bool sounding: false

    signal levelsReady(var values)

    readonly property int count: Math.max(2, bars)
    readonly property real quietLevel: quietThreshold / 100

    // Band order: mirrored halves fold the spectrum back on itself, reverse flips it.
    function bandOf(i) {
        let k = reverse ? count - 1 - i : i
        if (mirror) {
            const half = Math.floor(count / 2)
            k = k < half ? k : count - 1 - k
            return Math.min(k * 2, count - 1)
        }
        return k
    }

    function poll() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status !== 200) {
                source.relayUp = false
                return
            }
            source.relayUp = true

            // Plain text rather than JSON: at thirty polls a second the parsing shows up.
            const raw = xhr.responseText.split(",")
            const values = new Array(raw.length)
            let peak = 0
            for (let i = 0; i < raw.length; i++) {
                values[i] = (+raw[i]) / 1000
                if (values[i] > peak)
                    peak = values[i]
            }
            if (peak > source.quietLevel) {
                source.sounding = true
                quietTimer.restart()
            }
            if (source.sounding || !source.hideWhenQuiet) {
                if (values.length >= source.count) {
                    const mapped = new Array(source.count)
                    for (let i = 0; i < source.count; i++)
                        mapped[i] = values[source.bandOf(i)]
                    source.levelsReady(mapped)
                }
            }
        }
        xhr.open("GET", "http://127.0.0.1:" + relayPort + "/bands?bars=" + count)
        xhr.send()
    }

    // While hidden the visualizer only listens for sound returning, so it polls slowly:
    // silence costs a few requests a second instead of thirty.
    property Timer pollTimer: Timer {
        interval: (source.sounding || !source.hideWhenQuiet)
            ? Math.max(8, Math.round(1000 / Math.max(1, source.dataRate)))
            : Math.max(100, Math.round(1000 / Math.max(1, source.idleRate)))
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: source.poll()
    }

    // `sounding` goes true on the first loud frame and back to false after quietDelayMs
    // without one, so a pause between tracks does not blink the ring.
    property Timer quietTimer: Timer {
        id: quietTimer
        interval: Math.max(100, source.quietDelayMs)
        repeat: false
        onTriggered: {
            source.sounding = false
            // Zero the ticks while hidden: when the sound returns they grow out of the
            // ring rather than snapping to the level they held when it stopped.
            source.levelsReady(new Array(source.count).fill(0))
        }
    }
}
