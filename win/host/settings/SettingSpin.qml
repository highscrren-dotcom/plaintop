import QtQuick
import QtQuick.Controls
import "Form.js" as Form

// An Int setting. valueModified, not valueChanged: only what the user does is written,
// never the value the poll just set.
SpinBox {
    id: spin

    required property string key
    property int fallback: 0
    property var page: null

    editable: true
    value: page ? page.num(key, fallback) : fallback
    onValueModified: if (page) page.set(key, value)

    Component.onCompleted: {
        page = Form.pageOf(spin)
        if (page) page.register(key, spin)
    }
}
