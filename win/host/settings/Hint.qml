import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Form.js" as Form

// The dim small text under a row, aligned with the controls — the plasmoid pages' Label
// with Kirigami.Theme.smallFont. `indent: false` for a note that spans the page.
Label {
    property bool indent: true

    Layout.fillWidth: true
    Layout.leftMargin: indent ? Form.labelWidth + Form.spacing : 0
    opacity: 0.7
    font.pointSize: Math.max(7, Application.font.pointSize - 1)
    wrapMode: Text.Wrap
}
