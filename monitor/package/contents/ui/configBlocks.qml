import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as P5Support

import "../code/description.js" as Description

// The page is built from the vocabulary of block types (schema/blocks.json → description.js),
// not from a hardcoded list: a new block type must not require UI changes. Where the
// vocabulary marks a parameter "pick", the machine's own sensors, interfaces and mount
// points are offered beside the field (decision 6) — from the same registry the widget
// reads, which is a sibling file in this package.
KCM.SimpleKCM {
    id: page

    property string cfg_blocksJson: ""

    // Working copy of the description; it goes into the settings as a JSON string.
    property var blocks: []
    property int selected: -1
    property string jsonError: ""

    Component.onCompleted: load()

    function load() {
        let parsed = null
        if (cfg_blocksJson && cfg_blocksJson.length > 0) {
            try { parsed = JSON.parse(cfg_blocksJson) } catch (e) { parsed = null }
        }
        // Empty or garbage — take the layout generated from schema/widget.json.
        blocks = JSON.parse(JSON.stringify(
            (parsed && parsed.length > 0) ? parsed : Description.BLOCKS))
        refresh()
    }

    function save() {
        cfg_blocksJson = JSON.stringify(blocks)
        refresh()
    }

    function refresh() {
        const keep = selected
        listModel.clear()
        for (let i = 0; i < blocks.length; i++) {
            const b = blocks[i]
            const spec = Description.VOCAB[b.type] || { name: b.type }
            const own = String(b.name || "")
            listModel.append({
                // The vocabulary is English source text; the contexts match po/extract.py.
                title: (own.length > 0 ? own + " — " : "")
                       + (spec.name ? i18nc("schema: block name", spec.name) : b.type),
                subtitle: b.id + (Number(b.column) === 2 ? "  " + i18nc("the block is in the second column", "(right column)") : "")
                          + (spec.hint ? " — " + i18nc("schema: block hint", spec.hint) : ""),
                isOn: b.enabled !== false
            })
        }
        selected = Math.min(keep, blocks.length - 1)
        // The JSON view follows the list unless it is being typed in.
        if (!jsonArea.activeFocus)
            jsonArea.text = JSON.stringify(blocks, null, 2)
    }

    function move(from, to) {
        if (to < 0 || to >= blocks.length) return
        const copy = blocks.slice()
        const item = copy.splice(from, 1)[0]
        copy.splice(to, 0, item)
        blocks = copy
        selected = to
        save()
    }

    // The list of types to add comes from the vocabulary — nowhere is it listed by hand.
    readonly property var types: {
        const out = []
        for (const key in Description.VOCAB)
            out.push({ type: key, name: Description.VOCAB[key].name
                                        ? i18nc("schema: block name", Description.VOCAB[key].name) : key })
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
        save()
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
        save()
    }

    function removeBlock(i) {
        if (i < 0 || i >= blocks.length) return
        const copy = blocks.slice()
        copy.splice(i, 1)
        blocks = copy
        selected = Math.min(i, copy.length - 1)
        save()
    }

    function setParam(key, value) {
        if (selected < 0) return
        const copy = JSON.parse(JSON.stringify(blocks))
        copy[selected].params = copy[selected].params || ({})
        copy[selected].params[key] = value
        blocks = copy
        save()
    }

    // A field of the block itself — its name, its column — rather than a parameter.
    function setField(key, value) {
        if (selected < 0) return
        const copy = JSON.parse(JSON.stringify(blocks))
        copy[selected][key] = value
        blocks = copy
        save()
    }

    // The layout typed as JSON: checked against the vocabulary before it replaces the
    // working copy, so a typo names its block rather than emptying the widget.
    function applyJson(text) {
        let parsed
        try {
            parsed = JSON.parse(text)
        } catch (e) {
            jsonError = i18n("Not valid JSON: %1", String(e.message || e))
            return
        }
        if (!Array.isArray(parsed)) {
            jsonError = i18n("The layout must be a list of blocks")
            return
        }
        const seen = ({})
        for (let i = 0; i < parsed.length; i++) {
            const b = parsed[i]
            if (!b || typeof b !== "object" || !b.id || !b.type) {
                jsonError = i18n("Block %1 needs an id and a type", i + 1)
                return
            }
            if (!Description.VOCAB[b.type]) {
                jsonError = i18n("Block %1: unknown type “%2”", i + 1, b.type)
                return
            }
            if (seen[b.id]) {
                jsonError = i18n("Block %1: the id “%2” is used twice", i + 1, b.id)
                return
            }
            seen[b.id] = true
        }
        jsonError = ""
        blocks = parsed
        selected = Math.min(selected, parsed.length - 1)
        save()
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
            out.push(i18nc("schema: parameter value", String(md.names[i])))
        return out
    }
    function enumIndex(md) {
        for (let i = 0; i < md.values.length; i++)
            if (String(md.values[i]) === String(md.value))
                return i
        return 0
    }

    // What this machine has, for the pick lists: the widget's own registry for sensors
    // and interfaces, df for the mount points (pseudo filesystems left out).
    SensorRegistry { id: registry }

    property var mounts: []

    P5Support.DataSource {
        engine: "executable"
        interval: 0
        connectedSources: ["timeout 5 df -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x overlay --output=target 2>/dev/null | tail -n +2"]
        onNewData: function(source, data) {
            page.mounts = String(data.stdout).trim().split("\n").filter(m => m.length > 0)
            disconnectSource(source)
        }
    }

    function candidates(md) {
        switch (md.pick) {
        case "sensor": return registry.match(md.pattern.length > 0 ? md.pattern : ".")
        case "iface": return registry.interfaces
        case "mount": return page.mounts
        }
        return []
    }

    // A stringlist value as a JS array of strings, whatever list type it arrived as.
    function listOf(value) {
        const out = []
        for (let i = 0; value && i < value.length; i++)
            out.push(String(value[i]))
        return out
    }

    ListModel { id: listModel }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: true
            text: i18n("The blocks and their order. The default layout comes from schema/widget.json.")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 16

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    model: listModel
                    clip: true
                    currentIndex: page.selected
                    onCurrentIndexChanged: page.selected = currentIndex

                    delegate: ItemDelegate {
                        width: list.width
                        highlighted: ListView.isCurrentItem
                        onClicked: page.selected = index

                        contentItem: RowLayout {
                            CheckBox {
                                checked: model.isOn
                                onToggled: {
                                    const copy = JSON.parse(JSON.stringify(page.blocks))
                                    copy[index].enabled = checked
                                    page.blocks = copy
                                    page.save()
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Label { text: model.title }
                                Label {
                                    text: model.subtitle
                                    opacity: 0.6
                                    font: Kirigami.Theme.smallFont
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop

                Button {
                    icon.name: "go-up"
                    text: i18n("Up")
                    enabled: page.selected > 0
                    onClicked: page.move(page.selected, page.selected - 1)
                }

                Button {
                    icon.name: "go-down"
                    text: i18n("Down")
                    enabled: page.selected >= 0 && page.selected < page.blocks.length - 1
                    onClicked: page.move(page.selected, page.selected + 1)
                }

                Button {
                    icon.name: "edit-copy"
                    text: i18n("Duplicate")
                    enabled: page.selected >= 0
                    onClicked: page.duplicateBlock(page.selected)
                }

                Button {
                    icon.name: "list-remove"
                    text: i18n("Remove")
                    enabled: page.selected >= 0
                    onClicked: page.removeBlock(page.selected)
                }

                Button {
                    icon.name: "edit-reset"
                    text: i18n("Reset")
                    onClicked: { page.cfg_blocksJson = ""; page.load() }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            ComboBox {
                id: typeBox
                Layout.fillWidth: true
                model: page.types
                textRole: "name"
            }

            Button {
                icon.name: "list-add"
                text: i18n("Add block")
                enabled: typeBox.currentIndex >= 0
                onClicked: page.addBlock(page.types[typeBox.currentIndex].type)
            }
        }

        // The block's own fields: a name of yours, to tell two of a kind apart in the
        // list, and the column it is drawn in.
        Kirigami.FormLayout {
            Layout.fillWidth: true
            visible: page.selected >= 0

            TextField {
                Kirigami.FormData.label: i18n("Name:")
                Layout.fillWidth: true
                text: page.selected >= 0 ? String(page.blocks[page.selected].name || "") : ""
                placeholderText: i18nc("placeholder for the block's own name", "optional, shown in the list")
                onEditingFinished: page.setField("name", text)
            }

            ComboBox {
                Kirigami.FormData.label: i18n("Column:")
                model: [i18nc("the widget's column", "left"), i18nc("the widget's column", "right")]
                currentIndex: (page.selected >= 0 && Number(page.blocks[page.selected].column) === 2) ? 1 : 0
                onActivated: page.setField("column", currentIndex === 1 ? 2 : 1)
            }

            // The block's lines as active lines: off, they take no clicks; a command of
            // the user's own goes first in the menu and runs on a left click, with the
            // row's values filled in.
            CheckBox {
                Kirigami.FormData.label: i18n("Active:")
                text: i18n("the block's lines take clicks")
                checked: page.selected >= 0 ? page.blocks[page.selected].active !== false : true
                onToggled: page.setField("active", checked)
            }

            TextField {
                Kirigami.FormData.label: i18n("Click:")
                Layout.fillWidth: true
                text: page.selected >= 0 ? String(page.blocks[page.selected].click || "") : ""
                placeholderText: i18nc("placeholder for the block's own click command", "a command of your own; {name} {pid} {path} {unit} {value} are filled in")
                onEditingFinished: page.setField("click", text)
            }
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            visible: page.params.length > 0

            Repeater {
                model: page.params

                // The parameter editor is picked by the type from the vocabulary.
                Item {
                    required property var modelData
                    Kirigami.FormData.label: i18nc("schema: parameter name", modelData.name) + ":"
                    implicitWidth: row.implicitWidth
                    implicitHeight: row.implicitHeight

                    RowLayout {
                        id: row

                        CheckBox {
                            visible: modelData.type === "bool"
                            checked: modelData.type === "bool" ? modelData.value : false
                            onToggled: page.setParam(modelData.key, checked)
                        }

                        SpinBox {
                            visible: modelData.type === "int"
                            from: modelData.min
                            to: modelData.max
                            value: modelData.type === "int" ? modelData.value : 0
                            onValueModified: page.setParam(modelData.key, value)
                        }

                        ComboBox {
                            visible: modelData.type === "enum"
                            model: modelData.type === "enum" ? page.enumNames(modelData) : []
                            currentIndex: modelData.type === "enum" ? page.enumIndex(modelData) : 0
                            onActivated: page.setParam(modelData.key, String(modelData.values[currentIndex]))
                        }

                        TextField {
                            visible: modelData.type === "string" || modelData.type === "stringlist"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                            text: modelData.type === "stringlist"
                                  ? page.listOf(modelData.value).join(", ")
                                  : String(modelData.value || "")
                            onEditingFinished: {
                                if (modelData.type === "stringlist")
                                    page.setParam(modelData.key,
                                        text.split(",").map(s => s.trim()).filter(s => s.length > 0))
                                else
                                    page.setParam(modelData.key, text)
                            }
                        }

                        // The machine's own list where the vocabulary says "pick": a choice
                        // replaces a string, or is added to a list — the field stays the
                        // place to type, so an id the machine has not got yet can be kept.
                        ComboBox {
                            id: picker
                            visible: (modelData.type === "string" || modelData.type === "stringlist")
                                     && modelData.pick.length > 0
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                            model: visible ? page.candidates(modelData) : []
                            currentIndex: -1
                            displayText: count > 0
                                ? i18ncp("pick list: how many the machine offers", "pick from %1…", "pick from %1…", count)
                                : i18nc("pick list: the machine offers nothing", "nothing found")
                            onActivated: {
                                const chosen = String(model[currentIndex])
                                if (modelData.type === "stringlist") {
                                    const cur = page.listOf(modelData.value)
                                    if (cur.indexOf(chosen) < 0)
                                        cur.push(chosen)
                                    page.setParam(modelData.key, cur)
                                } else {
                                    page.setParam(modelData.key, chosen)
                                }
                                currentIndex = -1
                            }
                        }
                    }
                }
            }
        }

        // The whole layout as text: to read, to copy to another machine, to edit at once.
        Label {
            text: i18n("The layout as JSON — edit here, or paste one from another machine:")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        TextArea {
            id: jsonArea
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 10
            font.family: "monospace"
            wrapMode: TextEdit.NoWrap
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            visible: page.jsonError.length > 0
            text: page.jsonError
        }

        RowLayout {
            Button {
                icon.name: "dialog-ok-apply"
                text: i18n("Apply JSON")
                onClicked: page.applyJson(jsonArea.text)
            }

            Button {
                icon.name: "view-refresh"
                text: i18n("Reload from the list")
                onClicked: { page.jsonError = ""; jsonArea.text = JSON.stringify(page.blocks, null, 2) }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
