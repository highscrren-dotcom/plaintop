import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "../code/description.js" as Description

// The page is built from the vocabulary of block types (schema/blocks.json → description.js),
// not from a hardcoded list: a new block type must not require UI changes.
KCM.SimpleKCM {
    id: page

    property string cfg_blocksJson: ""

    // Working copy of the description; it goes into the settings as a JSON string.
    property var blocks: []
    property int selected: -1

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
            listModel.append({
                title: spec.name || b.type,
                subtitle: b.id + (spec.hint ? " — " + spec.hint : ""),
                isOn: b.enabled !== false
            })
        }
        selected = Math.min(keep, blocks.length - 1)
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
            out.push({ type: key, name: Description.VOCAB[key].name || key })
        return out
    }

    function addBlock(type) {
        const spec = Description.VOCAB[type]
        if (!spec) return
        const params = ({})
        for (const key in (spec.params || {})) params[key] = spec.params[key].default
        // The id must be unique: it tells the block apart from siblings of the same type.
        let n = 1
        while (blocks.some(b => b.id === type + n)) n++
        const copy = blocks.slice()
        const at = selected >= 0 ? selected + 1 : copy.length
        copy.splice(at, 0, { id: type + n, type: type, enabled: true, params: params })
        blocks = copy
        selected = at
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
                       max: d.max !== undefined ? d.max : 999 })
        }
        return out
    }

    ListModel { id: listModel }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: true
            text: i18n("Порядок и набор блоков. Раскладка по умолчанию берётся из schema/widget.json.")
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
                    text: i18n("Выше")
                    enabled: page.selected > 0
                    onClicked: page.move(page.selected, page.selected - 1)
                }

                Button {
                    icon.name: "go-down"
                    text: i18n("Ниже")
                    enabled: page.selected >= 0 && page.selected < page.blocks.length - 1
                    onClicked: page.move(page.selected, page.selected + 1)
                }

                Button {
                    icon.name: "list-remove"
                    text: i18n("Убрать")
                    enabled: page.selected >= 0
                    onClicked: page.removeBlock(page.selected)
                }

                Button {
                    icon.name: "edit-reset"
                    text: i18n("Сбросить")
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
                text: i18n("Добавить блок")
                enabled: typeBox.currentIndex >= 0
                onClicked: page.addBlock(page.types[typeBox.currentIndex].type)
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
                    Kirigami.FormData.label: modelData.name + ":"
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

                        TextField {
                            visible: modelData.type === "string" || modelData.type === "stringlist"
                            text: modelData.type === "stringlist"
                                  ? (modelData.value || []).join(", ")
                                  : String(modelData.value || "")
                            onEditingFinished: {
                                if (modelData.type === "stringlist")
                                    page.setParam(modelData.key,
                                        text.split(",").map(s => s.trim()).filter(s => s.length > 0))
                                else
                                    page.setParam(modelData.key, text)
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
