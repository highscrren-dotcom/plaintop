import QtQuick
import org.kde.plasma.core as PlasmaCore

// The menu of an active line: its title in the top border, its items one per row, the
// row under the pointer or the keyboard marked with ">", in a popup window framed with
// characters like the calendar's sticker — NoBackground, our own flat sheet, the widget's
// font and palette. The same window asks before a destructive item ("nginx.service:
// restart?" — yes / no, "no" marked) and shows a notice when a command fails. It only
// reports what was chosen (`run`); the host runs it.
//
// PlasmaCore.Dialog is the one way to put a window next to an item under Wayland; the
// host hands it an anchor item on the clicked line as visualParent.
PlasmaCore.Dialog {
    id: menu

    type: PlasmaCore.Dialog.PopupMenu
    // Below the anchor, centred on it; the host may set another edge.
    location: PlasmaCore.Types.TopEdge
    backgroundHints: PlasmaCore.Dialog.NoBackground
    hideOnWindowDeactivate: true

    property string fontFamily: "JetBrainsMono Nerd Font Mono"
    property int fontSize: 10
    property color colorFg: "#C8CCD4"
    property color colorAccent: "#E05561"
    property color colorDim: "#6B7280"
    property color colorValue: "#8FB6E0"
    property color colorPaper: "#141820"
    property int paperOpacity: 94
    // Eight characters: top-left, horizontal, top-right, vertical, bottom-left,
    // bottom-right, and two junctions (unused here, kept for one setting with the sticker).
    property string frame: "┌─┐│└┘├┤"

    // What is shown: the line's action, the mode, the item awaiting an answer, a notice.
    property var action: ({ title: "", items: [] })
    property int mode: 0               // 0 the items, 1 a question, 2 a notice
    property var pending: null
    property string noticeText: ""
    property int current: 0            // the marked option
    signal run(var item)

    function openMenu(act, anchor) {
        action = act
        mode = 0
        current = 0
        visualParent = anchor
        visible = true
    }
    // The question before a destructive item; "no" is marked, Enter leaves things be.
    function ask(act, it, anchor) {
        action = act
        pending = it
        mode = 1
        current = 1
        visualParent = anchor
        visible = true
    }
    function notice(title, text, anchor) {
        action = { title: title, items: [] }
        noticeText = String(text || "")
        mode = 2
        current = 0
        visualParent = anchor
        visible = true
    }

    // The options of the current mode: the items, yes/no, or ok.
    readonly property var options: {
        switch (mode) {
        case 1: return [i18nc("the question before a destructive action: proceed", "yes"),
                        i18nc("the question before a destructive action: leave it", "no")]
        case 2: return [i18nc("closes a notice", "ok")]
        }
        const out = []
        const items = (action && action.items) ? action.items : []
        for (let i = 0; i < items.length; i++) out.push(String(items[i].text))
        return out
    }

    readonly property string heading: {
        const t = (action && action.title) ? String(action.title) : ""
        if (mode === 1 && pending)
            return (t.length > 0 ? t + ": " : "") + String(pending.text) + "?"
        return t
    }

    function choose(index) {
        if (index < 0 || index >= options.length) return
        if (mode === 0) {
            const it = action.items[index]
            if (it.confirm) {
                pending = it
                mode = 1
                current = 1
                return
            }
            visible = false
            run(it)
        } else if (mode === 1) {
            const it = pending
            visible = false
            if (index === 0) run(it)
        } else {
            visible = false
        }
    }

    onVisibleChanged: if (visible) sheet.forceActiveFocus()

    // ── The frame ─────────────────────────────────────────────────────────────
    readonly property var f: {
        const a = Array.from(frame)
        while (a.length < 8) a.push(a.length === 1 ? a[0] : "+")
        return a
    }
    // Wide enough for the title and the longest option, within reason.
    readonly property int width_: {
        let w = Array.from(heading).length + 2
        for (let i = 0; i < options.length; i++) w = Math.max(w, Array.from(options[i]).length + 2)
        const lines = noticeLines
        for (let i = 0; i < lines.length; i++) w = Math.max(w, Array.from(lines[i]).length)
        return Math.max(16, Math.min(60, w))
    }
    readonly property var noticeLines: {
        if (mode !== 2) return []
        return noticeText.split("\n").filter(l => l.trim().length > 0).slice(0, 6)
    }
    function pad(text, width) {
        const chars = Array.from(text)
        if (chars.length > width)
            return chars.slice(0, Math.max(0, width - 1)).join("") + "…"
        return text + " ".repeat(width - chars.length)
    }
    function framed(text) { return f[3] + " " + pad(text, width_) + " " + f[3] }
    // The title sits in the top border: "┌─ nginx.service ─────┐".
    readonly property string top: {
        const t = Array.from(heading).length > 0 ? " " + pad(heading, Math.min(Array.from(heading).length, width_ - 2)) + " " : ""
        return f[0] + f[1] + t + f[1].repeat(Math.max(0, width_ + 1 - Array.from(t).length)) + f[2]
    }
    readonly property string bottom: f[4] + f[1].repeat(width_ + 2) + f[5]

    // The rows: {text, role, pick} — pick is the option's index, or -1 for a border or a
    // notice line.
    readonly property var rows: {
        const out = [{ text: top, role: "dim", pick: -1 }]
        for (let i = 0; i < noticeLines.length; i++)
            out.push({ text: framed(noticeLines[i]), role: "fg", pick: -1 })
        for (let i = 0; i < options.length; i++)
            out.push({ text: framed((i === current ? "> " : "  ") + options[i]),
                       role: i === current ? "value" : "fg", pick: i })
        out.push({ text: bottom, role: "dim", pick: -1 })
        return out
    }

    function paint(role) {
        switch (role) {
        case "accent": return menu.colorAccent
        case "dim": return menu.colorDim
        case "value": return menu.colorValue
        default: return menu.colorFg
        }
    }

    mainItem: Item {
        id: sheet
        implicitWidth: column.width
        implicitHeight: column.height
        // PlasmaCore.Dialog sizes its window from the sheet's width and height and, on
        // its resize, sets them back: a binding to the implicit size would be broken and
        // the window would keep its first size. Re-apply it on every change instead.
        onImplicitWidthChanged: width = implicitWidth
        onImplicitHeightChanged: height = implicitHeight
        focus: true

        Keys.onEscapePressed: menu.visible = false
        Keys.onUpPressed: menu.current = (menu.current + menu.options.length - 1) % Math.max(1, menu.options.length)
        Keys.onDownPressed: menu.current = (menu.current + 1) % Math.max(1, menu.options.length)
        Keys.onReturnPressed: menu.choose(menu.current)
        Keys.onEnterPressed: menu.choose(menu.current)
        Keys.onSpacePressed: menu.choose(menu.current)

        Rectangle {
            anchors.fill: column
            color: menu.colorPaper
            opacity: menu.paperOpacity / 100
        }

        Column {
            id: column
            spacing: 0
            // A short fade in; nothing moves.
            opacity: menu.visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 100 } }

            Repeater {
                model: menu.rows.length

                Item {
                    id: row
                    required property int index
                    readonly property var spec: menu.rows[index] || ({ text: "", role: "dim", pick: -1 })
                    width: rowText.width
                    height: rowText.height

                    Text {
                        id: rowText
                        text: row.spec.text
                        color: menu.paint(row.spec.role)
                        font.family: menu.fontFamily
                        font.pointSize: menu.fontSize
                        renderType: Text.NativeRendering
                        textFormat: Text.PlainText
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: row.spec.pick >= 0
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: menu.current = row.spec.pick
                        onClicked: menu.choose(row.spec.pick)
                    }
                }
            }
        }
    }
}
