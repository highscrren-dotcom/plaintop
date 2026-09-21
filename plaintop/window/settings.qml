import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import org.kde.ksysguard.sensors as Sensors

import "description.js" as Description

// Settings editor for the standalone text monitor. The window host has no Plasma dialog
// behind it, so this is that dialog.
//
// It never touches the file: the relay owns monitor.json, this window reads
// GET /config?widget=monitor and sends changes with POST. QML cannot write files, and one
// owner beats two writers.
ApplicationWindow {
    id: app

    width: 1000
    height: 760
    visible: true
    title: "plaintop — настройки монитора"

    readonly property int port: 8788

    property var cfg: ({})
    property var blocks: []
    property bool loaded: false
    property int selected: -1

    function num(key, fallback) {
        const v = cfg[key]
        return (v === undefined || v === null) ? fallback : v
    }

    function load() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status !== 200) {
                status.text = "реле не отвечает на порту " + app.port
                return
            }
            app.cfg = JSON.parse(xhr.responseText)
            // Same fallback as the window host: with no blocks in the config, edit the
            // description that came with the package rather than an empty list.
            app.blocks = (app.cfg.blocks !== undefined && app.cfg.blocks.length > 0)
                         ? app.cfg.blocks : Description.BLOCKS
            app.loaded = true
            app.refreshList()
            status.text = "настройки прочитаны"
        }
        xhr.open("GET", "http://127.0.0.1:" + port + "/config?widget=monitor")
        xhr.send()
    }

    // Changes are collected and sent together: dragging a spin box would otherwise fire a
    // request per step.
    property var pending: ({})

    function change(key, value) {
        if (!loaded)
            return
        const copy = ({})
        for (const k in cfg) copy[k] = cfg[k]
        copy[key] = value
        cfg = copy
        pending[key] = value
        saveTimer.restart()
    }

    function saveBlocks() {
        change("blocks", blocks)
        refreshList()
    }

    Timer {
        id: saveTimer
        interval: 250
        onTriggered: {
            const body = JSON.stringify(app.pending)
            app.pending = ({})
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE)
                    status.text = xhr.status === 200 ? "сохранено" : "не сохранилось: " + xhr.status
            }
            xhr.open("POST", "http://127.0.0.1:" + app.port + "/config?widget=monitor")
            xhr.setRequestHeader("Content-Type", "application/json")
            xhr.send(body)
        }
    }

    Component.onCompleted: {
        load()
        loadMounts()
    }

    // ── What this machine offers ──────────────────────────────────────────────
    // Ids rot: a chip renumbers, an interface is renamed, a disk is unplugged. So the
    // editor never asks the user to know an id — it offers what the machine reports now.
    SensorRegistry { id: registry }

    readonly property var interfaces: {
        const out = []
        for (const id of registry.match("^network/(?!all)[^/]+/download$"))
            out.push(id.split("/")[1])
        return out
    }

    // Real filesystems only: /proc, cgroups and the rest of the pseudo mounts are noise.
    readonly property var fsTypes: ["ext2", "ext3", "ext4", "btrfs", "xfs", "f2fs", "zfs",
                                    "vfat", "exfat", "ntfs", "ntfs3", "fuseblk", "jfs",
                                    "reiserfs", "nfs", "nfs4", "cifs"]
    property var mounts: []

    function loadMounts() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            const seen = ({})
            const out = []
            for (const row of String(xhr.responseText).split("\n")) {
                const f = row.split(" ")
                if (f.length < 3 || app.fsTypes.indexOf(f[2]) < 0)
                    continue
                const path = f[1].replace(/\\040/g, " ")
                if (seen[path])
                    continue
                seen[path] = true
                out.push({ path: path, dev: f[0], fs: f[2] })
            }
            app.mounts = out
        }
        // The launcher sets QML_XHR_ALLOW_FILE_READ=1; without it the shell refuses file://.
        xhr.open("GET", "file:///proc/self/mounts")
        xhr.send()
    }

    function listValue(key) {
        if (selected < 0 || selected >= blocks.length)
            return []
        const b = blocks[selected]
        const spec = Description.VOCAB[b.type]
        const d = spec && spec.params ? spec.params[key] : null
        const v = (b.params && b.params[key] !== undefined) ? b.params[key]
                                                            : (d ? d.default : [])
        return Array.isArray(v) ? v : []
    }

    function addToList(key, value) {
        if (value.length === 0)
            return
        const cur = listValue(key)
        if (cur.indexOf(value) >= 0)
            return
        setParam(key, cur.concat([value]))
    }

    function removeFromList(key, value) {
        setParam(key, listValue(key).filter(x => x !== value))
    }

    function pickInto(key, pick, pattern, multi) {
        if (pick === "mount") {
            mountDialog.paramKey = key
            mountDialog.multi = multi
            mountManual.text = ""
            mountDialog.open()
            return
        }
        sensorDialog.paramKey = key
        sensorDialog.pattern = pattern
        sensorDialog.multi = multi
        sensorDialog.narrowed = pattern.length > 0
        sensorSearch.text = ""
        sensorManual.text = ""
        sensorDialog.open()
    }

    // ── Blocks ────────────────────────────────────────────────────────────────
    ListModel { id: listModel }

    readonly property var types: {
        const out = []
        for (const key in Description.VOCAB)
            out.push({ type: key, name: Description.VOCAB[key].name || key })
        return out
    }

    function refreshList() {
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
        if (to < 0 || to >= blocks.length)
            return
        const copy = blocks.slice()
        const item = copy.splice(from, 1)[0]
        copy.splice(to, 0, item)
        blocks = copy
        selected = to
        saveBlocks()
    }

    function addBlock(type) {
        const spec = Description.VOCAB[type]
        if (!spec)
            return
        const params = ({})
        for (const key in (spec.params || {}))
            params[key] = spec.params[key].default
        let n = 1
        while (blocks.some(b => b.id === type + n)) n++
        const copy = blocks.slice()
        const at = selected >= 0 ? selected + 1 : copy.length
        copy.splice(at, 0, { id: type + n, type: type, enabled: true, params: params })
        blocks = copy
        selected = at
        saveBlocks()
    }

    function removeBlock(i) {
        if (i < 0 || i >= blocks.length)
            return
        const copy = blocks.slice()
        copy.splice(i, 1)
        blocks = copy
        selected = Math.min(i, copy.length - 1)
        saveBlocks()
    }

    function setParam(key, value) {
        if (selected < 0)
            return
        const copy = JSON.parse(JSON.stringify(blocks))
        copy[selected].params = copy[selected].params || ({})
        copy[selected].params[key] = value
        blocks = copy
        saveBlocks()
    }

    function setEnabled(i, on) {
        const copy = JSON.parse(JSON.stringify(blocks))
        copy[i].enabled = on
        blocks = copy
        saveBlocks()
    }

    // Parameters of the selected block, read off the vocabulary: type, label, value.
    readonly property var params: {
        if (selected < 0 || selected >= blocks.length)
            return []
        const b = blocks[selected]
        const spec = Description.VOCAB[b.type]
        if (!spec || !spec.params)
            return []
        const out = []
        for (const key in spec.params) {
            const d = spec.params[key]
            const v = (b.params && b.params[key] !== undefined) ? b.params[key] : d.default
            out.push({ key: key, name: d.name, type: d.type, value: v,
                       pick: d.pick !== undefined ? d.pick : "",
                       pattern: d.pattern !== undefined ? d.pattern : "",
                       min: d.min !== undefined ? d.min : 0,
                       max: d.max !== undefined ? d.max : 999 })
        }
        return out
    }

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing

            TabBar {
                id: tabs
                Layout.fillWidth: true

                TabButton { text: "Вид" }
                TabButton { text: "Блоки" }
            }

            Label { id: status; text: "загрузка…" }

            Button {
                text: "Перечитать"
                onClicked: app.load()
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

    StackLayout {
        // The pickers made the blocks page wider, and its minimum width squeezed the
        // preview to nothing. The settings column is capped; the preview takes the rest.
        Layout.preferredWidth: 540
        Layout.maximumWidth: 560
        Layout.fillHeight: true
        currentIndex: tabs.currentIndex

        // ── Appearance ────────────────────────────────────────────────────────
        ScrollView {
            contentWidth: availableWidth

            Kirigami.FormLayout {
                width: parent.width

                Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Текст" }

                TextField {
                    Kirigami.FormData.label: "Шрифт:"
                    text: app.num("fontFamily", "JetBrainsMono Nerd Font Mono")
                    Layout.fillWidth: true
                    onEditingFinished: app.change("fontFamily", text)
                }

                SpinBox {
                    Kirigami.FormData.label: "Кегль:"
                    from: 6; to: 32
                    value: app.num("fontSize", 10)
                    onValueModified: app.change("fontSize", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Интервал обновления, мс:"
                    from: 200; to: 10000; stepSize: 100
                    value: app.num("updateInterval", 1000)
                    onValueModified: app.change("updateInterval", value)
                }

                Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Место" }

                SpinBox {
                    Kirigami.FormData.label: "Отступ слева, px:"
                    from: 0; to: 500; stepSize: 4
                    value: app.num("padLeft", 48)
                    onValueModified: app.change("padLeft", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Отступ сверху, px:"
                    from: 0; to: 500; stepSize: 4
                    value: app.num("padTop", 44)
                    onValueModified: app.change("padTop", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Ширина, px:"
                    from: 100; to: 2000; stepSize: 10
                    value: app.num("widgetWidth", 500)
                    onValueModified: app.change("widgetWidth", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Высота, px:"
                    from: 100; to: 2000; stepSize: 10
                    value: app.num("widgetHeight", 950)
                    onValueModified: app.change("widgetHeight", value)
                }

                Label {
                    text: "Размер и место окна держит правило KWin — после смены размера\nперезапустите: ./install.sh --plaintop-window"
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                }

                Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Палитра" }

                KQuickControls.ColorButton {
                    Kirigami.FormData.label: "Основной текст:"
                    color: app.num("colorFg", "#C8CCD4")
                    onColorChanged: app.change("colorFg", color.toString())
                }

                KQuickControls.ColorButton {
                    Kirigami.FormData.label: "Заголовок:"
                    color: app.num("colorAccent", "#E05561")
                    onColorChanged: app.change("colorAccent", color.toString())
                }

                KQuickControls.ColorButton {
                    Kirigami.FormData.label: "Второстепенное:"
                    color: app.num("colorDim", "#6B7280")
                    onColorChanged: app.change("colorDim", color.toString())
                }

                KQuickControls.ColorButton {
                    Kirigami.FormData.label: "Значения:"
                    color: app.num("colorValue", "#8FB6E0")
                    onColorChanged: app.change("colorValue", color.toString())
                }
            }
        }

        // ── Blocks ────────────────────────────────────────────────────────────
        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: true
                text: "Набор и порядок блоков. Правки уходят в монитор через две секунды."
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: list
                        model: listModel
                        clip: true
                        currentIndex: app.selected
                        onCurrentIndexChanged: app.selected = currentIndex

                        delegate: ItemDelegate {
                            width: list.width
                            highlighted: ListView.isCurrentItem
                            onClicked: app.selected = index

                            contentItem: RowLayout {
                                CheckBox {
                                    checked: model.isOn
                                    onToggled: app.setEnabled(index, checked)
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
                        text: "Выше"
                        icon.name: "go-up"
                        enabled: app.selected > 0
                        onClicked: app.move(app.selected, app.selected - 1)
                    }

                    Button {
                        text: "Ниже"
                        icon.name: "go-down"
                        enabled: app.selected >= 0 && app.selected < app.blocks.length - 1
                        onClicked: app.move(app.selected, app.selected + 1)
                    }

                    Button {
                        text: "Убрать"
                        icon.name: "list-remove"
                        enabled: app.selected >= 0
                        onClicked: app.removeBlock(app.selected)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                ComboBox {
                    id: typeBox
                    Layout.fillWidth: true
                    model: app.types
                    textRole: "name"
                }

                Button {
                    text: "Добавить блок"
                    icon.name: "list-add"
                    enabled: typeBox.currentIndex >= 0
                    onClicked: app.addBlock(app.types[typeBox.currentIndex].type)
                }
            }

            Kirigami.FormLayout {
                Layout.fillWidth: true
                visible: app.params.length > 0

                Repeater {
                    model: app.params

                    // The editor of a parameter comes from the vocabulary: "type" picks the
                    // widget, "pick" says what this machine can offer instead of a typed id.
                    Item {
                        id: pd
                        required property var modelData

                        readonly property bool isList: modelData.type === "stringlist"
                        // A list arrives here as a variant list, not as a JS array, so
                        // Array.isArray() says no. Copy it by length instead.
                        readonly property var listNow: {
                            if (!pd.isList)
                                return []
                            const v = pd.modelData.value
                            const out = []
                            for (let i = 0; v !== undefined && v !== null && i < v.length; i++)
                                out.push(String(v[i]))
                            return out
                        }
                        readonly property bool pickable: modelData.pick.length > 0
                        // Only a discovered id can fall back to "find it yourself"; a mount
                        // point is a choice, not something the widget can guess.
                        readonly property bool autoable: modelData.pick === "sensor"
                                                         || modelData.pick === "iface"

                        Kirigami.FormData.label: modelData.name + ":"
                        implicitWidth: col.implicitWidth
                        implicitHeight: col.implicitHeight

                        ColumnLayout {
                            id: col
                            spacing: Kirigami.Units.smallSpacing

                            CheckBox {
                                visible: pd.modelData.type === "bool"
                                checked: pd.modelData.type === "bool" ? pd.modelData.value : false
                                onToggled: app.setParam(pd.modelData.key, checked)
                            }

                            SpinBox {
                                visible: pd.modelData.type === "int"
                                from: pd.modelData.min
                                to: pd.modelData.max
                                value: pd.modelData.type === "int" ? pd.modelData.value : 0
                                onValueModified: app.setParam(pd.modelData.key, value)
                            }

                            // An interface is a short list — a menu beats a text field.
                            ComboBox {
                                visible: pd.modelData.pick === "iface"
                                Layout.minimumWidth: 280
                                model: ["— найти самому —"].concat(app.interfaces)
                                currentIndex: {
                                    const i = app.interfaces.indexOf(String(pd.modelData.value || ""))
                                    return i < 0 ? 0 : i + 1
                                }
                                onActivated: app.setParam(pd.modelData.key,
                                                          currentIndex === 0
                                                          ? "" : app.interfaces[currentIndex - 1])
                            }

                            // A single value: still typeable, with the picker beside it.
                            RowLayout {
                                visible: pd.modelData.type === "string"
                                         && pd.modelData.pick !== "iface"

                                TextField {
                                    Layout.minimumWidth: 260
                                    placeholderText: pd.autoable ? "пусто — найти самому" : ""
                                    text: String(pd.modelData.value || "")
                                    onEditingFinished: app.setParam(pd.modelData.key, text)
                                }

                                Button {
                                    visible: pd.pickable
                                    text: "Выбрать…"
                                    icon.name: "search"
                                    onClicked: app.pickInto(pd.modelData.key, pd.modelData.pick,
                                                            pd.modelData.pattern, false)
                                }

                                Button {
                                    visible: pd.autoable
                                    text: "Авто"
                                    icon.name: "edit-clear"
                                    onClicked: app.setParam(pd.modelData.key, "")
                                }
                            }

                            // A list: what is chosen, each row removable, plus the picker.
                            ColumnLayout {
                                visible: pd.isList
                                spacing: 2

                                Repeater {
                                    model: pd.listNow

                                    RowLayout {
                                        required property string modelData
                                        spacing: 0

                                        Label {
                                            text: modelData
                                            font: Kirigami.Theme.smallFont
                                        }

                                        Button {
                                            text: "✕"
                                            flat: true
                                            implicitWidth: implicitHeight
                                            onClicked: app.removeFromList(pd.modelData.key, modelData)
                                        }
                                    }
                                }

                                Label {
                                    visible: pd.listNow.length === 0
                                    text: pd.autoable ? "пусто — найти самим" : "ничего не выбрано"
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.7
                                }

                                RowLayout {
                                    Button {
                                        text: "Добавить…"
                                        icon.name: "list-add"
                                        enabled: pd.pickable
                                        onClicked: app.pickInto(pd.modelData.key, pd.modelData.pick,
                                                                pd.modelData.pattern, true)
                                    }

                                    Button {
                                        visible: pd.autoable && pd.listNow.length > 0
                                        text: "Авто"
                                        icon.name: "edit-clear"
                                        onClicked: app.setParam(pd.modelData.key, [])
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

        // Live preview: the very renderer the desktop uses, fed by a second data source
        // and scaled to fit. Edits show here before they even reach the file.
        Rectangle {
            Layout.fillWidth: true
            Layout.minimumWidth: 300
            Layout.fillHeight: true
            color: "#0c1420"
            radius: 4
            clip: true

            MonitorData {
                id: previewData
                blocks: app.blocks
                rate: app.num("updateInterval", 1000)
                servicesScript: Qt.resolvedUrl("services.sh").toString().replace("file://", "")
            }

            MonitorView {
                id: previewView
                width: app.num("widgetWidth", 500)
                height: app.num("widgetHeight", 950)
                anchors.centerIn: parent
                transformOrigin: Item.Center
                scale: Math.min(1, Math.min((parent.width - 16) / Math.max(1, width),
                                            (parent.height - 34) / Math.max(1, height)))

                lines: previewData.lines
                fontFamily: app.num("fontFamily", "JetBrainsMono Nerd Font Mono")
                fontSize: app.num("fontSize", 10)
                padLeft: app.num("padLeft", 48)
                padTop: app.num("padTop", 44)
                colorFg: app.num("colorFg", "#C8CCD4")
                colorAccent: app.num("colorAccent", "#E05561")
                colorDim: app.num("colorDim", "#6B7280")
                colorValue: app.num("colorValue", "#8FB6E0")
            }

            Label {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                color: "#6B7280"
                font: Kirigami.Theme.smallFont
                text: "живой просмотр · " + previewView.width + "x" + previewView.height
                      + " · масштаб " + previewView.scale.toFixed(2)
                      + " · строк " + previewData.lines.length
            }
        }
    }

    // ── Pickers ───────────────────────────────────────────────────────────────
    // The value of the highlighted sensor, live. One probe, not one per row: the tree has
    // hundreds of entries on this machine alone.
    Sensors.Sensor {
        id: probe
        sensorId: sensorDialog.visible ? sensorDialog.current : ""
        updateRateLimit: 500
    }

    Dialog {
        id: sensorDialog
        title: "Датчики этой машины"
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(app.width - 80, 780)
        height: Math.min(app.height - 80, 580)
        standardButtons: Dialog.Ok | Dialog.Cancel

        property string paramKey: ""
        property string pattern: ""
        property bool multi: false
        property bool narrowed: true

        readonly property var items: {
            const base = (narrowed && pattern.length > 0) ? registry.match(pattern) : registry.ids
            const q = sensorSearch.text.trim().toLowerCase()
            if (q.length === 0)
                return base
            return base.filter(id => id.toLowerCase().indexOf(q) >= 0)
        }

        readonly property string current: (sensorList.currentIndex >= 0
                                           && sensorList.currentIndex < items.length)
                                          ? items[sensorList.currentIndex] : ""

        function apply() {
            const typed = sensorManual.text.trim()
            const id = typed.length > 0 ? typed : current
            if (id.length === 0)
                return
            if (multi)
                app.addToList(paramKey, id)
            else
                app.setParam(paramKey, id)
        }

        onAccepted: apply()

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true

                TextField {
                    id: sensorSearch
                    Layout.fillWidth: true
                    placeholderText: "поиск: часть идентификатора"
                }

                CheckBox {
                    text: "только подходящие"
                    visible: sensorDialog.pattern.length > 0
                    checked: sensorDialog.narrowed
                    onToggled: sensorDialog.narrowed = checked
                }
            }

            Label {
                text: "показано " + sensorDialog.items.length + " из " + registry.ids.length
                      + (registry.ready ? "" : " · дерево ещё читается")
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }

            ListView {
                id: sensorList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: sensorDialog.items
                currentIndex: 0
                ScrollBar.vertical: ScrollBar {}

                delegate: ItemDelegate {
                    required property int index
                    required property string modelData
                    width: sensorList.width
                    text: modelData
                    highlighted: ListView.isCurrentItem
                    onClicked: sensorList.currentIndex = index
                    onDoubleClicked: {
                        sensorList.currentIndex = index
                        sensorDialog.apply()
                        sensorDialog.close()
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: probe.sensorId.length === 0
                      ? "—"
                      : probe.name + " · " + probe.formattedValue
                        + (probe.status === 2 ? "" : "  (данных нет)")
            }

            TextField {
                id: sensorManual
                Layout.fillWidth: true
                placeholderText: "или впишите идентификатор вручную"
            }
        }
    }

    Dialog {
        id: mountDialog
        title: "Точки монтирования этой машины"
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(app.width - 80, 720)
        height: Math.min(app.height - 80, 520)
        standardButtons: Dialog.Ok | Dialog.Cancel

        property string paramKey: ""
        property bool multi: false

        readonly property string current: (mountList.currentIndex >= 0
                                           && mountList.currentIndex < app.mounts.length)
                                          ? app.mounts[mountList.currentIndex].path : ""

        function apply() {
            const typed = mountManual.text.trim()
            const path = typed.length > 0 ? typed : current
            if (path.length === 0)
                return
            if (multi)
                app.addToList(paramKey, path)
            else
                app.setParam(paramKey, path)
        }

        onAccepted: apply()

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true

                Label {
                    Layout.fillWidth: true
                    text: "смонтировано сейчас: " + app.mounts.length
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }

                Button {
                    text: "Перечитать"
                    icon.name: "view-refresh"
                    onClicked: app.loadMounts()
                }
            }

            ListView {
                id: mountList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: app.mounts
                currentIndex: 0
                ScrollBar.vertical: ScrollBar {}

                delegate: ItemDelegate {
                    required property int index
                    required property var modelData
                    width: mountList.width
                    text: modelData.path
                    highlighted: ListView.isCurrentItem
                    onClicked: mountList.currentIndex = index
                    onDoubleClicked: {
                        mountList.currentIndex = index
                        mountDialog.apply()
                        mountDialog.close()
                    }

                    contentItem: ColumnLayout {
                        spacing: 0

                        Label { text: modelData.path }

                        Label {
                            text: modelData.dev + " · " + modelData.fs
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                        }
                    }
                }
            }

            TextField {
                id: mountManual
                Layout.fillWidth: true
                placeholderText: "или впишите путь вручную"
            }
        }
    }
}
