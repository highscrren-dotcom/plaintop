import QtQuick
import QtQuick.Controls
import "Form.js" as Form

// A String setting. Written 400 ms after the last keystroke and on Enter or focus loss,
// and never reset under the cursor: the stored value is taken only while the field is
// not being edited, so the poll that brings a half-typed word back cannot cut it short.
TextField {
    id: field

    required property string key
    property string fallback: ""
    property var page: null
    // A keystroke not written yet, for the stand.
    readonly property bool pending: debounce.running

    function stored() { return page ? page.str(key, fallback) : fallback }
    function sync() {
        if (!activeFocus && text !== stored())
            text = stored()
    }
    function flush() {
        debounce.stop()
        if (page && text !== stored())
            page.set(key, text)
    }

    onTextEdited: debounce.restart()
    onEditingFinished: flush()

    Timer {
        id: debounce
        interval: 400
        onTriggered: field.flush()
    }

    Component.onCompleted: {
        page = Form.pageOf(field)
        if (page) {
            page.register(key, field)
            page.cfgChanged.connect(field.sync)
        }
        sync()
    }
    Component.onDestruction: if (page) page.cfgChanged.disconnect(field.sync)
}
