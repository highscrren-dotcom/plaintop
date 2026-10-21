pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../monitor/description.js" as Description

// The monitor's Blocks page: monitor/package/contents/ui/configBlocks.qml over the
// setting `blocksJson`. The page is built from the vocabulary of block types
// (schema/blocks.json → description.js, copied in by win/build.py), not from a hardcoded
// list: a new block type must not require UI changes. Where the vocabulary marks a
// parameter "pick", the Plasma page offers the machine's own sensors beside the field;
// here the field stands alone, and its placeholder says that an empty value is found on
// the machine — which is what the widget does with an empty value anyway (decision 6).
SettingsPage {
    id: page

    // Working copy of the description; it goes into the settings as a JSON string.
    property var blocks: []
    property int selected: -1
    property string jsonError: ""
    // The JSON last written from here, so the poll's echo of it is told from an edit made
    // elsewhere — the ini file, say — which reloads the list.
    property string lastSaved: ""

    Component.onCompleted: load()
    onCfgChanged: if (str("blocksJson", "") !== lastSaved) load()

    function load() {
        const raw = str("blocksJson", "")
        lastSaved = raw
        let parsed = null
        if (raw.length > 0) {
            try { parsed = JSON.parse(raw) } catch (e) { parsed = null }
        }
        // Empty or garbage — take the layout generated from schema/widget.json.
        blocks = JSON.parse(JSON.stringify(
            (parsed && parsed.length > 0) ? parsed : Description.BLOCKS))
        selected = Math.min(selected, blocks.length - 1)
        refresh()
    }

    // Not save(): that is the page's write to the service, which set() calls.
    function commit() {
        lastSaved = JSON.stringify(blocks)
        set("blocksJson", lastSaved)
        refresh()
    }

    function reset() {
        lastSaved = ""
        set("blocksJson", "")
        blocks = JSON.parse(JSON.stringify(Description.BLOCKS))
        selected = Math.min(selected, blocks.length - 1)
        refresh()
    }

    // The JSON view follows the list unless it is being typed in.
    function refresh() {
        if (!jsonArea.activeFocus)
            jsonArea.text = JSON.stringify(blocks, null, 2)
    }

    // The vocabulary is English source text; the contexts match po/extract.py.
    function titleOf(b) {
        const spec = Description.VOCAB[b.type] || { name: b.type }
        const own = String(b.name || "")
        return (own.length > 0 ? own + " — " : "")
               + (spec.name ? page.i18nc("schema: block name", spec.name) : b.type)
    }
    function subtitleOf(b) {
        const spec = Description.VOCAB[b.type] || {}
        return b.id + (Number(b.column) === 2 ? "  " + page.i18nc("the block is in the second column", "(right column)") : "")
               + (spec.hint ? " — " + page.i18nc("schema: block hint", spec.hint) : "")
    }

    function move(from, to) {
        if (to < 0 || to >= blocks.length) return
        const copy = blocks.slice()
        const item = copy.splice(from, 1)[0]
        copy.splice(to, 0, item)
        blocks = copy
        selected = to
        commit()
    }

    // The list of types to add comes from the vocabulary — nowhere is it listed by hand.
    readonly property var types: {
        const out = []
        for (const key in Description.VOCAB)
            out.push({ type: key, name: Description.VOCAB[key].name
                                        ? page.i18nc("schema: block name", Description.VOCAB[key].name) : key })
        return out
    }

    // An id that no block has yet: the type plus a number.
    function freshId(type, list) {
        let n = 1
        while (list.some(b => b.id === type + n)) n++
        return type + n
    }

    function addBlock(type) {
        const spec = Description.VOCAB[type]
        if (!spec) return
        const params = ({})
        for (const key in (spec.params || {})) params[key] = spec.params[key].default
        const copy = blocks.slice()
        const at = selected >= 0 ? selected + 1 : copy.length
        copy.splice(at, 0, { id: freshId(type, copy), type: type, enabled: true, params: params })
        blocks = copy
        selected = at
        commit()
    }

    // A copy of the selected block under a fresh id, right after it: two command or two
    // sensor blocks differ only in their parameters, and those are kept.
    function duplicateBlock(i) {
        if (i < 0 || i >= blocks.length) return
        const copy = JSON.parse(JSON.stringify(blocks))
        const b = JSON.parse(JSON.stringify(copy[i]))
        b.id = freshId(b.type, copy)
        copy.splice(i + 1, 0, b)
        blocks = copy
        selected = i + 1
        commit()
    }

    function removeBlock(i) {
        if (i < 0 || i >= blocks.length) return
        const copy = blocks.slice()
        copy.splice(i, 1)
        blocks = copy
        selected = Math.min(i, copy.length - 1)
        commit()
    }

    function setEnabled(i, on) {
        if (i < 0 || i >= blocks.length) return
        const copy = JSON.parse(JSON.stringify(blocks))
        copy[i].enabled = on
        blocks = copy
        commit()
    }

    function setParam(key, value) {
        if (selected < 0) return
        const copy = JSON.parse(JSON.stringify(blocks))
        copy[selected].params = copy[selected].params || ({})
        copy[selected].params[key] = value
        blocks = copy
        commit()
    }

    // A field of the block itself — its name, its column — rather than a parameter.
    function setField(key, value) {
        if (selected < 0) return
        const copy = JSON.parse(JSON.stringify(blocks))
        copy[selected][key] = value
        blocks = copy
        commit()
    }

    // The layout typed as JSON: checked against the vocabulary before it replaces the
    // working copy, so a typo names its block rather than emptying the widget.
    function applyJson(text) {
        let parsed
        try {
            parsed = JSON.parse(text)
        } catch (e) {
            jsonError = page.i18n("Not valid JSON: %1", String(e.message || e))
            return
        }
        if (!Array.isArray(parsed)) {
            jsonError = page.i18n("The layout must be a list of blocks")
            return
        }
        const seen = ({})
        for (let i = 0; i < parsed.length; i++) {
            const b = parsed[i]
            if (!b || typeof b !== "object" || !b.id || !b.type) {
                jsonError = page.i18n("Block %1 needs an id and a type", i + 1)
                return
            }
            if (!Description.VOCAB[b.type]) {
                jsonError = page.i18n("Block %1: unknown type “%2”", i + 1, b.type)
                return
            }
            if (seen[b.id]) {
                jsonError = page.i18n("Block %1: the id “%2” is used twice", i + 1, b.id)
                return
            }
            seen[b.id] = true
        }
        jsonError = ""
        blocks = parsed
        selected = Math.min(selected, parsed.length - 1)
        commit()
    }

    // Parameters of the selected block, resolved through the vocabulary: type, label, value.
    readonly property var params: {
        if (selected < 0 || selected >= blocks.length) return []
        const b = blocks[selected]
        const spec = Description.VOCAB[b.type]
        if (!spec || !spec.params) return []
        const out = []
        for (const key in spec.params) {
            const d = spec.params[key]
            const v = (b.params && b.params[key] !== undefined) ? b.params[key] : d.default
            out.push({ key: key, name: d.name, type: d.type, value: v,
                       min: d.min !== undefined ? d.min : 0,
                       max: d.max !== undefined ? d.max : 999,
                       values: d.values || [], names: d.names || [],
                       pick: d.pick || "", pattern: d.pattern || "" })
        }
        return out
    }

    // An enum's labels, translated, and the index of its stored value. By index, not
    // Array methods: the list reaches the delegate as a variant list (docs/GOTCHAS.md).
    function enumNames(md) {
        const out = []
        for (let i = 0; i < md.names.length; i++)
            out.push(page.i18nc("schema: parameter value", String(md.names[i])))
        return out
    }
    function enumIndex(md) {
        for (let i = 0; i < md.values.length; i++)
            if (String(md.values[i]) === String(md.value))
                return i
        return 0
    }

    // A stringlist value as a JS array of strings, whatever list type it arrived as.
    function listOf(value) {
        const out = []
        for (let i = 0; value && i < value.length; i++)
            out.push(String(value[i]))
        return out
    }

    readonly property var current: (selected >= 0 && selected < blocks.length) ? blocks[selected] : null

    Hint {
        indent: false
        text: page.i18n("The blocks and their order. The default layout comes from schema/widget.json.")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Frame {
            Layout.fillWidth: true
            implicitHeight: 290
            padding: 1

            ListView {
                id: list
                anchors.fill: parent
                model: page.blocks
                clip: true

                delegate: ItemDelegate {
                    id: row
                    required property int index
                    required property var modelData
                    width: ListView.view.width
                    highlighted: index === page.selected
                    onClicked: page.selected = index

                    contentItem: RowLayout {
                        CheckBox {
                            checked: row.modelData.enabled !== false
                            onToggled: page.setEnabled(row.index, checked)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label {
                                text: page.titleOf(row.modelData)
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Label {
                                text: page.subtitleOf(row.modelData)
                                opacity: 0.6
                                font.pointSize: Math.max(7, Application.font.pointSize - 1)
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }

        // Not fillWidth: a layout inside a layout fills by default, and the buttons would
        // take the row from the list.
        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: false

            Button {
                text: page.i18n("Up")
                Layout.fillWidth: true
                enabled: page.selected > 0
                onClicked: page.move(page.selected, page.selected - 1)
            }
            Button {
                text: page.i18n("Down")
                Layout.fillWidth: true
                enabled: page.selected >= 0 && page.selected < page.blocks.length - 1
                onClicked: page.move(page.selected, page.selected + 1)
            }
            Button {
                text: page.i18n("Duplicate")
                Layout.fillWidth: true
                enabled: page.selected >= 0
                onClicked: page.duplicateBlock(page.selected)
            }
            Button {
                text: page.i18n("Remove")
                Layout.fillWidth: true
                enabled: page.selected >= 0
                onClicked: page.removeBlock(page.selected)
            }
            Button {
                text: page.i18n("Reset")
                Layout.fillWidth: true
                onClicked: page.reset()
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        ComboBox {
            id: typeBox
            Layout.fillWidth: true
            model: page.types
            textRole: "name"
        }
        Button {
            text: page.i18n("Add block")
            enabled: typeBox.currentIndex >= 0
            onClicked: page.addBlock(page.types[typeBox.currentIndex].type)
        }
    }

    // The block's own fields: a name of yours, to tell two of a kind apart in the list,
    // and the column it is drawn in.
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.current !== null
        spacing: 8

        FormRow {
            label: page.i18n("Name:")
            TextField {
                Layout.fillWidth: true
                text: page.current ? String(page.current.name || "") : ""
                placeholderText: page.i18nc("placeholder for the block's own name", "optional, shown in the list")
                onEditingFinished: page.setField("name", text)
            }
        }
        FormRow {
            label: page.i18n("Column:")
            ComboBox {
                model: [page.i18nc("the widget's column", "left"), page.i18nc("the widget's column", "right")]
                currentIndex: (page.current && Number(page.current.column) === 2) ? 1 : 0
                onActivated: page.setField("column", currentIndex === 1 ? 2 : 1)
            }
        }
        // The block's lines as active lines: off, they take no clicks; a command of the
        // user's own goes first in the menu and runs on a left click, with the row's
        // values filled in.
        FormRow {
            label: page.i18n("Active:")
            CheckBox {
                text: page.i18n("the block's lines take clicks")
                checked: page.current ? page.current.active !== false : true
                onToggled: page.setField("active", checked)
            }
        }
        FormRow {
            label: page.i18n("Click:")
            TextField {
                Layout.fillWidth: true
                text: page.current ? String(page.current.click || "") : ""
                placeholderText: page.i18nc("placeholder for the block's own click command", "a command of your own; {name} {pid} {path} {unit} {value} are filled in")
                onEditingFinished: page.setField("click", text)
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: page.params.length > 0
        spacing: 8

        Repeater {
            model: page.params

            // The parameter editor is picked by the type from the vocabulary.
            FormRow {
                id: paramRow
                required property var modelData
                label: page.i18nc("schema: parameter name", modelData.name) + ":"

                CheckBox {
                    visible: paramRow.modelData.type === "bool"
                    checked: paramRow.modelData.type === "bool" ? paramRow.modelData.value === true : false
                    onToggled: page.setParam(paramRow.modelData.key, checked)
                }
                SpinBox {
                    visible: paramRow.modelData.type === "int"
                    editable: true
                    from: paramRow.modelData.min
                    to: paramRow.modelData.max
                    value: paramRow.modelData.type === "int" ? Number(paramRow.modelData.value) : 0
                    onValueModified: page.setParam(paramRow.modelData.key, value)
                }
                ComboBox {
                    visible: paramRow.modelData.type === "enum"
                    Layout.fillWidth: true
                    model: paramRow.modelData.type === "enum" ? page.enumNames(paramRow.modelData) : []
                    currentIndex: paramRow.modelData.type === "enum" ? page.enumIndex(paramRow.modelData) : 0
                    onActivated: page.setParam(paramRow.modelData.key, String(paramRow.modelData.values[currentIndex]))
                }
                TextField {
                    visible: paramRow.modelData.type === "string" || paramRow.modelData.type === "stringlist"
                    Layout.fillWidth: true
                    text: paramRow.modelData.type === "stringlist"
                          ? page.listOf(paramRow.modelData.value).join(", ")
                          : String(paramRow.modelData.value || "")
                    placeholderText: paramRow.modelData.pick.length > 0
                        ? page.i18nc("Windows: placeholder of a sensor, interface or mount field", "empty — found on this machine")
                        : ""
                    onEditingFinished: {
                        if (paramRow.modelData.type === "stringlist")
                            page.setParam(paramRow.modelData.key,
                                text.split(",").map(s => s.trim()).filter(s => s.length > 0))
                        else
                            page.setParam(paramRow.modelData.key, text)
                    }
                }
            }
        }
    }

    // The whole layout as text: to read, to copy to another machine, to edit at once.
    Hint {
        indent: false
        text: page.i18n("The layout as JSON — edit here, or paste one from another machine:")
    }

    ScrollView {
        Layout.fillWidth: true
        implicitHeight: 200

        TextArea {
            id: jsonArea
            font.family: "monospace"
            wrapMode: TextEdit.NoWrap
        }
    }

    Label {
        Layout.fillWidth: true
        visible: page.jsonError.length > 0
        text: page.jsonError
        wrapMode: Text.Wrap
        color: "#B03030"
    }

    RowLayout {
        Button {
            text: page.i18n("Apply JSON")
            onClicked: page.applyJson(jsonArea.text)
        }
        Button {
            text: page.i18n("Reload from the list")
            onClicked: { page.jsonError = ""; jsonArea.text = JSON.stringify(page.blocks, null, 2) }
        }
    }
}
