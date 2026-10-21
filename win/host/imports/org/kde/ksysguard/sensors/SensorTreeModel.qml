import QtQuick

// The tree of what the machine reports, for SensorRegistry's walk: rowCount(parent),
// index(row, 0, parent) and data(index, SensorId). Built from the store's ids — a node for
// every path prefix, as the daemon's tree has group nodes ("cpu", "cpu/cpu0") with their
// own ids. An index here is the node's full path as a string; the root is undefined.
QtObject {
    id: tree

    enum Roles { SensorId = 256, Name }

    // path → [child paths], in the order the ids arrived.
    property var children: ({})
    property var names: ({})

    function rebuild() {
        const kids = ({ "": [] })
        const seen = ({ "": true })
        for (const id of SensorStore.ids()) {
            const parts = id.split("/")
            let path = ""
            for (let i = 0; i < parts.length; i++) {
                const next = path.length > 0 ? path + "/" + parts[i] : parts[i]
                if (!seen[next]) {
                    seen[next] = true
                    kids[path].push(next)
                    kids[next] = []
                }
                path = next
            }
        }
        children = kids
    }

    function rowCount(parent) {
        const list = children[parent === undefined || parent === null ? "" : String(parent)]
        return list ? list.length : 0
    }
    function index(row, column, parent) {
        const list = children[parent === undefined || parent === null ? "" : String(parent)]
        return list ? list[row] : undefined
    }
    function data(idx, role) {
        if (idx === undefined) return undefined
        if (role === SensorTreeModel.SensorId) return String(idx)
        if (role === SensorTreeModel.Name) return String(idx).split("/").pop()
        return undefined
    }

    readonly property Connections link: Connections {
        target: SensorStore
        function onUpdated() { tree.rebuild() }
    }
    Component.onCompleted: rebuild()
}
