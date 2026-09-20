import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.ksysguard.sensors as Sensors
import org.kde.ksysguard.process as Proc
import org.kde.kitemmodels as KItem

import "../code/description.js" as Description

PlasmoidItem {
    id: root

    // The widget lives on the desktop background: no frame and no backdrop needed,
    // but the user can bring them back through the standard dialog.
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    preferredRepresentation: fullRepresentation

    // ⚠️ The containment takes the applet size from Layout.* ON THE ROOT, and the hint
    // must be constant. While it depended on the text height, the containment rebuilt
    // the layout on every change of the line count and reset the widget to the 0,0
    // corner — verified.
    Layout.minimumWidth: Plasmoid.configuration.widgetWidth
    Layout.minimumHeight: Plasmoid.configuration.widgetHeight
    Layout.preferredWidth: Plasmoid.configuration.widgetWidth
    Layout.preferredHeight: Plasmoid.configuration.widgetHeight

    // Palette carried over from conky/plainext.conf — the same PlainExt.
    readonly property color cFg: "#C8CCD4"      // main text
    readonly property color cAccent: "#E05561"  // header and bars
    readonly property color cDim: "#6B7280"     // secondary
    readonly property color cVal: "#8FB6E0"     // values

    readonly property int rate: Plasmoid.configuration.updateInterval
    readonly property int barWidth: 18          // bar width in characters, as in lua

    // ── Widget description ────────────────────────────────────────────────────
    // What to show and in which order comes from the description, not from the layout.
    // The user's edit sits in the settings as a JSON string; when it is empty, take the
    // one generated from schema/widget.json (plasmoid/generate.py puts it in the
    // package).
    readonly property var blocks: {
        const raw = Plasmoid.configuration.blocksJson
        if (raw && raw.length > 0) {
            try {
                const parsed = JSON.parse(raw)
                if (Array.isArray(parsed) && parsed.length > 0) return parsed
            } catch (e) {
                console.warn("plaintop: the description in the settings does not parse, using the packaged one:", e)
            }
        }
        return Description.BLOCKS
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
        model: root.commandBlocks

        delegate: P5Support.DataSource {
            required property var modelData
            engine: "executable"
            interval: modelData.interval * 1000
            connectedSources: [modelData.command]

            onNewData: function(source, data) {
                // Rebuild the whole object: editing a field does not wake bindings.
                const m = ({})
                for (const k in root.cmdOut) m[k] = root.cmdOut[k]
                m[modelData.id] = String(data.stdout).replace(/\n+$/, "")
                root.cmdOut = m
            }
        }
    }

    readonly property string netIface: blockParam("network", "interface", "enp4s0")
    readonly property var mounts: blockParam("disks", "mounts", ["/"])

    // ── Data ──────────────────────────────────────────────────────────────────
    // One SensorDataModel for all values: a single subscription instead of a hundred
    // objects. Roles are taken by name (Sensors.SensorDataModel.Value), not by number —
    // the numbers are not promised across Plasma versions.
    readonly property var coreIds: {
        const a = []
        for (let i = 0; i < 72; i++) a.push("cpu/cpu" + i + "/usage")
        for (let i = 0; i < 72; i++) a.push("cpu/cpu" + i + "/temperature")
        return a
    }

    // ⚠️ Duplicates must be removed: SensorDataModel collapses identical ids, the
    // columns become fewer than the list entries, and reads by index slide off.
    readonly property var sensorIds: {
        const out = [], seen = ({})
        for (const id of rawSensorIds) if (!seen[id]) { seen[id] = true; out.push(id) }
        return out
    }

    readonly property var rawSensorIds: [
        "cpu/all/usage",
        "memory/physical/usedPercent", "memory/physical/used", "memory/physical/total",
        "os/system/hostname", "os/system/name", "os/kernel/version",
        "lmsensors/nct6779-isa-0a20/fan1", "lmsensors/nct6779-isa-0a20/fan2",
        // ⚠️ lm_sensors sensors are addressed by chip NAME, not by hwmon index:
        // the indexes drift between reboots.
        "lmsensors/nvme-pci-0500/temp1",
        "gpu/gpu0/usage", "gpu/gpu0/temperature", "gpu/gpu0/usedVram",
        "gpu/gpu0/totalVram", "gpu/gpu0/power", "gpu/gpu0/name",
        "network/" + netIface + "/download", "network/" + netIface + "/upload",
        "os/system/uptime"
    ].concat(coreIds).concat(customSensorIds)

    readonly property var colOf: {
        const m = ({})
        for (let i = 0; i < sensorIds.length; i++) m[sensorIds[i]] = i
        return m
    }

    Sensors.SensorDataModel {
        id: mon
        sensors: root.sensorIds
        updateRateLimit: root.rate
    }

    Proc.ProcessDataModel {
        id: procs
        enabledAttributes: ["name", "usage", "memory"]
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
            root.nodeCpus = nodes
        }

        function parseBoard(out) {
            const l = out.trim().split("\n")
            if (l.length >= 3) root.boardLine = l[0] + " " + l[1] + "  (BIOS " + l[2] + ")"
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
            root.cpuModel = model.replace(/\(R\)|\(TM\)/g, "").replace(/ CPU /, " ")
                                 .replace(/ @.*$/, "").replace(/\s+/g, " ").trim()
            root.cpuSockets = sockets
            root.cpuCores = sockets * perSocket
            root.cpuThreads = sockets * perSocket * perCore
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
            "df -B1 --output=target,size,used,pcent " + root.mounts.join(" ") + " 2>/dev/null"
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
            root.diskRows = rows
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
        connectedSources: ["bash " + Qt.resolvedUrl("../code/services.sh").toString().replace("file://", "")]

        onNewData: function(source, data) {
            const rows = []
            for (const line of String(data.stdout).trim().split("\n")) {
                const i = line.indexOf("|")
                if (i < 0) continue
                rows.push({ label: line.slice(0, i), value: line.slice(i + 1) })
            }
            root.serviceRows = rows
        }
    }

    // The tick every computed line depends on: reading from the model does not create a
    // binding by itself, so the dependency is made explicit.
    property int tick: 0

    Timer {
        interval: root.rate
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.tick++
    }

    function sval(id) {
        const col = colOf[id]
        if (col === undefined) return undefined
        return mon.data(mon.index(0, col), Sensors.SensorDataModel.Value)
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
        for (let i = 0; i < 72; i++) if (set[i]) { sum += num("cpu/cpu" + i + "/usage", 0); cnt++ }
        return cnt > 0 ? sum / cnt : 0
    }

    function nodeTemp(n) {
        const set = nodeCpus[n]
        if (!set) return 0
        let max = 0
        for (let i = 0; i < 72; i++) if (set[i]) max = Math.max(max, num("cpu/cpu" + i + "/temperature", 0))
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
    function line(text, color) {
        return { kind: "parts", parts: [{ text: text, color: color || cFg }] }
    }

    function kvLine(label, value) {
        return { kind: "parts", parts: [
            { text: String(label).padEnd(21), color: cDim },
            { text: "| " + value, color: cFg }
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
                const host = p.hostname === false ? "" : sval("os/system/hostname")
                out.push(line((p.text || "") + (host ? "\\" + host : ""), cAccent))
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
                out.push(line(d.charAt(0).toUpperCase() + d.slice(1), cVal))
                break
            }
            case "os":
                out.push(line((sval("os/system/name") || "") + "  " + (sval("os/kernel/version") || ""), cDim))
                break

            case "separator":
                out.push(line("-".repeat(35), cDim))
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
                    const f1 = Math.round(num("lmsensors/nct6779-isa-0a20/fan1", 0))
                    const f2 = Math.round(num("lmsensors/nct6779-isa-0a20/fan2", 0))
                    out.push(line(name + "  " + cpuCores + "c/" + cpuThreads + "t  "
                                  + (t0 > 0 ? t0 + "/" + t1 + "°C  " : "")
                                  + (f1 > 0 ? f1 + "/" + f2 + " rpm" : ""), cDim))
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
                                  + gib(num("memory/physical/total", 0)), cDim))
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
                                  + "°C  pwr " + Math.round(num("gpu/gpu0/power", 0)) + "W", cDim))
                }
                break
            }

            case "disks": {
                for (const d of diskRows) {
                    const name = d.target === "/" ? "/" : d.target.split("/").pop()
                    out.push(line(barRow(name, d.pct)))
                    let note = "F: " + gib(d.size - d.used) + "  T: " + gib(d.size)
                    if (d.target === "/" && p.nvme_temp !== false) {
                        const t = Math.round(num("lmsensors/nvme-pci-0500/temp1", 0))
                        if (t > 0) note += "  nvme " + t + "°C"
                    }
                    out.push(line(note, cDim))
                }
                // Configured but not mounted: say so instead of staying silent.
                for (const m of (p.mounts || [])) {
                    if (!diskRows.some(d => d.target === m))
                        out.push(line(m.split("/").pop() + " | не смонтирован", cDim))
                }
                break
            }

            case "uptime":
                out.push(line("аптайм " + human(num("os/system/uptime", 0))))
                break

            case "network": {
                const iface = p.interface || netIface
                out.push(line(iface + "  Dl " + speed(num("network/" + iface + "/download", 0))
                              + "  Ul " + speed(num("network/" + iface + "/upload", 0)), cDim))
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
                if (cpuModel) out.push(line("CPU | " + (cpuSockets > 1 ? cpuSockets + "x " : "") + cpuModel, cDim))
                const gpu = sval("gpu/gpu0/name")
                if (gpu) out.push(line("GPU | " + gpu, cDim))
                if (boardLine) out.push(line("MBD | " + boardLine, cDim))
                break
            }
            }
        }
        return out
    }

    // ── Layout ────────────────────────────────────────────────────────────────
    fullRepresentation: Item {
        // ⚠️ No Layout.minimum*: they make the containment fit the applet to the text
        // height, and that height changes while the data arrives (disks, services). Each
        // such fit resets the widget to the 0,0 corner — verified. The size comes from
        // the saved geometry, implicit* is only needed on the first appearance.
        // ⚠️ The size comes from the settings, NOT from the text height. While the
        // layout hint depended on the content, the containment rebuilt the layout on
        // every change of the line count (disks and services arriving) and reset the
        // widget to the 0,0 corner. Verified. A constant size means a constant place.
        implicitWidth: Plasmoid.configuration.widgetWidth
        implicitHeight: Plasmoid.configuration.widgetHeight

        // A widget line: monospace text, the color and font size are set in place.
        component Line: Text {
            color: root.cFg
            font.family: Plasmoid.configuration.fontFamily
            font.pointSize: Plasmoid.configuration.fontSize
            renderType: Text.NativeRendering
        }

        // ⚠️ The padding is drawn INSIDE the widget instead of being set through its
        // coordinates: a place set by a script is reset to the 0,0 corner by plasmashell
        // on the next start anyway — verified. This way the conky-like gap from the edge
        // holds regardless of where the containment put the applet.
        Column {
            id: column
            x: Plasmoid.configuration.padLeft
            y: Plasmoid.configuration.padTop
            spacing: 0

            Repeater {
                model: root.lines

                Item {
                    required property var modelData

                    implicitWidth: modelData.kind === "clock" ? clockRow.implicitWidth : partsRow.implicitWidth
                    implicitHeight: modelData.kind === "clock" ? clockRow.implicitHeight : partsRow.implicitHeight

                    // Row sets only x, so the small seconds can be placed on the
                    // baseline of the big clock — otherwise they drift in height.
                    Row {
                        id: clockRow
                        visible: modelData.kind === "clock"
                        spacing: 0

                        Line {
                            id: bigClock
                            text: visible ? modelData.big : ""
                            font.pointSize: Plasmoid.configuration.fontSize * 3.4
                            font.bold: true
                        }

                        Line {
                            text: clockRow.visible ? modelData.small : ""
                            font.pointSize: Plasmoid.configuration.fontSize * 1.5
                            color: root.cVal
                            anchors.baseline: bigClock.baseline
                        }
                    }

                    Row {
                        id: partsRow
                        visible: modelData.kind !== "clock"
                        spacing: 0

                        Repeater {
                            model: partsRow.visible ? modelData.parts : []

                            Line {
                                required property var modelData
                                text: modelData.text
                                color: modelData.color
                            }
                        }
                    }
                }
            }
        }
    }
}
