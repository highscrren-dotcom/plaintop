import QtQuick
import plaintop

// The monitor's window host. The data and the drawing are the shared files
// (monitor/shared/, copied in by win/build.py), the menu of an active line is the
// plasmoid's ActionMenu.qml copied beside them; this file is the shell-facing part —
// size, settings, the mouse — with the same shape as the plasmoid's main.qml.
import "monitor"
import "monitor/description.js" as Description

WidgetWindow {
    id: root
    widget: "monitor"

    width: num("widgetWidth", 500)
    height: num("widgetHeight", 950)

    // What to show and in which order comes from the description: the user's edit from
    // the settings as a JSON string, or the one generated from schema/widget.json.
    readonly property var blocks: {
        const raw = str("blocksJson", "")
        if (raw.length > 0) {
            try {
                const parsed = JSON.parse(raw)
                if (Array.isArray(parsed) && parsed.length > 0)
                    return parsed
            } catch (e) {
                console.warn("plaintop: the description in the settings does not parse, using the packaged one:", e)
            }
        }
        return Description.BLOCKS
    }

    // The configured family when it is installed, else the system's monospace face.
    readonly property string face: Qt.fontFamilies().includes(str("fontFamily")) ? str("fontFamily") : "monospace"

    TextMetrics {
        id: cell
        font.family: root.face
        font.pointSize: root.num("fontSize", 10)
        text: "0"
    }

    readonly property real secondX: num("secondColumn", 0) > 0 ? num("secondColumn", 0) : Math.round(width / 2)
    readonly property bool actionsOn: flag("actions", false)
    // For the stand (tests/win_hosts.qml): what the view draws.
    readonly property var lines: monitorData.lines

    MonitorData {
        id: monitorData
        blocks: root.blocks
        rate: root.num("updateInterval", 1000)
        processInterval: root.num("processInterval", 2)
        barWidth: root.num("barWidth", 18)
        barFill: root.str("barFill", "/")
        barEmpty: root.str("barEmpty", "")
        separatorChar: root.str("separatorChar", "-")
        separatorWidth: root.num("separatorWidth", 35)
        sparkGlyphs: root.str("sparkGlyphs", "▁▂▃▄▅▆▇█")
        actions: root.actionsOn
        // The service answers these by their base name, wherever they are said to be.
        servicesScript: "win/service/services.sh"
        healthScript: "win/service/health.sh"
        columns: Math.max(20, Math.floor(((monitorData.twoColumns ? root.secondX : root.width) - root.num("padLeft", 48))
                                         / Math.max(1, cell.advanceWidth)))
        columns2: Math.max(20, Math.floor((root.width - root.secondX) / Math.max(1, cell.advanceWidth)))
    }

    MonitorView {
        id: view
        anchors.fill: parent
        lines: monitorData.lines
        lines2: monitorData.lines2
        secondColumn: root.secondX

        fontFamily: root.face
        fontSize: root.num("fontSize", 10)
        padLeft: root.num("padLeft", 48)
        padTop: root.num("padTop", 44)

        colorFg: root.str("colorFg", "#C8CCD4")
        colorAccent: root.str("colorAccent", "#E05561")
        colorDim: root.str("colorDim", "#6B7280")
        colorValue: root.str("colorValue", "#8FB6E0")

        onActivate: (action, button, column, index, area) => {
            anchor.x = area.x; anchor.y = area.y; anchor.width = area.width; anchor.height = area.height
            const items = action.items || []
            const first = items.length > 0 ? items[0] : null
            if (button === Qt.RightButton || first === null) {
                view.framedColumn = column; view.framedIndex = index
                menu.openMenu(action, anchor)
            } else if (first.confirm === true) {
                view.framedColumn = column; view.framedIndex = index
                menu.ask(action, first, anchor)
            } else {
                root.runItem(action.title, first)
            }
        }
    }

    // The service does not answer: say so where the lines would be.
    Text {
        visible: root.serviceDown && monitorData.lines.length === 0
        x: root.num("padLeft", 48); y: root.num("padTop", 44)
        color: root.str("colorDim", "#6B7280")
        font.family: root.face
        font.pointSize: root.num("fontSize", 10)
        textFormat: Text.PlainText
        text: root.i18n("no data: the plaintop service does not answer\nport %1", Service.port)
    }

    // ── the actions ───────────────────────────────────────────────────────────
    // The items are shell commands written for Linux; the service runs what it can
    // translate (win/PROTOCOL.md) and refuses the rest with a notice. Off by default
    // on Windows (settings_store.py).
    property string lastTitle: ""
    function runItem(title, it) {
        if (!it) return
        if (it.configure === true) {
            Service.postJson("/ui", { settings: "monitor" })
            return
        }
        root.lastTitle = String(title || "")
        Service.postJson("/exec", { command: String(it.run || ""), action: true, terminal: it.terminal === true,
                                    hold: it.hold === true, gui: it.gui === true, editor: it.editor === true },
                         function(d) {
            const code = d ? Number(d["exit code"]) : 127
            if (code !== 0 && !isNaN(code)) {
                const err = String((d && d.stderr) || "").trim().split("\n")[0]
                menu.notice(root.lastTitle, err.length > 0 ? err
                            : root.i18nc("a line action failed: its exit code", "exit code %1", code), anchor)
            }
        })
    }

    Item { id: anchor; visible: false; width: 1; height: 1 }

    ActionMenu {
        id: menu
        fontFamily: root.face
        fontSize: root.num("fontSize", 10)
        colorFg: root.str("colorFg", "#C8CCD4")
        colorAccent: root.str("colorAccent", "#E05561")
        colorDim: root.str("colorDim", "#6B7280")
        colorValue: root.str("colorValue", "#8FB6E0")
        colorPaper: root.str("colorPaper", "#141820")
        paperOpacity: root.num("paperOpacity", 94)
        frame: root.str("frame", "┌─┐│└┘├┤")
        onRun: it => root.runItem(menu.action ? menu.action.title : "", it)
        onVisibleChanged: if (!visible) { view.framedColumn = -1; view.framedIndex = -1 }
    }
}
