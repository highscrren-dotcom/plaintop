import QtQuick

import org.kde.plasma.plasma5support as P5Support
import org.kde.ksysguard.sensors as Sensors
import org.kde.ksysguard.process as Proc
import org.kde.kitemmodels as KItem
import org.kde.ki18n

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
    property string healthScript: Qt.resolvedUrl("health.sh").toString().replace("file://", "")

    // Width of the text area in characters, set by the host from its width and font: the
    // one place free text (journal messages) is cut. The tabular lines are built to fit.
    property int columns: 57

    readonly property int barWidth: 18          // bar width in characters, as in the lua

    // ⚠️ Translations go through a context object, not a bare i18n(): this file runs in
    // the plasmoid, where i18n() exists, and in the bare qml6 window host, where it does
    // not. The domain is the plasmoid's own, so both hosts read one catalog — see
    // decision 7 in docs/DECISIONS.md.
    readonly property KI18nContext tr: KI18nContext {
        translationDomain: "plasma_applet_org.s1dd1.plaintop"
    }

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

    // Whether an enabled block of this type exists: what no block shows is not collected.
    function hasBlock(type) {
        for (const b of blocks)
            if (b.type === type && b.enabled !== false) return true
        return false
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

    // Pressure stall information: a kernel feature, so the ids are the same on every
    // machine, but the plugin may be missing — then the block hides. ⚠️ Not
    // registry.has("pressure"): a group node may or may not be listed, a leaf is a fact.
    // pressure/cpu/full* is always zero by kernel semantics and is never subscribed; the
    // memory and I/O full stalls only when the block shows them.
    readonly property bool hasPressure: hasBlock("pressure")
        && registry.match("^pressure/cpu/some10Sec$").length > 0
    readonly property var pressureIds: !hasPressure ? []
        : ["pressure/cpu/some10Sec", "pressure/memory/some10Sec", "pressure/io/some10Sec"]
            .concat(blockParam("pressure", "full", false) === true
                    ? ["pressure/memory/full10Sec", "pressure/io/full10Sec"] : [])

    // Batteries: whatever the power plugin reports, sorted by id so the order holds. A bare
    // "power" group with no children sits in the tree of a desktop machine; the leaf
    // pattern never matches it. The registry keeps polling, so a battery that appears
    // later brings the block with it — verified in a standalone run, 2026-09-23.
    readonly property var batteries: hasBlock("battery")
        ? registry.match("^power/[^/]+/chargePercentage$").map(id => id.split("/")[1]).sort()
        : []
    readonly property var batteryIds: {
        const out = []
        for (const b of batteries)
            for (const k of ["chargePercentage", "chargeRate", "charge", "capacity", "health"])
                out.push("power/" + b + "/" + k)
        return out
    }

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
        nvmeSensor.length > 0 ? [nvmeSensor] : []).concat(pressureIds).concat(batteryIds)

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
            // "key|field|field…": the script reports numbers and states, the text is made
            // in serviceText(), where the catalog and its plural forms are.
            const rows = []
            for (const line of String(data.stdout).trim().split("\n")) {
                const f = line.split("|")
                if (f.length < 2) continue
                rows.push({ label: f[0], fields: f.slice(1) })
            }
            monitor.serviceRows = rows
        }
    }

    // System health: failed units, error counts and the last error lines, from a script in
    // the package like the services. Gated on the block: nothing runs for a block nobody
    // shows. The line count is the script's argument, so it never reads more than shown.
    property var healthData: ({})
    // −1 without an enabled health block, else its line count (0–5). One property read
    // from `blocks` directly: split in two (enabled, lines) the command was rebuilt twice
    // per change of `blocks` and the first script killed while still running — reproduced
    // in the standalone harness, 2026-09-23.
    readonly property int healthSpec: {
        for (const b of blocks) {
            if (b.type !== "health" || b.enabled === false) continue
            const v = (b.params || {}).lines
            return Math.max(0, Math.min(5, Number(v === undefined ? 3 : v) || 0))
        }
        return -1
    }

    P5Support.DataSource {
        id: healthSource
        engine: "executable"
        interval: 15000
        connectedSources: monitor.healthSpec < 0 ? []
            : ["bash " + monitor.healthScript + " " + monitor.healthSpec]

        onNewData: function(source, data) {
            // "failed|s|u", "err|s|u" or "err|noaccess", "errline|ident|message".
            const h = { failed: null, err: null, lines: [] }
            for (const row of String(data.stdout).trim().split("\n")) {
                const f = row.split("|")
                if (f[0] === "failed" && f.length >= 3) h.failed = [f[1], f[2]]
                else if (f[0] === "err" && f.length >= 2) h.err = f.slice(1)
                else if (f[0] === "errline" && f.length >= 2) {
                    // The message may carry "|" itself: everything after the ident is text.
                    const named = f.length >= 3
                    h.lines.push({ ident: named ? f[1] : "", text: f.slice(named ? 2 : 1).join("|") })
                }
            }
            monitor.healthData = h
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

    // The decimal separator is the locale's: a comma under ru_RU, a point under en_US.
    function comma(x, digits) {
        return x.toFixed(digits).replace(".", Qt.locale().decimalPoint)
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
        return (d > 0 ? tr.i18nc("uptime: days, abbreviated", "%1d", d) + " " : "")
            + tr.i18nc("uptime: hours, abbreviated", "%1h", h) + " "
            + tr.i18nc("uptime: minutes, abbreviated", "%1m", m)
    }

    // Hours and minutes of an estimate, the minutes always two digits so the text does
    // not shift as they pass. Days fold into hours: a battery past a day is "26h 10m".
    function hoursMinutes(secs) {
        const s = isFinite(secs) ? Math.max(0, secs) : 0
        return tr.i18nc("battery: hours and minutes of an estimate", "%1h %2m",
                        Math.floor(s / 3600), String(Math.floor(s % 3600 / 60)).padStart(2, "0"))
    }

    // Free text is cut at the widget's width with an ellipsis.
    function clip(text) {
        return text.length > columns ? text.slice(0, Math.max(0, columns - 1)) + "…" : text
    }

    // The battery's second line, from numbers alone so it can be tested on a machine
    // without one: the charge in %, the rate in W (positive charging, negative
    // discharging), charge and capacity in Wh, the health in % (negative when absent).
    function batteryText(percent, rate, charge, capacity, health) {
        const w = Math.abs(rate)
        let s
        if (w < 0.05)
            s = percent >= 99 ? tr.i18nc("battery: no current flowing, charged", "full")
                              : tr.i18nc("battery: no current flowing", "idle")
        else if (rate > 0)
            s = tr.i18nc("battery: charging; the power and the time to full",
                         "charging  %1 W  %2 to full",
                         comma(w, 1), hoursMinutes((capacity - charge) / w * 3600))
        else
            s = tr.i18nc("battery: discharging; the power and the time left",
                         "discharging  %1 W  %2 left",
                         comma(w, 1), hoursMinutes(charge / w * 3600))
        if (health >= 0)
            s += "  " + tr.i18nc("battery: wear, a percentage", "health %1", Math.round(health) + "%")
        return s
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

    function serviceText(r) {
        const f = r.fields
        switch (r.label) {
        case "docker":
            return f[0] === "noaccess"
                ? tr.i18nc("docker: the user is not in the docker group yet", "needs re-login")
                : tr.i18nc("docker: running containers of all containers", "%1 of %2",
                           f[0], f[1])
        case "ollama":
            return f[0] === "model"
                ? f[1]
                : tr.i18ncp("ollama: no model loaded; how many are installed",
                            "idle, %1 model", "idle, %1 models", Number(f[1]) || 0)
        case "pacman":
            return tr.i18ncp("pacman: pending updates", "%1 update", "%1 updates",
                             Number(f[0]) || 0)
        }
        return f.join(" ")
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
                // The names follow the locale; the order is the translation's to set.
                const d = new Date().toLocaleDateString(Qt.locale(),
                    tr.i18nc("date line: a Qt date pattern, no year", "dddd, MMMM d"))
                out.push(line(d.charAt(0).toUpperCase() + d.slice(1), "value"))
                break
            }
            case "os":
                out.push(line((sval("os/system/name") || "") + "  " + (sval("os/kernel/version") || ""), "dim"))
                break

            case "separator": {
                // Blocks that hide themselves would leave two of these in a row, or one at
                // the top: only between two neighbours that show something. The trailing
                // one goes after the loop.
                if (out.length === 0 || out[out.length - 1].separator) break
                const s = line("-".repeat(35), "dim")
                s.separator = true
                out.push(s)
                break
            }

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

            case "pressure": {
                if (!hasPressure) break
                out.push(line(barRow("PSI", num("pressure/cpu/some10Sec", 0))))
                out.push(line(barRow("mem", num("pressure/memory/some10Sec", 0))))
                out.push(line(barRow("io ", num("pressure/io/some10Sec", 0))))
                // Full stalls are usually well under 1%, hence one decimal.
                if (p.full === true)
                    out.push(line(tr.i18nc("pressure: time every task stalled, memory and I/O",
                                           "full  mem %1  io %2",
                                           comma(num("pressure/memory/full10Sec", 0), 1) + "%",
                                           comma(num("pressure/io/full10Sec", 0), 1) + "%"), "dim"))
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
                        out.push(line(m.split("/").pop() + " | "
                                      + tr.i18nc("disks: a configured mount point is absent",
                                                 "not mounted"), "dim"))
                }
                break
            }

            case "uptime":
                out.push(line(tr.i18nc("uptime line", "uptime %1",
                                       human(num("os/system/uptime", 0)))))
                break

            case "network": {
                // netIface already honours p.interface and falls back to discovery.
                const iface = netIface
                out.push(line(iface + "  Dl " + speed(num("network/" + iface + "/download", 0))
                              + "  Ul " + speed(num("network/" + iface + "/upload", 0)), "dim"))
                break
            }

            case "battery": {
                // No battery, no lines. Mice, headsets and UPSes register here too, under
                // serials rather than names: only one with a capacity in Wh is shown, and
                // all are subscribed, because the capacity is readable only when subscribed.
                const real = batteries.filter(b => num("power/" + b + "/capacity", 0) > 0)
                for (let i = 0; i < real.length; i++) {
                    const id = "power/" + real[i] + "/"
                    const percent = num(id + "chargePercentage", 0)
                    out.push(line(barRow(real.length > 1 ? "BT" + i : "BAT", percent)))
                    out.push(line(batteryText(percent, num(id + "chargeRate", 0),
                                              num(id + "charge", 0), num(id + "capacity", 0),
                                              num(id + "health", -1)), "dim"))
                }
                break
            }

            case "services":
                for (const s of serviceRows) out.push(kvLine(s.label, serviceText(s)))
                break

            case "health": {
                const h = healthData
                if (p.units !== false && h.failed) {
                    const zero = h.failed[0] === "0" && h.failed[1] === "0"
                    out.push(kvLine(tr.i18nc("health: failed systemd units", "failed units"),
                                    zero ? "0" : tr.i18nc("health: a count for the system and one for the user session",
                                                          "%1 system, %2 user", h.failed[0], h.failed[1])))
                }
                if (p.errors !== false && h.err) {
                    out.push(kvLine(tr.i18nc("health: journal entries of priority error or worse", "errors since boot"),
                                    h.err[0] === "noaccess"
                                        ? tr.i18nc("health: the system journal cannot be read by this user", "no access")
                                        : tr.i18nc("health: a count for the system and one for the user session",
                                                   "%1 system, %2 user", h.err[0], h.err[1] || "0")))
                }
                const n = p.lines === undefined ? 3 : Math.max(0, Number(p.lines) || 0)
                for (const l of (h.lines || []).slice(0, n))
                    out.push(line(clip((l.ident ? l.ident + "  " : "") + l.text), "dim"))
                break
            }

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
        if (out.length > 0 && out[out.length - 1].separator) out.pop()
        return out
    }
}
