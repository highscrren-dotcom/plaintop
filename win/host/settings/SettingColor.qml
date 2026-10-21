import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "Form.js" as Form

// A colour setting, stored as "#RRGGBB" as the plasmoid stores ColorButton's string.
// There is no KQuickControls here: the text itself, a swatch beside it, and the system's
// colour dialog from a click on the swatch. The text is written like SettingText —
// debounced, and only when it is a colour.
RowLayout {
    id: row

    required property string key
    property string fallback: "#000000"
    property var page: null
    // A keystroke not written yet, for the stand.
    readonly property bool pending: debounce.running
    property alias text: field.text
    readonly property bool valid: /^#[0-9A-Fa-f]{6}$/.test(field.text)

    spacing: Form.spacing

    function stored() { return page ? page.str(key, fallback) : fallback }
    function sync() {
        if (!field.activeFocus && field.text !== stored())
            field.text = stored()
    }
    function flush() {
        debounce.stop()
        if (page && row.valid && field.text !== stored())
            page.set(key, field.text)
    }

    TextField {
        id: field
        implicitWidth: 110
        maximumLength: 7
        placeholderText: "#RRGGBB"
        font.family: "monospace"
        onTextEdited: debounce.restart()
        onEditingFinished: row.flush()
    }

    Rectangle {
        implicitWidth: field.implicitHeight
        implicitHeight: field.implicitHeight
        radius: 3
        color: row.valid ? field.text : "transparent"
        border.color: field.palette.mid
        border.width: 1

        // A cross where the text is not a colour yet.
        Label {
            anchors.centerIn: parent
            visible: !row.valid
            text: "×"
            opacity: 0.6
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                dialog.selectedColor = row.valid ? field.text : row.fallback
                dialog.open()
            }
        }
    }

    ColorDialog {
        id: dialog
        onAccepted: {
            field.text = selectedColor.toString()
            if (row.page) row.page.set(row.key, field.text)
        }
    }

    Timer {
        id: debounce
        interval: 400
        onTriggered: row.flush()
    }

    Component.onCompleted: {
        page = Form.pageOf(row)
        if (page) {
            page.register(key, row)
            page.cfgChanged.connect(row.sync)
        }
        sync()
    }
    Component.onDestruction: if (page) page.cfgChanged.disconnect(row.sync)
}
