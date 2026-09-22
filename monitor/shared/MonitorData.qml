import QtQuick

import org.kde.plasma.plasma5support as P5Support
import org.kde.ksysguard.sensors as Sensors
import org.kde.ksysguard.process as Proc
import org.kde.kitemmodels as KItem

// Data side of the text monitor, with no visuals of its own: subscriptions, one-shot
// readings, the slow commands, and the lines built from the description.
//
// Shared by both hosts — the plasmoid and the standalone click-through window — so the
// rules live in one place. The host supplies `blocks` and `rate`; what comes back is
// `lines`, where every part carries a role ("fg", "dim", "accent", "value") rather than a
// colour, because the palette belongs to the view.
Item {
    id: monitor

    visible: false

    // Set by the host.
    property var blocks: []
    property int rate: 1000
    property int processInterval: 2          // seconds between process-list reads

    // ⚠️ Path set by the host: the script sits in contents/code/ inside the plasmoid
    // package and next to the QML in the standalone host, so a relative guess here left
    // the services block silently empty in one of the two.
    property string servicesScript: Qt.resolvedUrl("services.sh").toString().replace("file://", "")

    readonly property int barWidth: 18          // bar width in characters, as in the lua

    // A parameter of an enabled block of this type — needed where sensor subscriptions
    // depend on it, not only the text.
    function blockParam(type, key, fallback) {
        for (const b of blocks) {
            if (b.type === type && b.enabled !== false) {
                const v = (b.params || {})[key]
                if (v !== undefined) return v
            }
        }
        return fallback
    }

    // "Custom sensor" blocks add their ids to the same subscription.
    readonly property var customSensorIds: {
        const out = []
        for (const b of blocks)
            if (b.type === "sensor" && b.enabled !== false && (b.params || {}).id)
                out.push(b.params.id)
        return out
    }

    // "Custom command" blocks: each has its own interval, so each gets its own source.
    readonly property var commandBlocks: {
        const out = []
        for (const b of blocks)
            if (b.type === "command" && b.enabled !== false && (b.params || {}).command)
                out.push({ id: b.id, command: b.params.command,
                           interval: Math.max(1, b.params.interval || 30) })
        return out
    }

    property var cmdOut: ({})

    Instantiator {
        model: monitor.commandBlocks

        delegate: P5Support.DataSource {
            required property var modelData
            engine: "executable"
            interval: modelData.interval * 1000
            connectedSources: [modelData.command]

            onNewData: function(source, data) {
                // Rebuild the whole object: editing a field does not wake bindings.
                const m = ({})
                for (const k in monitor.cmdOut) m[k] = monitor.cmdOut[k]
                m[modelData.id] = String(data.stdout).replace(/\n+$/, "")
                monitor.cmdOut = m
            }
        }
    }

    // What this machine actually has; the settings hold a preference, not a promise.
    property SensorRegistry registry: SensorRegistry {}

    readonly property var mounts: blockParam("disks", "mounts", ["/"])

    // ⚠️ Every machine-specific id goes through the registry: a preference is used when
    // the machine has it, otherwise the sensor is discovered. Hardcoded ids rot — the NVMe
    // chip name follows the PCI address and the network interface name can change on its
    // own; both did on the development machine and both quietly removed a reading.
    readonly property string netIface: {
        const preferred = blockParam("network", "interface", "")
        if (preferred.length > 0 && registry.has("network/" + preferred + "/download"))
            return preferred
        // Not the first one listed: the daemon lists interfaces in hash order.
        return registry.bestInterface.length > 0 ? registry.bestInterface : preferred
    }

    // ⚠️ Hardware-specific sensor ids are parameters, not literals: a fan chip and an
    // NVMe sensor exist under different names on every machine, and lm_sensors chips are
    // addressed by NAME rather than by hwmon index, because the indexes drift between
    // reboots. Empty means "this machine does not have it", and the line simply omits it.
    readonly property var fanSensors:
        registry.resolveList(blockParam("cpu", "fans", []), "^lmsensors/[^/]+/fan\\d+$")

    readonly property string nvmeSensor:
        registry.resolve(blockParam("disks", "nvmeSensor", ""), "^lmsensors/nvme-[^/]+/temp1$")

    // ── Data ──────────────────────────────────────────────────────────────────
    // One SensorDataModel for all values: a single subscription instead of a hundred
    // objects. Roles are taken by name (Sensors.SensorDataModel.Value), not by number —
    // the numbers are not promised across Plasma versions.
    // ⚠️ The core count comes from the sensors, not from a number in the code: this used
    // to be a hardcoded 72, which is this machine and nobody else's. It is latched once a
    // positive value arrives, so the subscription is not rebuilt on every reading.
    property int coreCount: 0

    readonly property var coreIds: {
        const a = []
        for (let i = 0; i < coreCount; i++) a.push("cpu/cpu" + i + "/usage")
        for (let i = 0; i < coreCount; i++) a.push("cpu/cpu" + i + "/temperature")
        return a
    }

    // ⚠️ Duplicates must be removed: SensorDataModel collapses identical ids, the
    // columns become fewer than the list entries, and reads by index slide off.
    readonly property var sensorIds: coreIds

    // ⚠️ Two subscriptions on purpose. The uniform core arrays go through one
    // SensorDataModel, which handles hundreds of them well. Everything else — including
    // every machine-specific id — goes through individual Sensor objects, because a batch
    // model silently dropped the lm_sensors ids from its columns (21 requested, 18
    // columns, the fan and NVMe ids missing), while the same ids read fine one by one.
    // Verified on s1dPC 2026-09-21. Individual sensors also carry `status`, so "this
    // machine has no such sensor" is distinguishable from "the value is zero".
    readonly property var namedIds: {
        const out = [], seen = ({})
        for (const id of rawSensorIds)
            if (!seen[id]) { seen[id] = true; out.push(id) }
        return out
    }

    // Latest values of the individual sensors, mutated in place and never reassigned.
    // ⚠️ Reassigning them made every line depend on each sensor: ~25 sensors updating once
    // a second rebuilt all the lines ~25 times a second, 15% of a core for text that
    // changes once. The lines are rebuilt on `tick` alone and read these maps then.
    property var named: ({})
    property var namedReady: ({})

    function publish(id, value, ready) {
        named[id] = value
        namedReady[id] = ready
    }

    Instantiator {
        model: monitor.namedIds

        delegate: Sensors.Sensor {
            required property var modelData
            sensorId: modelData
            updateRateLimit: monitor.rate
            onValueChanged: monitor.publish(sensorId, value, status === 2)
            onStatusChanged: monitor.publish(sensorId, value, status === 2)
        }
    }

    readonly property var rawSensorIds: [
        "cpu/all/usage",
        "memory/physical/usedPercent", "memory/physical/used", "memory/physical/total",
        "os/system/hostname", "os/system/name", "os/kernel/version",
        "cpu/all/cpuCount", "cpu/all/coreCount",
        "gpu/gpu0/usage", "gpu/gpu0/temperature", "gpu/gpu0/usedVram",
        "gpu/gpu0/totalVram", "gpu/gpu0/power", "gpu/gpu0/name",
        "network/" + netIface + "/download", "network/" + netIface + "/upload",
        "os/system/uptime"
    ].concat(customSensorIds).concat(fanSensors).concat(
        nvmeSensor.length > 0 ? [nvmeSensor] : [])

    // ⚠️ Columns are found by asking the model for each column's SensorId, never by the
    // position in the requested list. SensorDataModel silently drops ids it cannot
    // resolve — on this machine three of 165 — and every column after the gap shifts, so
    // an index built from the request reads the wrong sensor or nothing at all. That is
    // the difference between working here and working on a machine with other hardware.
    property var colOf: ({})

    function rebuildColumns() {
        const m = ({})
        const n = mon.columnCount()
        for (let c = 0; c < n; c++) {
            const id = mon.data(mon.index(0, c), Sensors.SensorDataModel.SensorId)
            if (id)
                m[String(id)] = c
        }
        colOf = m
    }

    readonly property int missingSensors: Math.max(0, sensorIds.length - Object.keys(colOf).length)

    Connections {
        target: mon

        function onColumnsInserted() { monitor.rebuildColumns() }
        function onColumnsRemoved() { monitor.rebuildColumns() }
        function onModelReset() { monitor.rebuildColumns() }
    }

    // The daemon answers a moment after the subscription, so the first rebuild has nothing
    // to see; this keeps trying until the column count and the map agree.
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            if (Object.keys(monitor.colOf).length !== mon.columnCount())
                monitor.rebuildColumns()
        }
    }

    Sensors.SensorDataModel {
        id: mon
        sensors: monitor.sensorIds
        updateRateLimit: monitor.rate
    }

    // Latch the core count once: cpu/all/cpuCount answers a moment after the daemon wakes,
    // and rebuilding the subscription on every reading would be wasteful.
    Timer {
        interval: 500
        running: monitor.coreCount === 0
        repeat: true
        onTriggered: {
            // ⚠️ cpu/all/coreCount is the number of cpuN sensors (72 here); cpu/all/cpuCount
            // is the number of physical CPUs (2). Latching the wrong one subscribed to two
            // cores, and the per-node temperatures quietly disappeared. Verified.
            const cores = Math.round(monitor.num("cpu/all/coreCount", 0))
            const cpus = Math.round(monitor.num("cpu/all/cpuCount", 0))
            const n = Math.max(cores, cpus)
            if (n > 0)
                monitor.coreCount = n
        }
    }

    // ⚠️ The process list is the most expensive thing collected here: the model reads all
    // of /proc (~900 processes on s1dPC) on its own timer, fixed at 2 s inside libksysguard,
    // whatever `rate` says. Measured 2026-09-22: 3.2% of a core at 2 s, 1.3% at 10 s. So it
    // runs only when some block shows a top list, and for an interval above 2 s it is
    // switched on for a single read per period — `enabled` starts and stops that timer,
    // the first read lands 2 s after the start, and the model sleeps again right after it.
    readonly property bool needProcesses: {
        for (const b of blocks)
            if ((b.type === "cpu" || b.type === "memory") && b.enabled !== false
                    && ((b.params || {}).top_processes || 0) > 0)
                return true
        return false
    }
    readonly property bool processDuty: processInterval > 2
    property bool processAwake: false

    Proc.ProcessDataModel {
        id: procs
        enabledAttributes: ["name", "usage", "memory"]
        enabled: monitor.needProcesses && (!monitor.processDuty || monitor.processAwake)
    }

    Timer {
        interval: monitor.processInterval * 1000
        running: monitor.needProcesses && monitor.processDuty
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            monitor.processAwake = true
            processSafety.restart()
        }
    }

    // One read has landed: back to sleep. The safety net covers a read that never came.
    Connections {
        target: procs
        function onDataChanged() { monitor.processAwake = false }
    }

    Timer {
        id: processSafety
        interval: 3000
        onTriggered: monitor.processAwake = false
    }

    KItem.KSortFilterProxyModel {
        id: byCpu
        sourceModel: procs
        sortRoleName: "Value"     // ⚠️ sortRoleName, not sortRole: the component won't build
        sortColumn: 1
        sortOrder: Qt.DescendingOrder
    }

    KItem.KSortFilterProxyModel {
        id: byMem
        sourceModel: procs
        sortRoleName: "Value"
        sortColumn: 2
        sortOrder: Qt.DescendingOrder
    }

    // The core-to-NUMA-node layout, the CPU model and the board are read once: the
    // sensors do not have them (cpu/all/name returns the localized "All"), and they do
    // not change within a session.
    property var nodeCpus: []
    property string cpuModel: ""
    property string boardLine: ""
    property int cpuSockets: 0
    property int cpuCores: 0
    property int cpuThreads: 0

    P5Support.DataSource {
        id: once
        engine: "executable"
        connectedSources: [
            "cat /sys/devices/system/node/node*/cpulist",
            "LC_ALL=C lscpu",
            "cat /sys/devices/virtual/dmi/id/board_vendor /sys/devices/virtual/dmi/id/board_name /sys/devices/virtual/dmi/id/bios_version"
        ]

        onNewData: function(source, data) {
            if (data["exit code"] === 0) {
                if (source.indexOf("cpulist") >= 0) parseNodes(String(data.stdout))
                else if (source.indexOf("lscpu") >= 0) parseLscpu(String(data.stdout))
                else parseBoard(String(data.stdout))
            }
            disconnectSource(source)
        }

        function parseNodes(out) {
            const nodes = []
            for (const line of out.trim().split("\n")) {
                const set = ({})
                for (const part of line.split(",")) {
                    const r = part.split("-").map(Number)
                    for (let i = r[0]; i <= (r.length > 1 ? r[1] : r[0]); i++) set[i] = true
                }
                nodes.push(set)
            }
            monitor.nodeCpus = nodes
        }

        function parseBoard(out) {
            const l = out.trim().split("\n")
            if (l.length >= 3) monitor.boardLine = l[0] + " " + l[1] + "  (BIOS " + l[2] + ")"
        }

        function parseLscpu(out) {
            let model = "", sockets = 0, perSocket = 0, perCore = 0
            for (const line of out.split("\n")) {
                const i = line.indexOf(":")
                if (i < 0) continue
                const key = line.slice(0, i).trim()
                const val = line.slice(i + 1).trim()
                if (key === "Model name") model = val
                else if (key === "Socket(s)") sockets = Number(val)
                else if (key === "Core(s) per socket") perSocket = Number(val)
                else if (key === "Thread(s) per core") perCore = Number(val)
            }
            // «Intel(R) Xeon(R) CPU E5-2697 v4 @ 2.30GHz» → «Intel Xeon E5-2697 v4»
            monitor.cpuModel = model.replace(/\(R\)|\(TM\)/g, "").replace(/ CPU /, " ")
                                 .replace(/ @.*$/, "").replace(/\s+/g, " ").trim()
            monitor.cpuSockets = sockets
            monitor.cpuCores = sockets * perSocket
            monitor.cpuThreads = sockets * perSocket * perCore
        }
    }

    // Filesystems: the sensors key them by disk UUID, while the mount points are what
    // we need — so take df, the way conky did.
    property var diskRows: []

    P5Support.DataSource {
        id: slow
        engine: "executable"
        // ⚠️ Once every 10 s, not on every tick: each run is a fork in the shell process.
        interval: 10000
        connectedSources: [
            "df -B1 --output=target,size,used,pcent " + monitor.mounts.join(" ") + " 2>/dev/null"
        ]

        onNewData: function(source, data) {
            const rows = []
            // The first line is the df header, and it is localized; parse by position.
            for (const line of String(data.stdout).trim().split("\n").slice(1)) {
                const f = line.trim().split(/\s+/)
                if (f.length < 4) continue
                rows.push({ target: f[0], size: Number(f[1]), used: Number(f[2]),
                            pct: Number(String(f[3]).replace("%", "")) })
            }
            monitor.diskRows = rows
        }
    }

    property var serviceRows: []

    P5Support.DataSource {
        id: services
        engine: "executable"
        // Services change rarely and each run is a fork: once every 15 s is enough.
        interval: 15000
        // The script lives in the package itself; the engine runs the command through a
        // shell, so passing it the path without the file:// scheme is enough.
        connectedSources: ["bash " + monitor.servicesScript]

        onNewData: function(source, data) {
            const rows = []
            for (const line of String(data.stdout).trim().split("\n")) {
                const i = line.indexOf("|")
                if (i < 0) continue
                rows.push({ label: line.slice(0, i), value: line.slice(i + 1) })
            }
            monitor.serviceRows = rows
        }
    }

    // The tick every computed line depends on: reading from the model does not create a
    // binding by itself, so the dependency is made explicit.
    property int tick: 0

    Timer {
        interval: monitor.rate
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: monitor.tick++
    }

    function sval(id) {
        // Named sensors first, then the core model by column id.
        const v = named[id]
        if (v !== undefined)
            return v
        const col = colOf[id]
        if (col === undefined)
            return undefined
        return mon.data(mon.index(0, col), Sensors.SensorDataModel.Value)
    }

    function sensorReady(id) {
        if (namedReady[id] !== undefined)
            return namedReady[id] === true
        return colOf[id] !== undefined
    }

    function num(id, fallback) {
        const v = sval(id)
        return (v === undefined || v === null || isNaN(v)) ? fallback : Number(v)
    }

    // ── Formatting ────────────────────────────────────────────────────────────
    // ⚠️ Our own, not formattedValue: that one inserts U+200B before "%" and U+2009
    // before "°C", and in monospace text the columns drift apart.
    function bar(pct) {
        const k = Math.max(0, Math.min(barWidth, Math.round(pct * barWidth / 100)))
        return "/".repeat(k) + " ".repeat(barWidth - k)
    }

    function pct(v) {
        return String(Math.round(v)).padStart(3) + "%"
    }

    // The label is exactly three characters — otherwise the percent column wanders
    // with the label length.
    function barRow(label, value) {
        return String(label).padEnd(3).slice(0, 3) + " " + bar(value) + " " + pct(value)
    }

    function comma(x, digits) {
        return x.toFixed(digits).replace(".", ",")
    }

    function gib(bytes) {
        return comma(bytes / 1024 / 1024 / 1024, 1) + " GiB"
    }

    function speed(bytes) {
        if (bytes >= 1024 * 1024) return comma(bytes / 1024 / 1024, 1) + " MiB/s"
        if (bytes >= 1024) return comma(bytes / 1024, 0) + " KiB/s"
        return Math.round(bytes) + " B/s"
    }

    function human(secs) {
        const d = Math.floor(secs / 86400)
        const h = Math.floor(secs % 86400 / 3600)
        const m = Math.floor(secs % 3600 / 60)
        return (d > 0 ? d + "д " : "") + h + "ч " + m + "м"
    }

    // ── Values ────────────────────────────────────────────────────────────────
    function nodeUsage(n) {
        const set = nodeCpus[n]
        if (!set) return 0
        let sum = 0, cnt = 0
        for (let i = 0; i < coreCount; i++) if (set[i]) { sum += num("cpu/cpu" + i + "/usage", 0); cnt++ }
        return cnt > 0 ? sum / cnt : 0
    }

    function nodeTemp(n) {
        const set = nodeCpus[n]
        if (!set) return 0
        let max = 0
        for (let i = 0; i < coreCount; i++) if (set[i]) max = Math.max(max, num("cpu/cpu" + i + "/temperature", 0))
        return max
    }

    function topRows(model, column, count, format) {
        const out = []
        const n = Math.min(count, model.rowCount())
        for (let i = 0; i < n; i++) {
            const name = String(model.data(model.index(i, 0), Proc.ProcessDataModel.Value) || "")
            const v = model.data(model.index(i, column), Proc.ProcessDataModel.Value)
            out.push(name.slice(0, 20).padEnd(21) + "| " + format(Number(v) || 0))
        }
        return out
    }

    // ── Building lines from the description ───────────────────────────────────
    // A line is a set of parts with one common font size; the clock stands apart
    // because it has two different font sizes on one baseline.
    function line(text, role) {
        return { kind: "parts", parts: [{ text: text, role: role || "fg" }] }
    }

    function kvLine(label, value) {
        return { kind: "parts", parts: [
            { text: String(label).padEnd(21), role: "dim" },
            { text: "| " + value, role: "fg" }
        ] }
    }

    readonly property var lines: {
        tick
        const out = []

        for (const b of blocks) {
            if (b.enabled === false) continue
            const p = b.params || {}

            switch (b.type) {
            case "header": {
                // The text is the user's own and empty by default: no stranger's name on
                // a fresh install. Nothing is joined to an empty part, so no stray "\".
                const host = p.hostname === false ? "" : sval("os/system/hostname")
                const parts = [String(p.text || ""), String(host || "")]
                const head = parts.filter(s => s.length > 0).join("\\")
                if (head.length > 0)
                    out.push(line(head, "accent"))
                break
            }
            case "clock": {
                const big = Qt.formatTime(new Date(), "HH:mm")
                if (p.seconds === false) out.push({ kind: "clock", big: big, small: "" })
                else out.push({ kind: "clock", big: big, small: Qt.formatTime(new Date(), ":ss") })
                break
            }
            case "date": {
                // ⚠️ Qt.formatDate takes the C locale and produces "Sunday, 20 September"
                // even under ru_RU. Only toLocaleDateString gives the Russian names.
                const d = new Date().toLocaleDateString(Qt.locale(), "dddd, d MMMM")
                out.push(line(d.charAt(0).toUpperCase() + d.slice(1), "value"))
                break
            }
            case "os":
                out.push(line((sval("os/system/name") || "") + "  " + (sval("os/kernel/version") || ""), "dim"))
                break

            case "separator":
                out.push(line("-".repeat(35), "dim"))
                break

            case "cpu": {
                const usage = num("cpu/all/usage", 0)
                out.push(line(barRow("CPU", usage)))
                if (p.per_socket !== false) {
                    for (let n = 0; n < nodeCpus.length; n++)
                        out.push(line(barRow("S" + n, nodeUsage(n)) + "   node" + n))
                }
                if (p.model_line !== false) {
                    const name = (cpuSockets > 1 ? cpuSockets + "x " : "") + (cpuModel || "CPU")
                    const t0 = Math.round(nodeTemp(0)), t1 = Math.round(nodeTemp(1))
                    const rpm = []
                    for (const id of fanSensors) {
                        const v = Math.round(num(id, 0))
                        if (v > 0) rpm.push(v)
                    }
                    out.push(line(name + "  " + cpuCores + "c/" + cpuThreads + "t  "
                                  + (t0 > 0 ? t0 + "/" + t1 + "°C  " : "")
                                 + (rpm.length > 0 ? rpm.join("/") + " rpm" : ""), "dim"))
                }
                for (const r of topRows(byCpu, 1, p.top_processes || 0, v => comma(v, 1) + "%"))
                    out.push(line(r))
                break
            }

            case "memory": {
                const used = num("memory/physical/usedPercent", 0)
                out.push(line(barRow("RAM", used)))
                if (p.totals !== false)
                    out.push(line(gib(num("memory/physical/used", 0)) + " / "
                                  + gib(num("memory/physical/total", 0)), "dim"))
                for (const r of topRows(byMem, 2, p.top_processes || 0, v => gib(v * 1024)))
                    out.push(line(r))
                break
            }

            case "gpu": {
                out.push(line(barRow("GPU", num("gpu/gpu0/usage", 0))))
                if (p.details !== false) {
                    out.push(line("VRAM " + comma(num("gpu/gpu0/usedVram", 0) / 1073741824, 1)
                                  + "/" + comma(num("gpu/gpu0/totalVram", 0) / 1073741824, 1)
                                  + " GB  temp " + Math.round(num("gpu/gpu0/temperature", 0))
                                  + "°C  pwr " + Math.round(num("gpu/gpu0/power", 0)) + "W", "dim"))
                }
                break
            }

            case "disks": {
                for (const d of diskRows) {
                    const name = d.target === "/" ? "/" : d.target.split("/").pop()
                    out.push(line(barRow(name, d.pct)))
                    let note = "F: " + gib(d.size - d.used) + "  T: " + gib(d.size)
                    if (d.target === "/" && p.nvme_temp !== false) {
                        const t = nvmeSensor.length > 0 ? Math.round(num(nvmeSensor, 0)) : 0
                        if (t > 0) note += "  nvme " + t + "°C"
                    }
                    out.push(line(note, "dim"))
                }
                // Configured but not mounted: say so instead of staying silent.
                for (const m of (p.mounts || [])) {
                    if (!diskRows.some(d => d.target === m))
                        out.push(line(m.split("/").pop() + " | не смонтирован", "dim"))
                }
                break
            }

            case "uptime":
                out.push(line("аптайм " + human(num("os/system/uptime", 0))))
                break

            case "network": {
                // netIface already honours p.interface and falls back to discovery.
                const iface = netIface
                out.push(line(iface + "  Dl " + speed(num("network/" + iface + "/download", 0))
                              + "  Ul " + speed(num("network/" + iface + "/upload", 0)), "dim"))
                break
            }

            case "services":
                for (const s of serviceRows) out.push(kvLine(s.label, s.value))
                break

            case "command": {
                const text = cmdOut[b.id]
                const rows = (text === undefined ? ["…"] : text.split("\n")).slice(0, p.lines || 1)
                for (const r of rows) out.push(kvLine(p.label || b.id, r))
                break
            }

            case "sensor": {
                const v = num(p.id, 0)
                const label = p.label || "SEN"
                if (p.bar !== false) out.push(line(barRow(label, v) + (p.suffix || "")))
                else out.push(kvLine(label, comma(v, p.digits || 0) + (p.suffix || "")))
                break
            }

            case "passport": {
                if (cpuModel) out.push(line("CPU | " + (cpuSockets > 1 ? cpuSockets + "x " : "") + cpuModel, "dim"))
                const gpu = sval("gpu/gpu0/name")
                if (gpu) out.push(line("GPU | " + gpu, "dim"))
                if (boardLine) out.push(line("MBD | " + boardLine, "dim"))
                break
            }
            }
        }
        return out
    }
}
