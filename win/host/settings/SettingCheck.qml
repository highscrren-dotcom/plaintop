import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Form.js" as Form

// A Bool setting: checked from the page's settings, written back on a click. The binding
// outlives the click (verified: a toggle does not remove it), so an edit from elsewhere —
// the widget's own menu, the ini file — reaches the box through the window's poll.
CheckBox {
    id: box

    required property string key
    property bool fallback: false
    property var page: null

    checked: page ? page.flag(key, fallback) : fallback
    onToggled: if (page) page.set(key, checked)

    // A long text wraps inside the row instead of running past the window: the style's
    // label is a Text, whatever the style.
    Layout.fillWidth: true
    Component.onCompleted: {
        page = Form.pageOf(box)
        if (page) page.register(key, box)
        if (contentItem && contentItem.wrapMode !== undefined) contentItem.wrapMode = Text.Wrap // qmllint disable missing-property
    }
}
