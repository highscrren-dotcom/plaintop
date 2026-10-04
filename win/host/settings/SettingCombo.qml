import QtQuick
import QtQuick.Controls
import "Form.js" as Form

// A choice. With `values` empty the index itself is the setting, as the plasmoid pages'
// `property alias cfg_x: box.currentIndex` has it; otherwise values[index] is stored and
// the combo follows whichever entry the stored value matches (calendar's months 1/3,
// firstDay 0/1/7, the weather source's ids).
ComboBox {
    id: combo

    required property string key
    property var values: []
    property var page: null

    function indexFor(v) {
        if (!values || values.length === 0) {
            const n = Number(v)
            return isNaN(n) ? 0 : n
        }
        for (let i = 0; i < values.length; i++)
            if (String(values[i]) === String(v))
                return i
        return 0
    }

    // The index as a binding, set again whenever the model is replaced: a ComboBox resets
    // currentIndex to 0 on a new model (the growth entries follow ring/line, the accounts
    // arrive from /notes) and a plain binding would not be re-run for that.
    function rebind() {
        currentIndex = Qt.binding(function() { return page ? indexFor(page.cfg[key]) : 0 })
    }
    onModelChanged: if (page) rebind()
    onActivated: index => {
        if (page) page.set(key, (values && values.length > 0) ? values[index] : index)
    }

    Component.onCompleted: {
        page = Form.pageOf(combo)
        if (page) page.register(key, combo)
        rebind()
    }
}
