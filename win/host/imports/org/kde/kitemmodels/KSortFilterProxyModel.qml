import QtQuick

// Enough of KItemModels' proxy for the monitor's two process tops: rows of `sourceModel`
// sorted by one column (`sortColumn`, `sortOrder`), read through the same rowCount(),
// index() and data() the source has. `sortRoleName` is accepted for the shared QML's sake;
// the only role the source serves is its Value.
QtObject {
    id: proxy

    property QtObject sourceModel: null
    property string sortRoleName: ""
    property int sortColumn: 0
    property int sortOrder: Qt.AscendingOrder

    property var order: []          // proxy row → source row

    function rowCount() { return order.length }
    function index(row, column) { return { row: row, column: column } }
    function data(idx, role) {
        if (!sourceModel || !idx) return undefined
        const src = order[idx.row]
        if (src === undefined) return undefined
        return sourceModel.data(sourceModel.index(src, idx.column), role)
    }

    function resort() {
        if (!sourceModel) { order = []; return }
        const n = sourceModel.rowCount()
        const rows = []
        for (let r = 0; r < n; r++)
            rows.push({ r: r, v: sourceModel.data(sourceModel.index(r, sortColumn), 256) })
        const sign = sortOrder === Qt.DescendingOrder ? -1 : 1
        rows.sort(function(a, b) {
            const x = a.v, y = b.v
            if (typeof x === "number" && typeof y === "number") return sign * (x - y)
            return sign * String(x).localeCompare(String(y))
        })
        order = rows.map(x => x.r)
    }

    onSourceModelChanged: resort()
    onSortColumnChanged: resort()
    onSortOrderChanged: resort()

    readonly property Connections link: Connections {
        target: proxy.sourceModel
        ignoreUnknownSignals: true
        function onDataChanged() { proxy.resort() }
        function onModelReset() { proxy.resort() }
    }
    Component.onCompleted: resort()
}
