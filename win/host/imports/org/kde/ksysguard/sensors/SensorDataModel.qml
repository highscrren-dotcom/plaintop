import QtQuick

// The batch model: one column per requested id, read as the shared QML reads the real
// one — `data(index(0, c), SensorDataModel.SensorId)` and `…Value`. Like ksystemstats'
// model it silently drops ids the machine does not have (MonitorData maps columns by their
// id for exactly that reason), and announces a change of the column set with modelReset.
QtObject {
    id: model

    // Qt::UserRole is 256; the numbers are this shim's own, the shared QML never writes them.
    enum Roles { SensorId = 256, Name, ShortName, Value, FormattedValue, Unit, Minimum, Maximum, Type, Status, UpdateInterval }

    property var sensors: []
    property int updateRateLimit: 1000
    property bool enabled: true

    // The ids that exist, in the order asked for.
    property var columns: []

    signal columnsInserted()
    signal columnsRemoved()
    signal modelReset()
    signal dataChanged()

    function columnCount() { return columns.length }
    function rowCount() { return columns.length > 0 ? 1 : 0 }
    // An index is the column number: rows are always 0 here.
    function index(row, column) { return column }
    function data(idx, role) {
        const id = columns[idx]
        if (id === undefined) return undefined
        switch (role) {
        case SensorDataModel.SensorId: return id
        case SensorDataModel.Value: return SensorStore.value(id)
        case SensorDataModel.Name: return SensorStore.name(id) || id
        case SensorDataModel.ShortName: return SensorStore.name(id) || id.split("/").pop()
        case SensorDataModel.Status: return SensorStore.has(id) ? 2 : 3
        }
        return undefined
    }

    function rebuild() {
        const list = []
        if (enabled && SensorStore.answered)
            for (const id of sensors)
                if (SensorStore.has(id) && list.indexOf(id) < 0) list.push(id)
        if (list.join("\n") !== columns.join("\n")) {
            columns = list
            modelReset()
        } else if (list.length > 0) {
            dataChanged()
        }
    }

    onSensorsChanged: rebuild()
    onEnabledChanged: rebuild()
    onUpdateRateLimitChanged: SensorStore.want(updateRateLimit)

    readonly property Connections link: Connections {
        target: SensorStore
        function onUpdated() { model.rebuild() }
    }

    Component.onCompleted: {
        SensorStore.want(updateRateLimit)
        rebuild()
    }
}
