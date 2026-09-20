import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.ksysguard.sensors as Sensors

PlasmoidItem {
    id: root

    // Виджет живёт на фоне рабочего стола: рамка и подложка не нужны,
    // но пользователь может вернуть их через штатный диалог.
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    preferredRepresentation: fullRepresentation

    // Данные берутся у ksystemstats (демон поднимается по подписке), а не из /proc:
    // XHR к file:// в plasmashell запрещён Qt, а запуск команд каждую секунду —
    // это fork в процессе оболочки. Подробности — ../../docs/GOTCHAS.md.
    readonly property int statusReady: 2   // Sensor.status: 0 неизвестно, 1 грузится, 2 готов

    readonly property int rate: Plasmoid.configuration.updateInterval

    Sensors.Sensor { id: cpuUsage; sensorId: "cpu/all/usage";               updateRateLimit: root.rate }
    Sensors.Sensor { id: cpuTemp;  sensorId: "cpu/all/averageTemperature";  updateRateLimit: root.rate }
    Sensors.Sensor { id: memUsed;  sensorId: "memory/physical/usedPercent"; updateRateLimit: root.rate }
    Sensors.Sensor { id: uptime;   sensorId: "os/system/uptime";            updateRateLimit: 60000 }
    Sensors.Sensor { id: hostname; sensorId: "os/system/hostname";          updateRateLimit: 60000 }

    property string clockLine: ""

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.clockLine = Qt.formatTime(new Date(), "HH:mm:ss")
    }

    function ready(sensor) {
        return sensor.status === root.statusReady && sensor.value !== undefined
    }

    // Полоска из слешей — как в PlainExt: заполнение слева, ширина фиксированная,
    // иначе в моноширинном тексте поедут колонки справа.
    function bar(pct, width) {
        const filled = Math.max(0, Math.min(width, Math.round(pct / 100 * width)))
        return "/".repeat(filled) + " ".repeat(width - filled)
    }

    // ⚠️ Своё форматирование, а не Formatter/formattedValue: тот вставляет U+200B
    // перед «%» и U+2009 перед «°C», и моноширинные колонки разъезжаются.
    function pct(sensor) {
        return ready(sensor) ? String(Math.round(sensor.value)).padStart(3) + "%" : "   —"
    }

    function human(secs) {
        const d = Math.floor(secs / 86400)
        const h = Math.floor(secs % 86400 / 3600)
        const m = Math.floor(secs % 3600 / 60)
        return (d > 0 ? d + "д " : "") + h + "ч " + m + "м"
    }

    readonly property string cpuLine:
        "CPU " + bar(ready(cpuUsage) ? cpuUsage.value : 0, 20) + pct(cpuUsage)
        + (ready(cpuTemp) ? "  " + Math.round(cpuTemp.value) + "°C" : "")

    readonly property string memLine:
        "ОЗУ " + bar(ready(memUsed) ? memUsed.value : 0, 20) + pct(memUsed)

    readonly property string uptimeLine:
        ready(uptime) ? "аптайм " + human(uptime.value) : "аптайм —"

    fullRepresentation: Item {
        id: face

        // Размер задаёт сам текст: ширину — самая длинная строка, высоту — их число.
        // Layout.minimum* не даёт контейнеру ужать виджет и обрезать строки.
        implicitWidth: column.implicitWidth
        implicitHeight: column.implicitHeight
        Layout.minimumWidth: column.implicitWidth
        Layout.minimumHeight: column.implicitHeight

        Column {
            id: column
            spacing: 0

            Repeater {
                model: [
                    Plasmoid.configuration.header + (root.ready(hostname) ? "\\" + hostname.value : ""),
                    root.clockLine,
                    root.cpuLine,
                    root.memLine,
                    root.uptimeLine
                ]

                Text {
                    text: modelData
                    color: "white"
                    font.family: Plasmoid.configuration.fontFamily
                    font.pointSize: Plasmoid.configuration.fontSize
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}
