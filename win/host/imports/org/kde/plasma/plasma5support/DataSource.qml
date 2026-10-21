import QtQuick
import plaintop

// Plasma 5 Support's DataSource for the two engines the shared QML uses. "executable": a
// source is a command line, run by the service (POST /exec), its answer `newData(source,
// {stdout, stderr, "exit code"})` — once on connecting, then every `interval` ms while
// the interval is above zero, as the real engine does. "time": a source is "Local" or an
// IANA zone name, the answer {"Timezone City", "Offset"} from /time. Sources come from
// `connectedSources` or connectSource(); disconnectSource() drops one.
QtObject {
    id: ds

    property string engine: "executable"
    property int interval: 0
    property var connectedSources: []
    property var data: ({})

    signal newData(string source, var data)
    signal sourceAdded(string source)
    signal sourceRemoved(string source)

    // What is live right now, and which of them came from the list rather than a call.
    property var active: []
    property var fromList: []

    function connectSource(source) {
        const s = String(source)
        if (active.indexOf(s) >= 0) return
        active.push(s)
        activeChanged()
        sourceAdded(s)
        run(s)
    }

    function disconnectSource(source) {
        const s = String(source)
        const i = active.indexOf(s)
        if (i < 0) return
        active.splice(i, 1)
        activeChanged()
        sourceRemoved(s)
    }

    // The list changed: connect what is new, drop what left — only what the list owned.
    onConnectedSourcesChanged: {
        const want = (connectedSources || []).map(String)
        for (const s of fromList)
            if (want.indexOf(s) < 0) disconnectSource(s)
        for (const s of want)
            if (fromList.indexOf(s) < 0) connectSource(s)
        fromList = want
    }

    function run(source) {
        // An answer may arrive after the source went away with its host (the stands
        // destroy MonitorData between tests): then `ds` is null and there is nobody to tell.
        if (engine === "time") {
            Service.getJson("/time?zone=" + encodeURIComponent(source === "Local" ? "Local" : source), function(d) {
                if (!ds || !d || ds.active.indexOf(source) < 0) return
                const answer = { "Timezone City": String(d.city || ""), "Offset": Number(d.offset) || 0,
                                 "Timezone": String(d.zone || ""), "DateTime": new Date() }
                ds.data[source] = answer
                ds.newData(source, answer)
            }, 4000)
            return
        }
        Service.postJson("/exec", { command: source }, function(d) {
            if (!ds || ds.active.indexOf(source) < 0) return
            const answer = d ? d : { stdout: "", stderr: "the service did not answer", "exit code": 127 }
            ds.data[source] = answer
            ds.newData(source, answer)
        }, 15000)
    }

    readonly property Timer ticker: Timer {
        interval: Math.max(250, ds.interval)
        running: ds.interval > 0 && ds.active.length > 0
        repeat: true
        onTriggered: { for (const s of ds.active.slice()) ds.run(s) }
    }

    Component.onCompleted: {
        const want = (connectedSources || []).map(String)
        for (const s of want) connectSource(s)
        fromList = want
    }
}
