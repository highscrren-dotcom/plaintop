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
        if (fresh.join("\n") === ids.join("\n"))
            return
        ids = fresh
        const ifs = match("^network/(?!all)[^/]+/download$").map(id => id.split("/")[1]).sort()
        if (ifs.join(" ") !== interfaces.join(" ")) {
            // Keep the current pick while the new set is being ranked, if it is still here.
            netSettled = false
            if (ifs.indexOf(bestInterface) < 0)
                bestInterface = ifs.length > 0 ? ifs[0] : ""
            interfaces = ifs
            if (ifs.length < 2)
                netSettled = true
        }
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

    // ── The network interface worth showing ───────────────────────────────────
    // ksystemstats publishes only hardware links that are up — docker bridges, tun and
    // veth never reach the tree — but it keeps them in a hash, so with two of them (Wi-Fi
    // plus a dock, two ports) "the first one" changed from one daemon start to the next.
    // So the candidates are sorted and ranked: a default gateway first (the NetworkManager
    // backend fills it; the rtnetlink one never does), then the traffic carried so far,
    // then the name. Ranked once per set of interfaces, so the pick does not flicker.
    property var interfaces: []
    property string bestInterface: ""
    property bool netSettled: false

    function rankInterfaces(force) {
        if (netSettled)
            return
        const probes = []
        for (let i = 0; i < netProbes.count; i++) {
            const p = netProbes.objectAt(i)
            if (!p || (!force && !p.answered))
                return      // someone has not answered yet
            probes.push(p)
        }
        if (probes.length === 0)
            return
        probes.sort((a, b) => (b.hasGateway - a.hasGateway) || (b.carried - a.carried)
                              || (a.name < b.name ? -1 : 1))
        bestInterface = probes[0].name
        netSettled = true
    }

    // A single interface needs no ranking, so the usual machine subscribes to nothing here.
    // The probes unsubscribe once the pick is made: totals change twice a second.
    property var netProbes: Instantiator {
        model: registry.interfaces.length > 1 ? registry.interfaces : []

        delegate: QtObject {
            id: probe
            required property var modelData
            readonly property string name: String(modelData)

            property var gateway4: Sensors.Sensor {
                sensorId: "network/" + probe.name + "/ipv4gateway"
                enabled: !registry.netSettled
            }
            property var gateway6: Sensors.Sensor {
                sensorId: "network/" + probe.name + "/ipv6gateway"
                enabled: !registry.netSettled
            }
            property var total: Sensors.Sensor {
                sensorId: "network/" + probe.name + "/totalDownload"
                enabled: !registry.netSettled
            }

            // ⚠️ `probe.` is not decoration: inside a Sensor a bare `name` is the sensor's
            // own display name. The status turns Ready on metadata; the value comes later.
            readonly property bool answered: gateway4.value !== undefined
                                             && gateway6.value !== undefined
                                             && total.value !== undefined
            readonly property bool hasGateway: String(gateway4.value || "").length > 0
                                               || String(gateway6.value || "").length > 0
            readonly property real carried: Number(total.value) || 0

            onAnsweredChanged: if (answered) registry.rankInterfaces(false)
        }

        onObjectAdded: registry.netTimeout.restart()
    }

    // A sensor that never answers must not keep the provisional pick forever.
    property var netTimeout: Timer {
        interval: 3000
        onTriggered: registry.rankInterfaces(true)
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
