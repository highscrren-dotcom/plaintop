import QtQuick
import org.kde.ksysguard.sensors as Sensors

// The process table, as the shared QML reads libksysguard's: rowCount(), data(index(r, c),
// ProcessDataModel.Value) with the columns in the order of `enabledAttributes` — "name",
// "usage" (%), "memory" (KiB, as the attribute is there), "pid". The rows come from the
// service's /monitor answer: the heaviest processes by CPU and by memory, unsorted — the
// KSortFilterProxyModel shim orders them. `enabled: false` reads nothing, as the real
// model stops its timer; the monitor switches it on for one read per period.
QtObject {
    id: model

    enum Roles { Value = 256, FormattedValue, Name, Attribute }

    property var enabledAttributes: ["name", "usage", "memory", "pid"]
    property bool enabled: true

    // [[name, cpu, memory bytes, pid], …] as published.
    property var rows: []

    signal dataChanged()
    signal modelReset()

    function rowCount() { return rows.length }
    function columnCount() { return enabledAttributes.length }
    function index(row, column) { return { row: row, column: column } }
    function data(idx, role) {
        if (!idx || role !== ProcessDataModel.Value) return undefined
        const r = rows[idx.row]
        if (!r) return undefined
        switch (enabledAttributes[idx.column]) {
        case "name": return r[0]
        case "usage": return Number(r[1]) || 0
        case "memory": return Math.round((Number(r[2]) || 0) / 1024)
        case "pid": return Number(r[3]) || 0
        }
        return undefined
    }

    function refresh() {
        if (!enabled) return
        const list = Sensors.SensorStore.data.processes || []
        rows = list
        dataChanged()
    }

    onEnabledChanged: if (enabled) refresh()

    readonly property Connections link: Connections {
        target: Sensors.SensorStore
        function onUpdated() { model.refresh() }
    }
    Component.onCompleted: refresh()
}
