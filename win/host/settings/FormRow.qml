import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Form.js" as Form

// One labelled row of a page: the label right-aligned in a column of one width, as
// Kirigami's FormLayout draws it, the control or controls to the right of it. Hiding or
// disabling the row takes the label with it, which a grid of separate cells would not.
RowLayout {
    id: row

    property string label: ""
    default property alias content: slot.data

    Layout.fillWidth: true
    spacing: Form.spacing

    Label {
        text: row.label
        Layout.preferredWidth: Form.labelWidth
        Layout.minimumWidth: Form.labelWidth
        Layout.alignment: Qt.AlignVCenter
        horizontalAlignment: Text.AlignRight
        wrapMode: Text.Wrap
    }

    RowLayout {
        id: slot
        Layout.fillWidth: true
        spacing: Form.spacing
    }
}
