import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A section heading: Kirigami.FormData.isSection, as a bold line over a rule.
ColumnLayout {
    id: section

    property string title: ""

    Layout.fillWidth: true
    Layout.topMargin: 10
    spacing: 4

    Label {
        id: heading
        text: section.title
        font.bold: true
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: heading.palette.mid
        opacity: 0.6
    }
}
