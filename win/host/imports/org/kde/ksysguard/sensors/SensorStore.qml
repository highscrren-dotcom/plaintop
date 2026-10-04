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
        interval: Math.max(250, store.rate)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: store.poll()
    }
}
