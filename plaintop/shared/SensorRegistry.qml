import QtQuick
import org.kde.ksysguard.sensors as Sensors

// What sensors this machine actually has.
//
// ⚠️ This exists because hardcoded ids rot. On the development machine the NVMe chip was
// `lmsensors/nvme-pci-0500/temp1` and became `nvme-pci-0600` when the PCI address changed,
// and the network interface went from `enp4s0` to `enp5s0` — both silently, both taking a
// reading away with them. The project already banned hwmon indexes for the same reason;
// chip names built from addresses rot the same way. So ids are discovered, and the
// settings hold a preference rather than a promise.
QtObject {
    id: registry

    property var tree: Sensors.SensorTreeModel {}

    property var ids: []
    readonly property bool ready: ids.length > 0

    function walk(parent, out) {
        const n = tree.rowCount(parent)
        for (let r = 0; r < n; r++) {
            const idx = tree.index(r, 0, parent)
            const id = tree.data(idx, Sensors.SensorTreeModel.SensorId)
            // The tree also carries group templates — `network/(?!all).*/download`,
            // `cpu/cpu\d+/temperature` — which are regular expressions, not sensors. Any
            // regex metacharacter in an id marks one; a real id never contains them.
            if (id && !/[(*\\?\[\]|+]/.test(String(id)))
                out.push(String(id))
            if (tree.rowCount(idx) > 0)
                walk(idx, out)
        }
        return out
    }

    // ⚠️ Assign only when the list really changed. Every assignment re-resolves the
    // preferences, hands MonitorData a new id list and recreates every Sensor object —
    // which the 10-second poll used to do for an unchanged tree.
    function refresh() {
        const fresh = walk(undefined, [])
        if (fresh.join("\n") !== ids.join("\n"))
            ids = fresh
    }

    function has(id) {
        return id && ids.indexOf(id) >= 0
    }

    // Every id matching a regular expression, in the order the daemon lists them.
    function match(pattern) {
        const re = new RegExp(pattern)
        return ids.filter(id => re.test(id))
    }

    function firstMatch(pattern) {
        const hits = match(pattern)
        return hits.length > 0 ? hits[0] : ""
    }

    // A preference wins when the machine has it; otherwise fall back to discovery.
    function resolve(preferred, pattern) {
        if (has(preferred))
            return preferred
        return firstMatch(pattern)
    }

    function resolveList(preferred, pattern) {
        const kept = (preferred || []).filter(id => has(id))
        return kept.length > 0 ? kept : match(pattern)
    }

    // The daemon answers a moment after start, and plugins can appear later.
    property var poll: Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            const before = registry.ids.length
            registry.refresh()
            if (registry.ids.length === before && before > 0)
                interval = 10000      // settled: keep checking, but rarely
        }
    }

    Component.onCompleted: refresh()
}
