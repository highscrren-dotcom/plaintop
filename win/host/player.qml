import QtQuick
import plaintop

// The player's window host: the shared PlayerView over the mpris shim (the service's
// /player, the System Media Transport Controls). Sized as the plasmoid is: `columns`
// characters wide, five lines tall.
import "player"

WidgetWindow {
    id: root
    widget: "player"

    readonly property string face: fixedFace("fontFamily")
    TextMetrics {
        id: cell
        font.family: root.face
        font.pointSize: root.num("fontSize", 10)
        text: "0"
    }
    Text {
        id: lineProbe
        visible: false
        text: "0"
        font.family: root.face
        font.pointSize: root.num("fontSize", 10)
        renderType: Text.NativeRendering
    }

    width: Math.ceil(cell.advanceWidth * Math.max(22, num("columns", 44)))
    readonly property var lines: view.lines
    height: Math.ceil(lineProbe.implicitHeight * 5)

    PlayerView {
        id: view
        anchors.fill: parent
        playerFilter: root.str("player", "")
        showAlbum: root.flag("album", true)
        showControls: root.flag("controls", true)
        columns: Math.max(22, root.num("columns", 44))
        fontFamily: root.face
        fontSize: root.num("fontSize", 10)
        colorFg: root.str("colorFg", "#C8CCD4")
        colorAccent: root.str("colorAccent", "#E05561")
        colorDim: root.str("colorDim", "#6B7280")
    }
}
