import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.ksysguard.sensors as Sensors
import org.kde.ksysguard.process as Proc
import org.kde.kitemmodels as KItem

PlasmoidItem {
    id: root

    // Виджет живёт на фоне рабочего стола: рамка и подложка не нужны,
    // но пользователь может вернуть их через штатный диалог.
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    preferredRepresentation: fullRepresentation

    // Палитра перенесена из conky/plainext.conf — тот же PlainExt.
    readonly property color cFg: "#C8CCD4"      // основной текст
    readonly property color cAccent: "#E05561"  // заголовок и полоски
    readonly property color cDim: "#6B7280"     // второстепенное
    readonly property color cVal: "#8FB6E0"     // значения

    readonly property int rate: Plasmoid.configuration.updateInterval
    readonly property int barWidth: 18          // ширина полоски в символах, как в lua

    // ── Данные ────────────────────────────────────────────────────────────────
    // Один SensorDataModel на все величины: одна подписка вместо сотни объектов.
    // Роли берутся по имени (Sensors.SensorDataModel.Value), а не числом — числа
    // между версиями Plasma не обещаны.
    readonly property var coreIds: {
        const a = []
        for (let i = 0; i < 72; i++) a.push("cpu/cpu" + i + "/usage")
        for (let i = 0; i < 72; i++) a.push("cpu/cpu" + i + "/temperature")
        return a
    }

    readonly property var sensorIds: [
        "cpu/all/usage", "cpu/all/name", "cpu/all/coreCount", "cpu/all/cpuCount",
        "memory/physical/usedPercent", "memory/physical/used", "memory/physical/total",
        "os/system/hostname", "os/system/name", "os/kernel/version",
        "lmsensors/nct6779-isa-0a20/fan1", "lmsensors/nct6779-isa-0a20/fan2",
        // ⚠️ Датчики lm_sensors адресуются по ИМЕНИ чипа, не по индексу hwmon:
        // индексы плавают между перезагрузками.
        "lmsensors/nvme-pci-0500/temp1",
        "gpu/gpu0/usage", "gpu/gpu0/temperature", "gpu/gpu0/usedVram",
        "gpu/gpu0/totalVram", "gpu/gpu0/power", "gpu/gpu0/name",
        "network/" + Plasmoid.configuration.netInterface + "/download",
        "network/" + Plasmoid.configuration.netInterface + "/upload",
        "os/system/uptime"
    ].concat(coreIds)

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
        sortRoleName: "Value"     // ⚠️ именно sortRoleName: с sortRole компонент не строится
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

    // Раскладка ядер по узлам NUMA читается из /sys один раз на старте:
    // зашивать её числами нельзя — на другой машине она другая.
    property var nodeCpus: []
    property string cpuModel: ""
    property string boardLine: ""
    property int cpuSockets: 0
    property int cpuCores: 0
    property int cpuThreads: 0

    P5Support.DataSource {
        id: topology
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
            // Разовое чтение: топология и модель процессора за сеанс не меняются.
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

    property var diskRows: []

    P5Support.DataSource {
        id: slow
        engine: "executable"
        // ⚠️ Раз в 10 с, а не каждый тик: каждый запуск — это fork в процессе оболочки.
        interval: 10000
        connectedSources: [
            "df -B1 --output=target,size,used,pcent " + Plasmoid.configuration.mounts.join(" ") + " 2>/dev/null"
        ]

        onNewData: function(source, data) {
            const rows = []
            // Первая строка — заголовок df, он локализован; разбираем по позициям.
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
        // Службы меняются редко, а каждый запуск — fork: раз в 15 с достаточно.
        interval: 15000
        // Скрипт лежит в самом пакете; движок исполняет команду через shell,
        // поэтому достаточно отдать ему путь без схемы file://.
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

    // Тик, от которого зависят все вычисляемые строки: чтение из модели само
    // по себе связывания не создаёт, поэтому зависимость делается явной.
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

    // ── Форматирование ────────────────────────────────────────────────────────
    // ⚠️ Своё, а не formattedValue: тот вставляет U+200B перед «%» и U+2009 перед
    // «°C», и в моноширинном тексте колонки разъезжаются.
    function bar(pct) {
        const k = Math.max(0, Math.min(barWidth, Math.round(pct * barWidth / 100)))
        return "/".repeat(k) + " ".repeat(barWidth - k)
    }

    function pct(v) {
        return String(Math.round(v)).padStart(3) + "%"
    }

    function comma(x, digits) {
        return x.toFixed(digits).replace(".", ",")
    }

    function gib(bytes) {
        return comma(bytes / 1024 / 1024 / 1024, 1) + " GiB"
    }

    function human(secs) {
        const d = Math.floor(secs / 86400)
        const h = Math.floor(secs % 86400 / 3600)
        const m = Math.floor(secs % 3600 / 60)
        return (d > 0 ? d + "д " : "") + h + "ч " + m + "м"
    }

    // ── Вычисляемые строки ────────────────────────────────────────────────────
    readonly property real cpuUsage: (tick, num("cpu/all/usage", 0))

    // Узел NUMA: средняя загрузка его ядер и самая горячая из их температур.
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

    readonly property string headerLine: {
        tick
        const host = sval("os/system/hostname")
        return Plasmoid.configuration.header + (host ? "\\" + host : "")
    }

    readonly property var nodes: {
        tick
        const out = []
        for (let n = 0; n < nodeCpus.length; n++) out.push({ usage: nodeUsage(n), temp: nodeTemp(n) })
        return out
    }

    readonly property real memPct: (tick, num("memory/physical/usedPercent", 0))

    readonly property string clockBig: (tick, Qt.formatTime(new Date(), "HH:mm"))
    readonly property string clockSec: (tick, Qt.formatTime(new Date(), ":ss"))
    // ⚠️ Qt.formatDate берёт локаль C и выдаёт «Sunday, 20 September» даже при ru_RU.
    // Русские названия даёт только toLocaleDateString с явной локалью.
    readonly property string dateLine: {
        tick
        const s = new Date().toLocaleDateString(Qt.locale(), "dddd, d MMMM")
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    readonly property string osLine: {
        tick
        const os = sval("os/system/name") || ""
        const kern = sval("os/kernel/version") || ""
        return os + "  " + kern
    }

    readonly property string cpuModelLine: {
        tick
        const name = (cpuSockets > 1 ? cpuSockets + "x " : "") + (cpuModel || "CPU")
        const cores = cpuCores
        const threads = cpuThreads
        const t0 = Math.round(nodeTemp(0)), t1 = Math.round(nodeTemp(1))
        const f1 = Math.round(num("lmsensors/nct6779-isa-0a20/fan1", 0))
        const f2 = Math.round(num("lmsensors/nct6779-isa-0a20/fan2", 0))
        return name + "  " + cores + "c/" + threads + "t  "
             + (t0 > 0 ? t0 + "/" + t1 + "°C  " : "")
             + (f1 > 0 ? f1 + "/" + f2 + " rpm" : "")
    }

    readonly property string memLine: {
        tick
        return gib(num("memory/physical/used", 0)) + " / " + gib(num("memory/physical/total", 0))
    }

    readonly property string uptimeLine: (tick, "аптайм " + human(num("os/system/uptime", 0)))

    // Топ процессов: имя слева, значение в фиксированной колонке — иначе
    // в моноширинном тексте правый край поедет.
    function topRows(model, column, format) {
        tick
        const out = []
        const n = Math.min(Plasmoid.configuration.topCount, model.rowCount())
        for (let i = 0; i < n; i++) {
            const name = String(model.data(model.index(i, 0), Proc.ProcessDataModel.Value) || "")
            const v = model.data(model.index(i, column), Proc.ProcessDataModel.Value)
            out.push(name.slice(0, 20).padEnd(21) + "| " + format(Number(v) || 0))
        }
        return out
    }

    readonly property var topCpu: topRows(byCpu, 1, v => comma(v, 1) + "%")
    readonly property var topMem: topRows(byMem, 2, v => comma(v / 1024 / 1024, 1) + " GiB")

    readonly property real gpuUsage: (tick, num("gpu/gpu0/usage", 0))

    readonly property string vramLine: {
        tick
        const used = num("gpu/gpu0/usedVram", 0), total = num("gpu/gpu0/totalVram", 0)
        const t = Math.round(num("gpu/gpu0/temperature", 0))
        const w = Math.round(num("gpu/gpu0/power", 0))
        return "VRAM " + comma(used / 1024 / 1024 / 1024, 1) + "/" + comma(total / 1024 / 1024 / 1024, 1)
             + " GB  temp " + t + "°C  pwr " + w + "W"
    }

    // Каждая файловая система — две строки: полоска с процентом и подпись под ней.
    readonly property var diskLines: {
        tick
        const out = []
        for (const d of diskRows) {
            const name = d.target === "/" ? "/" : d.target.split("/").pop()
            out.push({ bar: true, text: name.padEnd(3).slice(0, 3) + " " + bar(d.pct) + " " + pct(d.pct) })
            let note = "F: " + gib(d.size - d.used) + "  T: " + gib(d.size)
            if (d.target === "/") {
                const t = Math.round(num("lmsensors/nvme-pci-0500/temp1", 0))
                if (t > 0) note += "  nvme " + t + "°C"
            }
            out.push({ bar: false, text: note })
        }
        // Настроенные, но не смонтированные — показываем прочерком, а не молчанием.
        for (const m of Plasmoid.configuration.mounts) {
            if (!diskRows.some(d => d.target === m))
                out.push({ bar: false, text: m.split("/").pop() + " | не смонтирован" })
        }
        return out
    }

    function speed(bytes) {
        if (bytes >= 1024 * 1024) return comma(bytes / 1024 / 1024, 1) + " MiB/s"
        if (bytes >= 1024) return comma(bytes / 1024, 0) + " KiB/s"
        return Math.round(bytes) + " B/s"
    }

    readonly property string netLine: {
        tick
        const iface = Plasmoid.configuration.netInterface
        return iface + "  Dl " + speed(num("network/" + iface + "/download", 0))
             + "  Ul " + speed(num("network/" + iface + "/upload", 0))
    }

    readonly property var passport: {
        tick
        const rows = []
        if (cpuModel) rows.push("CPU | " + (cpuSockets > 1 ? cpuSockets + "x " : "") + cpuModel)
        const gpu = sval("gpu/gpu0/name")
        if (gpu) rows.push("GPU | " + gpu)
        if (boardLine) rows.push("MBD | " + boardLine)
        return rows
    }

    readonly property string sep: "-".repeat(35)

    // ── Разметка ──────────────────────────────────────────────────────────────
    fullRepresentation: Item {
        implicitWidth: column.implicitWidth
        implicitHeight: column.implicitHeight
        Layout.minimumWidth: column.implicitWidth
        Layout.minimumHeight: column.implicitHeight

        // Строка виджета: моноширинный текст, цвет и кегль задаются на месте.
        component Line: Text {
            color: root.cFg
            font.family: Plasmoid.configuration.fontFamily
            font.pointSize: Plasmoid.configuration.fontSize
            renderType: Text.NativeRendering
        }

        Column {
            id: column
            spacing: 0

            Line {
                text: root.headerLine
                color: root.cAccent
            }

            Row {
                spacing: 0
                Line {
                    text: root.clockBig
                    font.pointSize: Plasmoid.configuration.fontSize * 3.4
                    font.bold: true
                }
                Line {
                    text: root.clockSec
                    font.pointSize: Plasmoid.configuration.fontSize * 1.5
                    color: root.cVal
                    anchors.bottom: parent.bottom
                }
            }

            Line { text: root.dateLine; color: root.cVal }
            Line { text: root.osLine; color: root.cDim }
            Line { text: root.sep; color: root.cDim }

            Line { text: "CPU " + root.bar(root.cpuUsage) + " " + root.pct(root.cpuUsage) }

            Repeater {
                model: root.nodes
                Line {
                    required property int index
                    required property var modelData
                    text: "S" + index + " " + root.bar(modelData.usage)
                          + " " + root.pct(modelData.usage) + "   node" + index
                }
            }

            Line { text: root.cpuModelLine; color: root.cDim }

            Repeater {
                model: root.topCpu
                Line { required property string modelData; text: modelData }
            }

            Line { text: root.sep; color: root.cDim }

            Line { text: "RAM " + root.bar(root.memPct) + " " + root.pct(root.memPct) }
            Line { text: root.memLine; color: root.cDim }

            Repeater {
                model: root.topMem
                Line { required property string modelData; text: modelData }
            }

            Line { text: root.sep; color: root.cDim }

            Line { text: "GPU " + root.bar(root.gpuUsage) + " " + root.pct(root.gpuUsage) }
            Line { text: root.vramLine; color: root.cDim }

            Line { text: root.sep; color: root.cDim }

            Repeater {
                model: root.diskLines
                Line {
                    required property var modelData
                    text: modelData.text
                    color: modelData.bar ? root.cFg : root.cDim
                }
            }

            Line { text: root.sep; color: root.cDim }

            Line { text: root.uptimeLine }
            Line { text: root.netLine; color: root.cDim }

            Line { text: root.sep; color: root.cDim }

            Repeater {
                model: root.serviceRows
                Row {
                    required property var modelData
                    spacing: 0
                    Line { text: modelData.label.padEnd(21); color: root.cDim }
                    Line { text: "| " + modelData.value }
                }
            }

            Line { text: root.sep; color: root.cDim }

            Repeater {
                model: root.passport
                Line { required property string modelData; text: modelData; color: root.cDim }
            }
        }
    }
}
