pragma Singleton
import QtQuick
import plaintop

// Where the shims of this module get their readings: one poll of the service's /monitor
// for every Sensor, SensorDataModel and SensorTreeModel in the host, at the fastest rate
// any of them asked for. The service speaks ksystemstats' vocabulary (win/PROTOCOL.md),
// so the ids the shared QML asks for are the keys of `sensors` here.
QtObject {
    id: store

    // The /monitor answer: { stamp, sensors: {id: {value, name}}, processes, coreCount }.
    property var data: ({ sensors: {}, processes: [], coreCount: 0 })
    property bool answered: false          // at least one answer arrived
    property int rate: 1000                // ms; the smallest updateRateLimit asked for
    property int generation: 0             // grows with every answer that changed anything
    property string lastText: ""
    // The host parks the poll while the window is not drawn (PipeWire-side saving on the
    // Windows port, Phase 3): off screen the service's sampler is told to rest too, so
    // polling would only read the same answer again.
    property bool active: true

    signal updated()

    function want(ms) {
        if (ms > 0 && ms < rate) rate = ms
    }

    function value(id) {
        const s = data.sensors[id]
        return s === undefined ? undefined : s.value
    }
    function name(id) {
        const s = data.sensors[id]
        return (s && s.name) ? String(s.name) : ""
    }
    function has(id) { return data.sensors[id] !== undefined }
    function ids() { return Object.keys(data.sensors) }

    function poll() {
        Service.get("/monitor", function(status, text) {
            if (status !== 200) return
            // The same answer twice costs nobody a rebuild.
            if (text === store.lastText) return
            try {
                const d = JSON.parse(text)
                if (!d || !d.sensors) return
                store.lastText = text
                store.data = d
                store.answered = true
                store.generation++
                store.updated()
            } catch (e) {
                console.warn("plaintop: /monitor did not parse:", e)
            }
        }, 3000)
    }

    readonly property Timer timer: Timer {
        // A 2 s floor: the clock and the CPU bars are recomputed by MonitorData's own
        // 1 s tick from the last answer, so the bars stay within two seconds while the
        // service is asked half as often (the Windows budget's Phase 1).
        interval: Math.max(2000, store.rate)
        running: store.active
        repeat: true
        triggeredOnStart: true
        onTriggered: store.poll()
    }
}
