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
    // Off, nothing is subscribed and no process list is read: the line stand
    // (tests/monitor.qml) pushes values in through publish() and must not have the
    // machine's own readings land on top of them.
    property bool liveSensors: true

    // ⚠️ Path set by the host: the script sits in contents/code/ inside the plasmoid
    // package and next to the QML in the standalone host, so a relative guess here left
    // the services block silently empty in one of the two.
    property string servicesScript: Qt.resolvedUrl("services.sh").toString().replace("file://", "")
    property string healthScript: Qt.resolvedUrl("health.sh").toString().replace("file://", "")

    // Width of the text area in characters, set by the host from its width and font: the
    // one place free text (journal messages) is cut. The tabular lines are built to fit.
    // With a second column in use, `columns` is the first column's width up to it and
    // `columns2` the second's to the right edge.
    property int columns: 57
    property int columns2: 57

    // Bars and separators, from the general settings: a bar's width in characters and the
    // two characters it is made of (PlainExt's slash and a space), the separator's
    // character and width. An empty character means the default.
    property int barWidth: 18
    property string barFill: "/"
    property string barEmpty: ""
    property string separatorChar: "-"
    property int separatorWidth: 35
    // Sparklines: the glyphs the "history" parameter draws with, lowest to highest.
    property string sparkGlyphs: "▁▂▃▄▅▆▇█"

    // Active lines. On, a line that has something to do carries an `action` — a title
    // and a list of items, the first of them what a left click runs, all of them the
    // right-click menu; the view draws such a line with a mouse area, the host runs the
    // items. Off, no line carries one and the widget takes no clicks of its own. A block
    // opts out with its "active" field (false); its "click" field is a command of the
    // user's own, put first, with {name} {pid} {path} {unit} {value} filled in per row.
    property bool actions: true

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

    // The scripts beside services.sh, one source per block with its own interval, read
    // like the custom commands: the output lands in cmdOut under the block's id.
    readonly property string codeDir: servicesScript.replace(/\/[^/]*$/, "")

    function quoted(list) {
        return (list || []).map(x => "'" + String(x).replace(/'/g, "'\\''") + "'").join(" ")
    }

    readonly property var scriptBlocks: {
        const out = []
        for (const b of blocks) {
            if (b.enabled === false) continue
            const p = b.params || {}
            const every = sec => Math.max(1, Number(p.interval) || sec)
            switch (b.type) {
            case "units":
                if ((p.units || []).length > 0)
                    out.push({ id: b.id, interval: every(15),
                               command: "bash " + codeDir + "/units.sh " + (p.user === true ? "--user " : "")
                                        + quoted(p.units) })
                break
            case "peripherals":
                out.push({ id: b.id, interval: every(30), command: "bash " + codeDir + "/peripherals.sh" })
                break
            case "sound":
                out.push({ id: b.id, interval: every(5),
                           command: "bash " + codeDir + "/sound.sh" + (p.input === true ? " input" : "") })
                break
            case "repos":
                if ((p.paths || []).length > 0)
                    out.push({ id: b.id, interval: every(60),
                               command: "bash " + codeDir + "/repos.sh " + quoted(p.paths) })
                break
            }
        }
        return out
    }

    property var cmdOut: ({})

    Instantiator {
        model: monitor.commandBlocks.concat(monitor.scriptBlocks)

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

    // The cores' frequencies only when the model line shows them: one more sensor per
    // core, and the model handles hundreds, but not for a line nobody asked for.
    readonly property bool wantFrequency: hasBlock("cpu")
        && blockParam("cpu", "model_line", true) !== false
        && blockParam("cpu", "frequency", true) !== false

    readonly property var coreIds: {
        const a = []
        for (let i = 0; i < coreCount; i++) a.push("cpu/cpu" + i + "/usage")
        for (let i = 0; i < coreCount; i++) a.push("cpu/cpu" + i + "/temperature")
        if (wantFrequency)
            for (let i = 0; i < coreCount; i++) a.push("cpu/cpu" + i + "/frequency")
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
    // `names` keeps each sensor's own display name — "Tctl", "Composite" — for the blocks
    // that print a sensor the user picked without a label of their own.
    property var named: ({})
    property var namedReady: ({})
    property var names: ({})

    function publish(id, value, ready, name) {
        named[id] = value
        namedReady[id] = ready
        if (name !== undefined && String(name).length > 0)
            names[id] = String(name)
    }

    Instantiator {
        model: monitor.liveSensors ? monitor.namedIds : []

        delegate: Sensors.Sensor {
            required property var modelData
            sensorId: modelData
            updateRateLimit: monitor.rate
            // ⚠️ A bare `name` here is the sensor's own display name (docs/GOTCHAS.md).
            onValueChanged: monitor.publish(sensorId, value, status === 2, name)
            onStatusChanged: monitor.publish(sensorId, value, status === 2, name)
        }
    }

    // Graphics cards: whatever the gpu plugin lists, sorted so the order holds; none on a
    // machine without one — a VM, a headless box — and the block hides with them, as the
    // battery does. The spec sheet needs only their names.
    readonly property var gpus: (hasBlock("gpu") || hasBlock("passport"))
        ? registry.match("^gpu/gpu\\d+/usage$").map(id => id.split("/")[1]).sort()
        : []
    readonly property var gpuIds: {
        const out = []
        const keys = hasBlock("gpu") ? ["usage", "temperature", "usedVram", "totalVram", "power", "name"] : ["name"]
        for (const g of gpus) {
            for (const k of keys)
                out.push("gpu/" + g + "/" + k)
            // amdgpu leaves "power" empty and reports the package power as "power1" (PPT,
            // the figure `sensors` shows); read it only where the plugin lists it.
            if (hasBlock("gpu") && registry.match("^gpu/" + g + "/power1$").length > 0)
                out.push("gpu/" + g + "/power1")
        }
        return out
    }

    // Swap: the percentage is computed from used and total, so a machine without swap
    // (total 0) simply shows no lines.
    readonly property var swapIds: hasBlock("swap") ? ["memory/swap/used", "memory/swap/total"] : []

    // The network block's optional second line: only the sensors it was asked for.
    readonly property var netExtraIds: {
        const out = []
        if (!hasBlock("network") || netIface.length === 0)
            return out
        if (blockParam("network", "address", false) === true)
            out.push("network/" + netIface + "/ipv4address")
        if (blockParam("network", "totals", false) === true)
            out.push("network/" + netIface + "/totalDownload", "network/" + netIface + "/totalUpload")
        if (blockParam("network", "signal", false) === true)
            out.push("network/" + netIface + "/signal")
        return out
    }

    // Load averages: the cpu plugin's, when it has them; else /proc/loadavg below.
    readonly property bool hasLoadSensors: hasBlock("load") && registry.has("cpu/loadaverages/loadaverage1")
    readonly property var loadIds: hasLoadSensors
        ? ["cpu/loadaverages/loadaverage1", "cpu/loadaverages/loadaverage5", "cpu/loadaverages/loadaverage15"]
        : []
    property var loadFile: []

    P5Support.DataSource {
        engine: "executable"
        interval: 5000
        connectedSources: (monitor.hasBlock("load") && !monitor.hasLoadSensors) ? ["cat /proc/loadavg"] : []
        onNewData: function(source, data) {
            const f = String(data.stdout).trim().split(/\s+/)
            if (f.length >= 3)
                monitor.loadFile = [Number(f[0]), Number(f[1]), Number(f[2])]
        }
    }

    // Disk I/O: the read/write pair the block follows — the preference when the machine
    // has it, else the plugin's "all", else the first disk listed. The write id is the
    // read id's sibling.
    readonly property string diskReadId: !hasBlock("diskio") ? ""
        : (registry.resolve(blockParam("diskio", "disk", ""), "^disk/all/read$")
           || registry.firstMatch("^disk/[^/]+/read$"))
    readonly property string diskWriteId: diskReadId.replace(/read$/, "write")
    readonly property var diskIoIds: diskReadId.length > 0 ? [diskReadId, diskWriteId] : []

    // Temperatures: a list of sensor ids, each optionally "label=id"; without a label the
    // sensor's own name is printed.
    function tempId(entry) {
        const t = String(entry), i = t.indexOf("=")
        return (i >= 0 ? t.slice(i + 1) : t).trim()
    }
    function tempLabel(entry) {
        const t = String(entry), i = t.indexOf("=")
        return i >= 0 ? t.slice(0, i).trim() : ""
    }
    // Every enabled temperatures block's sensors, with duplicates: namedIds removes them.
    readonly property var tempIds: {
        const out = []
        for (const b of blocks) {
            if (b.type !== "temps" || b.enabled === false) continue
            const list = (b.params || {}).sensors || []
            for (let i = 0; i < list.length; i++) {
                const id = tempId(list[i])
                if (id.length > 0) out.push(id)
            }
        }
        return out
    }

    readonly property var rawSensorIds: [
        "cpu/all/usage",
        "memory/physical/usedPercent", "memory/physical/used", "memory/physical/total",
        "os/system/hostname", "os/system/name", "os/kernel/version",
        "cpu/all/cpuCount", "cpu/all/coreCount",
        "network/" + netIface + "/download", "network/" + netIface + "/upload",
        "os/system/uptime"
    ].concat(customSensorIds).concat(fanSensors).concat(
        nvmeSensor.length > 0 ? [nvmeSensor] : []).concat(pressureIds).concat(batteryIds)
        .concat(gpuIds).concat(swapIds).concat(netExtraIds).concat(loadIds).concat(diskIoIds).concat(tempIds)

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
        sensors: monitor.liveSensors ? monitor.sensorIds : []
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
        // "pid" is the fourth column: the process rows' actions need it. Its absence
        // (an older libksysguard) costs only those actions.
        enabledAttributes: ["name", "usage", "memory", "pid"]
        enabled: monitor.liveSensors && monitor.needProcesses && (!monitor.processDuty || monitor.processAwake)
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
            // DMI on a PC; on an ARM board there is no DMI, and the device tree names the
            // model in one NUL-terminated line.
            "cat /sys/devices/virtual/dmi/id/board_vendor /sys/devices/virtual/dmi/id/board_name /sys/devices/virtual/dmi/id/bios_version 2>/dev/null || tr -d '\\0' < /proc/device-tree/model 2>/dev/null"
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
            const l = out.trim().split("\n").filter(x => x.trim().length > 0)
            if (l.length >= 3) monitor.boardLine = l[0] + " " + l[1] + "  (BIOS " + l[2] + ")"
            else if (l.length > 0) monitor.boardLine = l.join(" ")
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
            // ⚠️ Under a timeout: a network mount that stopped answering hangs df, and with
            // it this source — the other lines went on, this block froze.
            "timeout 5 df -B1 --output=target,size,used,pcent " + monitor.mounts.join(" ") + " 2>/dev/null"
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
            const h = { failed: null, err: null, lines: [], reboot: false }
            for (const row of String(data.stdout).trim().split("\n")) {
                const f = row.split("|")
                if (f[0] === "reboot") h.reboot = f[1] === "yes"
                else if (f[0] === "failed" && f.length >= 3) h.failed = [f[1], f[2]]
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
        onTriggered: {
            monitor.sample()
            monitor.tick++
        }
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
    function bar(pct, width) {
        const w = width || barWidth
        const k = Math.max(0, Math.min(w, Math.round(pct * w / 100)))
        const fill = Array.from(barFill)[0] || "/"
        const empty = Array.from(barEmpty)[0] || " "
        return fill.repeat(k) + empty.repeat(w - k)
    }

    function pct(v) {
        return String(Math.round(v)).padStart(3) + "%"
    }

    // The label is exactly three characters — otherwise the percent column wanders
    // with the label length.
    // The label is three characters; a wider label (the disks use four: "root", "home")
    // takes its extra characters from the bar, so the percentage column stays aligned.
    // The percentage is a part of its own in the value colour, so the numbers stand out
    // of the column; `tail` follows it in the main colour.
    function barRow(label, value, labelWidth, tail) {
        const lw = labelWidth || 3
        const parts = [
            { text: String(label).padEnd(lw).slice(0, lw) + " " + bar(value, Math.max(4, barWidth - (lw - 3))) + " ", role: "fg" },
            { text: pct(value), role: "value" }
        ]
        if (tail) parts.push({ text: tail, role: "fg" })
        return { kind: "parts", parts: parts }
    }

    // A line that turns accent past its threshold (0: never) — the one place the monitor
    // says "look here" rather than just reporting. Takes text or a line of parts (a bar
    // row); past the threshold every part turns accent, the value included.
    function warnLine(row, value, warn, role) {
        const hot = warn > 0 && value >= warn
        if (typeof row === "object")
            return hot ? tint(row, "accent") : row
        return line(row, hot ? "accent" : (role || "fg"))
    }

    // The same line with every part in one role.
    function tint(row, role) {
        return { kind: "parts", parts: row.parts.map(part => ({ text: part.text, role: role })) }
    }

    // Bytes as a size: GiB with a decimal from a gibibyte up, MiB below, KiB below that.
    function bytes(n) {
        if (n >= 1073741824) return gib(n)
        if (n >= 1048576) return Math.round(n / 1048576) + " MiB"
        return Math.round(n / 1024) + " KiB"
    }

    // ── Sparklines ────────────────────────────────────────────────────────────
    // The last `history` samples of a block's value, one per tick, drawn as glyphs after
    // its bar. Sampled on the tick, before the rebuild — a binding must not keep state.
    // The map is mutated in place for the same reason the sensor maps are.
    property var hist: ({})

    function remember(key, value, keep) {
        const a = hist[key] || (hist[key] = [])
        a.push(value)
        while (a.length > keep) a.shift()
    }

    // `max` scales the glyphs — 100 for a percentage; 0 scales to the window's own peak,
    // for rates. Left-padded to `width`, so the line keeps its length while it fills.
    function spark(key, width, max) {
        const glyphs = Array.from(sparkGlyphs)
        const values = hist[key] || []
        if (glyphs.length === 0 || width <= 0)
            return ""
        let top = max
        if (!(top > 0)) {
            top = 1
            for (const v of values) if (v > top) top = v
        }
        // Glyph i fills (i + 1)/n of the cell, so a value takes the lowest glyph that
        // reaches it: half is "▄", not the rounded-up "▅"; zero still shows the lowest.
        const n = glyphs.length
        const shown = values.slice(-width)
        let out = " ".repeat(Math.max(0, width - shown.length))
        for (const v of shown)
            out += glyphs[Math.max(0, Math.ceil(Math.max(0, Math.min(1, v / top)) * n) - 1)]
        return out
    }

    // "  ▁▂▃▅▇" after a bar, or nothing while the block keeps no history.
    function sparkTail(key, p, max) {
        const keep = Math.max(0, Number(p.history) || 0)
        return keep > 0 ? "  " + spark(key, keep, max) : ""
    }

    // What each block's history follows; run on every tick before the lines are rebuilt.
    function sample() {
        for (const b of blocks) {
            if (b.enabled === false) continue
            const p = b.params || {}
            const keep = Math.max(0, Number(p.history) || 0)
            if (keep === 0) continue
            switch (b.type) {
            case "cpu": remember(b.id, num("cpu/all/usage", 0), keep); break
            case "memory": remember(b.id, num("memory/physical/usedPercent", 0), keep); break
            case "swap": remember(b.id, swapPercent(), keep); break
            case "pressure": remember(b.id, num("pressure/cpu/some10Sec", 0), keep); break
            case "gpu":
                for (const g of gpus) remember(b.id + ":" + g, num("gpu/" + g + "/usage", 0), keep)
                break
            case "network":
                remember(b.id, num("network/" + netIface + "/download", 0)
                               + num("network/" + netIface + "/upload", 0), keep)
                break
            case "diskio":
                remember(b.id, num(diskReadId, 0) + num(diskWriteId, 0), keep)
                break
            case "sensor": remember(b.id, num(p.id, 0), keep); break
            }
        }
    }

    function swapPercent() {
        const total = num("memory/swap/total", 0)
        return total > 0 ? num("memory/swap/used", 0) * 100 / total : 0
    }

    function avgFrequency() {
        let sum = 0, cnt = 0
        for (let i = 0; i < coreCount; i++) {
            const f = num("cpu/cpu" + i + "/frequency", 0)
            if (f > 0) { sum += f; cnt++ }
        }
        return cnt > 0 ? sum / cnt / 1000 : 0      // MHz → GHz
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

    // Free text is cut at the column's width with an ellipsis.
    function clipText(text, width) {
        const w = width || columns
        return text.length > w ? text.slice(0, Math.max(0, w - 1)) + "…" : text
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

    // Process rows: the name in the main colour, the figure as a value, as in the bar rows.
    // Each row's action names the process and, with a pid, can end it.
    function topRows(model, column, count, format, block) {
        const out = []
        const n = Math.min(count, model.rowCount())
        for (let i = 0; i < n; i++) {
            const name = String(model.data(model.index(i, 0), Proc.ProcessDataModel.Value) || "")
            const v = model.data(model.index(i, column), Proc.ProcessDataModel.Value)
            const pid = Math.round(Number(model.data(model.index(i, 3), Proc.ProcessDataModel.Value)) || 0)
            const row = { kind: "parts", parts: [
                { text: name.slice(0, 20).padEnd(21) + "| ", role: "fg" },
                { text: format(Number(v) || 0), role: "value" }
            ] }
            out.push(attach(row, block, pid > 0 ? name + " " + pid : name, processItems(name, pid),
                            { name: name, pid: pid, value: Number(v) || 0 }))
        }
        return out
    }

    // ── Active lines ──────────────────────────────────────────────────────────
    // A line's action is {title, items}; an item is {text, run, terminal, hold, gui,
    // editor, confirm} — a shell command for the host to run: in a terminal (held open
    // after it ends when `hold`), detached as a GUI program, as the editor's argument,
    // or after a question — or {text, configure: true} for the widget's own settings.
    // The host owns the terminal and editor commands; this side only knows what a row is
    // about. Nothing is attached while `actions` is off or the block's "active" field
    // says false; a block's "click" command, when set, becomes the first item.
    function sh(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }
    // A path argument, quoted; a leading ~ is left to the shell as $HOME.
    function pathArg(p) {
        const s = String(p)
        return s.startsWith("~") ? '"$HOME"' + sh(s.slice(1)) : sh(s)
    }
    function item(text, run, opts) {
        const o = opts || {}
        return { text: text, run: run, terminal: o.terminal === true, hold: o.hold === true,
                 gui: o.gui === true, editor: o.editor === true, confirm: o.confirm === true }
    }
    // "{name}" and the like in the user's own command, from the row's values.
    function fill(template, vars) {
        return String(template).replace(/\{(\w+)\}/g,
            (m, k) => (vars && vars[k] !== undefined) ? String(vars[k]) : m)
    }
    function attach(row, block, title, items, vars) {
        if (!actions || !row || !block || block.active === false)
            return row
        const list = (items || []).slice()
        const custom = String(block.click || "").trim()
        if (custom.length > 0)
            list.unshift(item(tr.i18nc("line action: the block's own command", "run %1", clipText(custom, 30)),
                              fill(custom, vars)))
        if (list.length > 0)
            row.action = { title: String(title || ""), items: list }
        return row
    }
    function monitorItem() {
        return item(tr.i18nc("line action: open Plasma's System Monitor", "System Monitor"),
                    "plasma-systemmonitor", { gui: true })
    }
    function infoItem() {
        return item(tr.i18nc("line action: open Plasma's Info Center", "system information"), "kinfocenter", { gui: true })
    }
    function settingsItem(kcm, text) {
        return item(text, "kcmshell6 " + kcm, { gui: true })
    }
    function clockItem() {
        return settingsItem("kcm_clock", tr.i18nc("line action", "date and time settings"))
    }
    function terminalAt(path) {
        return item(tr.i18nc("line action", "open in a terminal"),
                    "cd " + pathArg(path) + ' && exec "${SHELL:-sh}"', { terminal: true })
    }
    function openItem(path) {
        return item(tr.i18nc("line action", "open in the file manager"), "xdg-open " + pathArg(path), { gui: true })
    }
    function diskItems(target) {
        return [openItem(target), terminalAt(target), monitorItem()]
    }
    function powerItems() {
        return [item(tr.i18nc("line action", "lock the screen"), "loginctl lock-session"),
                item(tr.i18nc("line action", "log out"),
                     "qdbus6 org.kde.Shutdown /Shutdown logout 2>/dev/null || qdbus org.kde.Shutdown /Shutdown logout",
                     { confirm: true }),
                item(tr.i18nc("line action", "reboot"), "systemctl reboot", { confirm: true }),
                item(tr.i18nc("line action", "power off"), "systemctl poweroff", { confirm: true })]
    }
    function processItems(name, pid) {
        const out = []
        if (pid > 0) {
            out.push(item(tr.i18nc("line action: send SIGTERM to the process", "terminate %1", name),
                          "kill -TERM " + pid, { confirm: true }))
            out.push(item(tr.i18nc("line action: send SIGKILL to the process", "kill %1", name),
                          "kill -KILL " + pid, { confirm: true }))
        }
        out.push(monitorItem())
        return out
    }
    function updateItem(cmd) {
        return item(tr.i18nc("line action: the package manager's update in a terminal", "update in a terminal"),
                    cmd, { terminal: true, hold: true })
    }
    function serviceItems(label) {
        switch (label) {
        case "docker":
        case "podman":
            return [item(tr.i18nc("line action: list the containers in a terminal", "containers in a terminal"),
                         label + " ps -a", { terminal: true, hold: true })]
        case "ollama":
            return [item(tr.i18nc("line action: list ollama's models in a terminal", "models in a terminal"),
                         "ollama ps; ollama list", { terminal: true, hold: true })]
        case "libvirt":
            return [item(tr.i18nc("line action: open virt-manager", "Virtual Machine Manager"), "virt-manager", { gui: true })]
        case "pacman": return [updateItem("sudo pacman -Syu")]
        case "apt": return [updateItem("sudo apt update && sudo apt upgrade")]
        case "dnf": return [updateItem("sudo dnf upgrade")]
        case "zypper": return [updateItem("sudo zypper update")]
        case "flatpak": return [updateItem("flatpak update")]
        }
        return []
    }
    function unitItems(unit, user) {
        const ctl = "systemctl " + (user ? "--user " : "")
        return [item(tr.i18nc("line action: systemctl status in a terminal", "status"), ctl + "status " + sh(unit), { terminal: true }),
                item(tr.i18nc("line action: systemctl start", "start"), ctl + "start " + sh(unit), { confirm: true }),
                item(tr.i18nc("line action: systemctl stop", "stop"), ctl + "stop " + sh(unit), { confirm: true }),
                item(tr.i18nc("line action: systemctl restart", "restart"), ctl + "restart " + sh(unit), { confirm: true }),
                item(tr.i18nc("line action: the unit's journal in a terminal", "journal"),
                     "journalctl " + (user ? "--user " : "") + "-e -u " + sh(unit), { terminal: true })]
    }
    function soundItems(input, muted) {
        const node = input ? "@DEFAULT_AUDIO_SOURCE@" : "@DEFAULT_AUDIO_SINK@"
        return [item(muted ? tr.i18nc("line action", "unmute") : tr.i18nc("line action", "mute"),
                     "wpctl set-mute " + node + " toggle"),
                settingsItem("kcm_pulseaudio", tr.i18nc("line action", "sound settings"))]
    }
    function repoItems(path) {
        return [terminalAt(path), openItem(path),
                item(tr.i18nc("line action", "open in the editor"), pathArg(path), { editor: true }),
                item(tr.i18nc("line action: git pull in a terminal", "git pull"),
                     "cd " + pathArg(path) + " && git pull", { terminal: true, hold: true })]
    }
    function journalItem(ident) {
        return ident.length > 0
            ? item(tr.i18nc("line action: this program's journal in a terminal", "journal of %1", ident),
                   "journalctl -b -e -t " + sh(ident), { terminal: true })
            : item(tr.i18nc("line action: the journal's errors in a terminal", "errors in a terminal"),
                   "journalctl -p err -b -e", { terminal: true })
    }

    // ── Building lines from the description ───────────────────────────────────
    // A line is a set of parts with one common font size; the clock stands apart
    // because it has two different font sizes on one baseline.
    function line(text, role) {
        return { kind: "parts", parts: [{ text: text, role: role || "fg" }] }
    }

    function kvLine(label, value, role) {
        return { kind: "parts", parts: [
            { text: String(label).padEnd(21), role: "dim" },
            { text: "| " + value, role: role || "fg" }
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
        case "podman":
            return f[0] === "noaccess"
                ? tr.i18nc("podman: it cannot be reached", "no access")
                : tr.i18nc("docker: running containers of all containers", "%1 of %2",
                           f[0], f[1])
        case "libvirt":
            return tr.i18nc("libvirt: running virtual machines of all", "%1 of %2", f[0], f[1])
                + (f[2] ? "  " + f[2] : "")
        case "pacman":
        case "apt":
        case "dnf":
        case "zypper":
        case "flatpak":
            return tr.i18ncp("pacman: pending updates", "%1 update", "%1 updates",
                             Number(f[0]) || 0)
        }
        return f.join(" ")
    }

    // A systemd unit's state, as a word.
    function unitState(state) {
        switch (state) {
        case "active": return tr.i18nc("systemd unit state", "active")
        case "inactive": return tr.i18nc("systemd unit state", "inactive")
        case "failed": return tr.i18nc("systemd unit state", "failed")
        case "activating": return tr.i18nc("systemd unit state", "starting")
        case "deactivating": return tr.i18nc("systemd unit state", "stopping")
        case "reloading": return tr.i18nc("systemd unit state", "reloading")
        default: return state.length > 0 ? state : tr.i18nc("systemd unit state: no answer", "unknown")
        }
    }

    // Blocks go to the second column by their "column" field; the first takes the rest.
    // Loops, not Array methods: `blocks` comes from the host and need not be a JS array.
    function inColumn(second) {
        const out = []
        for (const b of blocks)
            if ((Number(b.column) === 2) === second)
                out.push(b)
        return out
    }
    readonly property bool twoColumns: {
        for (const b of blocks)
            if (b.enabled !== false && Number(b.column) === 2)
                return true
        return false
    }
    readonly property var lines: { tick; return buildLines(inColumn(false), columns) }
    readonly property var lines2: { tick; return buildLines(inColumn(true), columns2) }

    // The lines of one column: every property read here is read inside a binding on
    // `lines` or `lines2`, so the dependencies are tracked as before.
    function buildLines(list, width) {
        const out = []
        const clip = text => clipText(text, width)

        for (const b of list) {
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
                    out.push(attach(line(head, "accent"), b, head,
                                    [{ text: tr.i18nc("line action: open the widget's settings dialog", "settings…"),
                                       configure: true }], {}))
                break
            }
            case "clock": {
                // 24-hour unless asked otherwise; "locale" reads the locale's short time
                // format and takes an AM/PM marker in it as the twelve-hour clock.
                const d = new Date()
                const twelve = p.format === "12h"
                    || (p.format === "locale" && /ap/i.test(Qt.locale().timeFormat(Locale.ShortFormat)))
                const big = Qt.formatTime(d, twelve ? "h:mm" : "HH:mm")
                let small = p.seconds === false ? "" : Qt.formatTime(d, ":ss")
                if (twelve)
                    small += " " + Qt.formatTime(d, "AP")
                out.push(attach({ kind: "clock", big: big, small: small }, b, big, [clockItem()], {}))
                break
            }
            case "date": {
                // ⚠️ Qt.formatDate takes the C locale and produces "Sunday, 20 September"
                // even under ru_RU. Only toLocaleDateString gives the Russian names.
                // The names follow the locale; the order is the translation's to set.
                const d = new Date().toLocaleDateString(Qt.locale(),
                    tr.i18nc("date line: a Qt date pattern, no year", "dddd, MMMM d"))
                const text = d.charAt(0).toUpperCase() + d.slice(1)
                out.push(attach(line(text, "value"), b, text, [clockItem()], {}))
                break
            }
            case "os": {
                const name = String(sval("os/system/name") || "")
                out.push(attach(line(name + "  " + (sval("os/kernel/version") || ""), "dim"), b, name, [infoItem()], {}))
                break
            }

            case "separator": {
                // Blocks that hide themselves would leave two of these in a row, or one at
                // the top: only between two neighbours that show something. The trailing
                // one goes after the loop.
                if (out.length === 0 || out[out.length - 1].separator) break
                const s = line((Array.from(separatorChar)[0] || "-").repeat(Math.max(1, separatorWidth)), "dim")
                s.separator = true
                out.push(s)
                break
            }

            case "cpu": {
                const usage = num("cpu/all/usage", 0)
                const warn = Number(p.warn) || 0
                out.push(attach(warnLine(barRow("CPU", usage, 3, sparkTail(b.id, p, 100)), usage, warn),
                                b, "CPU", [monitorItem()], { value: Math.round(usage) }))
                // One node is the whole machine: its line would only repeat the one above.
                if (p.per_socket !== false && nodeCpus.length > 1) {
                    for (let n = 0; n < nodeCpus.length; n++) {
                        const u = nodeUsage(n)
                        out.push(attach(warnLine(barRow("S" + n, u, 3, "   node" + n), u, warn),
                                        b, "S" + n, [monitorItem()], { value: Math.round(u) }))
                    }
                }
                if (p.model_line !== false) {
                    const name = (cpuSockets > 1 ? cpuSockets + "x " : "") + (cpuModel || "CPU")
                    // Only the nodes the machine has: with two read unconditionally, a
                    // one-node machine printed "62/0°C" (fixed 2026-10-04).
                    const temps = []
                    for (let n = 0; n < nodeCpus.length; n++) {
                        const t = Math.round(nodeTemp(n))
                        if (t > 0) temps.push(t)
                    }
                    const rpm = []
                    for (const id of fanSensors) {
                        const v = Math.round(num(id, 0))
                        if (v > 0) rpm.push(v)
                    }
                    const ghz = p.frequency === false ? 0 : avgFrequency()
                    const hot = temps.length > 0 ? Math.max(...temps) : 0
                    out.push(attach(warnLine(name + "  " + cpuCores + "c/" + cpuThreads + "t  "
                                             + (ghz > 0 ? comma(ghz, 1) + " GHz  " : "")
                                             + (temps.length > 0 ? temps.join("/") + "°C  " : "")
                                             + (rpm.length > 0 ? rpm.join("/") + " rpm" : ""),
                                             hot, Number(p.warn_temp) || 0, "dim"),
                                    b, name, [monitorItem()], { value: hot }))
                }
                for (const r of topRows(byCpu, 1, p.top_processes || 0, v => comma(v, 1) + "%", b))
                    out.push(r)
                break
            }

            case "load": {
                const v = hasLoadSensors
                    ? [num(loadIds[0], 0), num(loadIds[1], 0), num(loadIds[2], 0)]
                    : loadFile
                if (v.length < 3) break
                // The threshold is a share of the core count: 100 means as many runnable
                // tasks as cores.
                const warn = Number(p.warn) || 0
                const share = coreCount > 0 ? v[0] * 100 / coreCount : 0
                out.push(attach(warnLine(tr.i18nc("load average over 1, 5 and 15 minutes", "load %1  %2  %3",
                                                  comma(v[0], 2), comma(v[1], 2), comma(v[2], 2)),
                                         share, warn, "dim"),
                                b, "load", [monitorItem()], { value: comma(v[0], 2) }))
                break
            }

            case "pressure": {
                if (!hasPressure) break
                const warn = Number(p.warn) || 0
                const psi = num("pressure/cpu/some10Sec", 0)
                const mem = num("pressure/memory/some10Sec", 0)
                const io = num("pressure/io/some10Sec", 0)
                out.push(attach(warnLine(barRow("PSI", psi, 3, sparkTail(b.id, p, 100)), psi, warn),
                                b, "PSI", [monitorItem()], { value: Math.round(psi) }))
                out.push(attach(warnLine(barRow("mem", mem), mem, warn), b, "mem", [monitorItem()], { value: Math.round(mem) }))
                out.push(attach(warnLine(barRow("io ", io), io, warn), b, "io", [monitorItem()], { value: Math.round(io) }))
                // Full stalls are usually well under 1%, hence one decimal.
                if (p.full === true)
                    out.push(attach(line(tr.i18nc("pressure: time every task stalled, memory and I/O",
                                                  "full  mem %1  io %2",
                                                  comma(num("pressure/memory/full10Sec", 0), 1) + "%",
                                                  comma(num("pressure/io/full10Sec", 0), 1) + "%"), "dim"),
                                    b, "PSI", [monitorItem()], {}))
                break
            }

            case "memory": {
                const used = num("memory/physical/usedPercent", 0)
                out.push(attach(warnLine(barRow("RAM", used, 3, sparkTail(b.id, p, 100)), used, Number(p.warn) || 0),
                                b, "RAM", [monitorItem()], { value: Math.round(used) }))
                if (p.totals !== false)
                    out.push(attach(line(gib(num("memory/physical/used", 0)) + " / "
                                         + gib(num("memory/physical/total", 0)), "dim"),
                                    b, "RAM", [monitorItem()], { value: Math.round(used) }))
                for (const r of topRows(byMem, 2, p.top_processes || 0, v => gib(v * 1024), b))
                    out.push(r)
                break
            }

            case "swap": {
                // No swap, no lines — as with no battery.
                const total = num("memory/swap/total", 0)
                if (!(total > 0)) break
                const used = swapPercent()
                out.push(attach(warnLine(barRow("SWP", used, 3, sparkTail(b.id, p, 100)), used, Number(p.warn) || 0),
                                b, "SWP", [monitorItem()], { value: Math.round(used) }))
                if (p.totals !== false)
                    out.push(attach(line(gib(num("memory/swap/used", 0)) + " / " + gib(total), "dim"),
                                    b, "SWP", [monitorItem()], { value: Math.round(used) }))
                break
            }

            case "gpu": {
                // Every card the plugin lists; none, and the block says nothing.
                const warn = Number(p.warn) || 0, warnTemp = Number(p.warn_temp) || 0
                for (let i = 0; i < gpus.length; i++) {
                    const id = "gpu/" + gpus[i] + "/"
                    const usage = num(id + "usage", 0)
                    const label = gpus.length > 1 ? "GP" + i : "GPU"
                    out.push(attach(warnLine(barRow(label, usage, 3,
                                                    sparkTail(b.id + ":" + gpus[i], p, 100)), usage, warn),
                                    b, label, [monitorItem()], { name: gpus[i], value: Math.round(usage) }))
                    if (p.details !== false) {
                        const t = Math.round(num(id + "temperature", 0))
                        const watts = num(id + "power", 0) || num(id + "power1", 0)
                        out.push(attach(warnLine("VRAM " + comma(num(id + "usedVram", 0) / 1073741824, 1)
                                                 + "/" + comma(num(id + "totalVram", 0) / 1073741824, 1)
                                                 + " GB  temp " + t + "°C  pwr " + Math.round(watts) + "W",
                                                 t, warnTemp, "dim"),
                                        b, label, [monitorItem()], { name: gpus[i], value: t }))
                    }
                }
                break
            }

            case "disks": {
                for (const d of diskRows) {
                    // The root mount is labelled "root", not "/": the bar beside it is made of slashes too,
                    // and "/   //" read as one thing. Other mounts keep their last path element.
                    const name = d.target === "/" ? "root" : d.target.split("/").pop()
                    const vars = { name: name, path: d.target, value: d.pct }
                    out.push(attach(warnLine(barRow(name, d.pct, 4), d.pct, Number(p.warn) || 0),
                                    b, d.target, diskItems(d.target), vars))
                    let note = "F: " + gib(d.size - d.used) + "  T: " + gib(d.size)
                    if (d.target === "/" && p.nvme_temp !== false) {
                        const t = nvmeSensor.length > 0 ? Math.round(num(nvmeSensor, 0)) : 0
                        if (t > 0) note += "  nvme " + t + "°C"
                    }
                    out.push(attach(line(note, "dim"), b, d.target, diskItems(d.target), vars))
                }
                // Configured but not mounted: say so instead of staying silent.
                for (const m of (p.mounts || [])) {
                    if (!diskRows.some(d => d.target === m))
                        out.push(line((m === "/" ? "root" : m.split("/").pop()) + " | "
                                      + tr.i18nc("disks: a configured mount point is absent",
                                                 "not mounted"), "dim"))
                }
                break
            }

            case "uptime": {
                // The session's own line: the power menu lives here, every step but the
                // lock behind a question.
                const text = tr.i18nc("uptime line", "uptime %1", human(num("os/system/uptime", 0)))
                out.push(attach(line(text), b, text, powerItems(), {}))
                break
            }

            case "network": {
                // netIface already honours p.interface and falls back to discovery.
                const iface = netIface
                const netItems = [settingsItem("kcm_networkmanagement", tr.i18nc("line action", "network settings")),
                                  item(tr.i18nc("line action: ip addr in a terminal", "addresses in a terminal"),
                                       "ip -c addr", { terminal: true, hold: true })]
                out.push(attach(line(iface + "  Dl " + speed(num("network/" + iface + "/download", 0))
                                     + "  Ul " + speed(num("network/" + iface + "/upload", 0))
                                     + sparkTail(b.id, p, 0), "dim"),
                                b, iface, netItems, { name: iface }))
                // The second line: the address, the totals since boot, the Wi-Fi signal —
                // each only when asked for and when the interface reports it.
                const extra = []
                if (p.address === true) {
                    const a = sval("network/" + iface + "/ipv4address")
                    if (a) extra.push(String(a))
                }
                if (p.totals === true)
                    extra.push(tr.i18nc("network: traffic since boot, down and up", "total %1 down, %2 up",
                                        bytes(num("network/" + iface + "/totalDownload", 0)),
                                        bytes(num("network/" + iface + "/totalUpload", 0))))
                if (p.signal === true && sensorReady("network/" + iface + "/signal"))
                    extra.push(tr.i18nc("network: Wi-Fi signal strength", "signal %1",
                                        Math.round(num("network/" + iface + "/signal", 0)) + "%"))
                if (extra.length > 0)
                    out.push(attach(line(clip(extra.join("  ")), "dim"), b, iface, netItems, { name: iface }))
                break
            }

            case "diskio": {
                if (diskReadId.length === 0) break
                out.push(attach(line(tr.i18nc("disk I/O: read and write rates", "I/O  R %1  W %2",
                                              speed(num(diskReadId, 0)), speed(num(diskWriteId, 0)))
                                     + sparkTail(b.id, p, 0), "dim"),
                                b, "I/O", [monitorItem()], { name: diskReadId.split("/")[1] || "" }))
                break
            }

            case "temps": {
                const warn = Number(p.warn) || 0
                for (const e of (p.sensors || [])) {
                    const id = tempId(e)
                    if (id.length === 0 || !sensorReady(id)) continue
                    const t = num(id, 0)
                    const label = tempLabel(e) || names[id] || id.split("/").pop()
                    out.push(attach(kvLine(label, Math.round(t) + "°C", (warn > 0 && t >= warn) ? "accent" : "fg"),
                                    b, label, [monitorItem()], { name: label, value: Math.round(t) }))
                }
                break
            }

            case "text": {
                // Only the block's own "click" command makes a text line active.
                const t = String(p.text || "")
                if (t.length > 0) out.push(attach(line(clip(t), p.role || "fg"), b, t, [], {}))
                break
            }

            case "spacer": {
                // A space, not an empty string: a blank Text has no height to give.
                const n = Math.max(1, Math.min(10, Number(p.lines) || 1))
                for (let i = 0; i < n; i++) out.push(line(" ", "fg"))
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
                    const low = Number(p.warn_low) || 0
                    const label = real.length > 1 ? "BT" + i : "BAT"
                    const energy = [settingsItem("kcm_powerdevilprofilesconfig", tr.i18nc("line action", "energy settings"))]
                    const batRow = barRow(label, percent)
                    out.push(attach((low > 0 && percent <= low) ? tint(batRow, "accent") : batRow,
                                    b, label, energy, { value: Math.round(percent) }))
                    out.push(attach(line(batteryText(percent, num(id + "chargeRate", 0),
                                                     num(id + "charge", 0), num(id + "capacity", 0),
                                                     num(id + "health", -1)), "dim"),
                                    b, label, energy, { value: Math.round(percent) }))
                }
                break
            }

            case "services":
                for (const s of serviceRows)
                    out.push(attach(kvLine(s.label, serviceText(s)), b, s.label, serviceItems(s.label), { name: s.label }))
                break

            case "health": {
                const h = healthData
                if (p.units !== false && h.failed) {
                    const zero = h.failed[0] === "0" && h.failed[1] === "0"
                    const title = tr.i18nc("health: failed systemd units", "failed units")
                    out.push(attach(kvLine(title,
                                           zero ? "0" : tr.i18nc("health: a count for the system and one for the user session",
                                                                 "%1 system, %2 user", h.failed[0], h.failed[1])),
                                    b, title,
                                    [item(tr.i18nc("line action: systemctl --failed in a terminal", "failed units in a terminal"),
                                          "systemctl --failed; systemctl --user --failed", { terminal: true, hold: true })],
                                    { value: h.failed[0] }))
                }
                if (p.errors !== false && h.err) {
                    const title = tr.i18nc("health: journal entries of priority error or worse", "errors since boot")
                    out.push(attach(kvLine(title,
                                           h.err[0] === "noaccess"
                                               ? tr.i18nc("health: the system journal cannot be read by this user", "no access")
                                               : tr.i18nc("health: a count for the system and one for the user session",
                                                          "%1 system, %2 user", h.err[0], h.err[1] || "0")),
                                    b, title, [journalItem("")], { value: h.err[0] }))
                }
                if (p.reboot !== false && h.reboot) {
                    const title = tr.i18nc("health: a kernel newer than the running one is installed", "reboot")
                    out.push(attach(kvLine(title, tr.i18nc("health: a reboot is pending", "pending"), "accent"),
                                    b, title, [item(tr.i18nc("line action", "reboot now"), "systemctl reboot", { confirm: true })], {}))
                }
                const n = p.lines === undefined ? 3 : Math.max(0, Number(p.lines) || 0)
                for (const l of (h.lines || []).slice(0, n))
                    out.push(attach(line(clip((l.ident ? l.ident + "  " : "") + l.text), "dim"),
                                    b, l.ident || tr.i18nc("line action: menu title for a journal line", "journal"),
                                    [journalItem(l.ident || "")], { name: l.ident || "" }))
                break
            }

            case "units": {
                // "unit|state" per unit; a failed one in the accent colour, an inactive one dim.
                const text = cmdOut[b.id]
                if (text === undefined) break
                for (const row of text.split("\n")) {
                    const f = row.split("|")
                    if (f.length < 2) continue
                    const state = f[1].trim()
                    out.push(attach(kvLine(f[0].replace(/\.service$/, "").slice(0, 20), unitState(state),
                                           state === "failed" ? "accent" : (state === "active" ? "fg" : "dim")),
                                    b, f[0], unitItems(f[0], p.user === true), { unit: f[0], name: f[0], value: state }))
                }
                break
            }

            case "peripherals": {
                // "model|percentage|state" per device, from upower; low ones in the accent colour.
                const text = cmdOut[b.id]
                if (text === undefined) break
                const low = Number(p.warn_low) || 0
                for (const row of text.split("\n")) {
                    const f = row.split("|")
                    if (f.length < 3) continue
                    const percent = Number(f[1]) || 0
                    const note = f[2] === "charging" ? "  " + tr.i18nc("peripheral battery: charging", "charging") : ""
                    out.push(attach(kvLine(f[0].slice(0, 20), percent + "%" + note,
                                           (low > 0 && percent <= low) ? "accent" : "fg"),
                                    b, f[0], [settingsItem("kcm_bluetooth", tr.i18nc("line action", "Bluetooth settings"))],
                                    { name: f[0], value: percent }))
                }
                break
            }

            case "sound": {
                // "sink|name|volume|muted" and, when asked, "source|…": a bar for the volume,
                // the device's name under it.
                const text = cmdOut[b.id]
                if (text === undefined) break
                for (const row of text.split("\n")) {
                    const f = row.split("|")
                    if (f.length < 4) continue
                    const vol = Number(f[2]) || 0
                    const muted = f[3] === "1"
                    const input = f[0] === "source"
                    const volRow = barRow(input ? "MIC" : "VOL", vol, 3,
                                          muted ? "  " + tr.i18nc("sound: the device is muted", "muted") : "")
                    const vars = { name: f[1], value: vol }
                    out.push(attach(muted ? tint(volRow, "dim") : volRow, b, f[1], soundItems(input, muted), vars))
                    if (p.device !== false && f[1].length > 0)
                        out.push(attach(line(clip(f[1]), "dim"), b, f[1], soundItems(input, muted), vars))
                }
                break
            }

            case "repos": {
                // "name|branch|dirty|ahead|behind" per path; a dirty tree in the accent colour.
                const text = cmdOut[b.id]
                if (text === undefined) break
                // One line per path, in the order of the parameter: the path itself is
                // what the actions need, and the script prints only its last element.
                const rows = text.split("\n")
                for (let ri = 0; ri < rows.length; ri++) {
                    const f = rows[ri].split("|")
                    if (f.length < 2) continue
                    const path = String((p.paths || [])[ri] || "")
                    const items = path.length > 0 ? repoItems(path) : []
                    if (f[1] === "notgit") {
                        out.push(attach(kvLine(f[0].slice(0, 20),
                                               tr.i18nc("repos: the path is not a git repository", "not a repository"), "dim"),
                                        b, f[0], path.length > 0 ? [openItem(path), terminalAt(path)] : [],
                                        { name: f[0], path: path }))
                        continue
                    }
                    const dirty = Number(f[2]) || 0, ahead = Number(f[3]) || 0, behind = Number(f[4]) || 0
                    let v = f[1]
                    if (dirty > 0) v += "  ±" + dirty
                    if (ahead > 0) v += "  ↑" + ahead
                    if (behind > 0) v += "  ↓" + behind
                    out.push(attach(kvLine(f[0].slice(0, 20), v, dirty > 0 ? "accent" : "fg"),
                                    b, f[0], items, { name: f[0], path: path, value: f[1] }))
                }
                break
            }

            case "command": {
                const text = cmdOut[b.id]
                const rows = (text === undefined ? ["…"] : text.split("\n")).slice(0, p.lines || 1)
                const label = p.label || b.id
                const items = String(p.command || "").length > 0
                    ? [item(tr.i18nc("line action: the block's command, in a terminal", "run in a terminal"),
                            p.command, { terminal: true, hold: true })]
                    : []
                for (const r of rows) out.push(attach(kvLine(label, r), b, label, items, { name: label, value: r }))
                break
            }

            case "sensor": {
                const v = num(p.id, 0)
                const label = p.label || "SEN"
                const warn = Number(p.warn) || 0
                const vars = { name: p.id || "", value: comma(v, p.digits || 0) }
                if (p.bar !== false)
                    out.push(attach(warnLine(barRow(label, v, 3, (p.suffix || "") + sparkTail(b.id, p, 100)), v, warn),
                                    b, label, [monitorItem()], vars))
                else
                    out.push(attach(kvLine(label, comma(v, p.digits || 0) + (p.suffix || "") + sparkTail(b.id, p, 0),
                                           (warn > 0 && v >= warn) ? "accent" : "fg"),
                                    b, label, [monitorItem()], vars))
                break
            }

            case "passport": {
                if (cpuModel) out.push(attach(line("CPU | " + (cpuSockets > 1 ? cpuSockets + "x " : "") + cpuModel, "dim"),
                                              b, cpuModel, [infoItem()], { name: cpuModel }))
                for (const g of gpus) {
                    const gpu = sval("gpu/" + g + "/name")
                    if (gpu) out.push(attach(line("GPU | " + gpu, "dim"), b, String(gpu), [infoItem()], { name: gpu }))
                }
                if (boardLine) out.push(attach(line("MBD | " + boardLine, "dim"), b, boardLine, [infoItem()], { name: boardLine }))
                break
            }
            }
        }
        if (out.length > 0 && out[out.length - 1].separator) out.pop()
        return out
    }
}
