import QtQuick
import org.kde.plasma.core as PlasmaCore

// The sticker: a day's entries and the note of yours on a sheet framed with characters,
// in a popup window placed by the clicked cell. PlasmaCore.Dialog is the one way to put
// a window next to an item under Wayland (it goes through the shell's own protocol);
// nothing of Plasma's look is used — NoBackground, our flat sheet, the widget's font and
// palette, every line of the frame a line of text like the rest of the widgets.
//
// The sheet is a column of rows: borders, the title, the entries grouped by account, a
// separator, the editable note, a separator, a hint. The rows are laid out all at once —
// the window takes its size from them and must not grow while it opens — and the
// "unfold" animation only reveals them one by one.
PlasmaCore.Dialog {
    id: sticker

    type: PlasmaCore.Dialog.PopupMenu
    location: PlasmaCore.Types.Floating
    backgroundHints: PlasmaCore.Dialog.NoBackground
    hideOnWindowDeactivate: true

    // Set by the host for each opening.
    property string dateKey: ""
    property var entries: []           // the day's entries, as notes.py lists them
    property var accounts: []          // the document's accounts: names and errors
    property string noteAccount: "local"

    property string fontFamily: "JetBrainsMono Nerd Font Mono"
    property int fontSize: 10
    property color colorFg: "#C8CCD4"
    property color colorAccent: "#E05561"
    property color colorDim: "#6B7280"
    property color colorNote: "#8FB6E0"
    property color colorPaper: "#141820"
    property int paperOpacity: 94
    // Eight characters: top-left, horizontal, top-right, vertical, bottom-left,
    // bottom-right, and the separator's two junctions.
    property string frame: "┌─┐│└┘├┤"
    property int columns: 40
    property int animation: 2          // 0 none, 1 fade, 2 unfold

    // The note as it was when the sheet opened; a changed text is handed back on close.
    property string original: ""
    // The note as it is: the editor sits in a Repeater delegate — its id is not visible
    // here, and the delegate is rebuilt when the rows change — so the text lives on the
    // sticker, and the delegate that is the editor row registers its TextEdit.
    property string noteText: ""
    property TextEdit editorItem: null
    signal save(string dateKey, string text)

    function open(key, dayEntries, anchor) {
        const list = dayEntries || []
        let own = ""
        for (let i = 0; i < list.length; i++) {
            const e = list[i]
            if (e.own && e.account === noteAccount) {
                own = e.summary + (e.description.length > 0 ? "\n" + e.description : "")
                break
            }
        }
        // The text first: a rebuilt editor row takes it as it is created.
        original = own
        noteText = own
        if (editorItem)
            editorItem.text = own
        dateKey = key
        entries = list
        visualParent = anchor
        revealed = animation === 2 ? 0 : 1000
        visible = true
    }

    onVisibleChanged: {
        if (visible) {
            if (animation === 2)
                unfold.restart()
            if (editorItem) {
                editorItem.forceActiveFocus()
                editorItem.cursorPosition = editorItem.length
            }
        } else if (noteText !== original) {
            save(dateKey, noteText)
        }
    }

    // ── The frame ─────────────────────────────────────────────────────────────
    readonly property var f: {
        const a = Array.from(frame)
        while (a.length < 8) a.push(a.length === 1 ? a[0] : "+")
        return a
    }
    readonly property int width_: Math.max(20, columns)
    function pad(text) {
        const chars = Array.from(text)
        if (chars.length > width_)
            return chars.slice(0, width_ - 1).join("") + "…"
        return text + " ".repeat(width_ - chars.length)
    }
    function framed(text) { return f[3] + " " + pad(text) + " " + f[3] }
    readonly property string top: f[0] + f[1].repeat(width_ + 2) + f[2]
    readonly property string bottom: f[4] + f[1].repeat(width_ + 2) + f[5]
    readonly property string separator: f[6] + f[1].repeat(width_ + 2) + f[7]

    // ── The rows ──────────────────────────────────────────────────────────────
    // Each row is {text, role} or {editor: true}; the title names the day, the entries
    // come grouped under their account's name, the note of yours sits in the editor.
    function accountName(id) {
        for (let i = 0; i < accounts.length; i++)
            if (accounts[i].id === id)
                return accounts[i].name || id
        return id
    }
    function accountError(id) {
        for (let i = 0; i < accounts.length; i++)
            if (accounts[i].id === id)
                return accounts[i].error || ""
        return ""
    }
    readonly property var rows: {
        const out = []
        const p = dateKey.split("-").map(Number)
        const day = p.length === 3 ? new Date(p[0], p[1] - 1, p[2]) : new Date()
        out.push({ text: top, role: "dim" })
        out.push({ text: framed(day.toLocaleDateString(Qt.locale(), "dddd, d MMMM yyyy").toUpperCase()), role: "accent" })
        // The entries by account, the local ones first, the note of yours left to the editor.
        const groups = []
        for (let i = 0; i < entries.length; i++) {
            const e = entries[i]
            if (e.own && e.account === noteAccount)
                continue
            let g = null
            for (const x of groups) if (x.id === e.account) g = x
            if (g === null) {
                g = { id: e.account, items: [] }
                groups.push(g)
            }
            g.items.push(e)
        }
        if (groups.length > 0)
            out.push({ text: separator, role: "dim" })
        for (const g of groups) {
            const err = accountError(g.id)
            out.push({ text: framed(accountName(g.id) + (err.length > 0 ? "  · " + i18nc("the account's last fetch failed", "offline") : "")), role: "dim" })
            for (const e of g.items) {
                let head = ""
                if (e.kind === "todo")
                    head = (e.done ? "[x] " : "[ ] ")
                else if (e.time.length > 0)
                    head = e.time + " "
                out.push({ text: framed(head + e.summary), role: e.done ? "dim" : "fg" })
                if (e.description.length > 0)
                    out.push({ text: framed("  " + e.description.split("\n")[0]), role: "dim" })
            }
        }
        out.push({ text: separator, role: "dim" })
        out.push({ editor: true })
        out.push({ text: separator, role: "dim" })
        const where = noteAccount === "local" ? "" : "  · " + accountName(noteAccount)
        out.push({ text: framed(i18nc("the sticker's hint line", "Esc closes · an empty note deletes it") + where), role: "dim" })
        out.push({ text: bottom, role: "dim" })
        return out
    }

    // ── Animation ─────────────────────────────────────────────────────────────
    property int revealed: 1000

    function paint(role) {
        switch (role) {
        case "accent": return sticker.colorAccent
        case "dim": return sticker.colorDim
        case "note": return sticker.colorNote
        default: return sticker.colorFg
        }
    }

    component Line: Text {
        color: sticker.colorFg
        font.family: sticker.fontFamily
        font.pointSize: sticker.fontSize
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
    }

    mainItem: Item {
        id: sheet
        // A Dialog's default property is mainItem: an object declared at its root
        // is assigned there, and a second one fails the component — so the
        // timer and the metrics live in the sheet.
        Timer {
            id: unfold
            interval: 22
            repeat: true
            running: false
            onTriggered: {
                sticker.revealed++
                if (sticker.revealed > sticker.rows.length)
                    stop()
            }
        }

        TextMetrics {
            id: cell
            font.family: sticker.fontFamily
            font.pointSize: sticker.fontSize
            text: "0"
        }

        implicitWidth: column.width
        implicitHeight: column.height

        Rectangle {
            anchors.fill: column
            color: sticker.colorPaper
            opacity: sticker.paperOpacity / 100
        }

        Column {
            id: column
            spacing: 0
            // The fade: the whole sheet from nothing to itself on opening.
            opacity: sticker.visible || sticker.animation !== 1 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: sticker.animation === 1 ? 140 : 0 } }

            Repeater {
                model: sticker.rows.length

                Item {
                    id: row
                    required property int index
                    readonly property var spec: sticker.rows[index] || ({ text: "", role: "dim" })
                    readonly property bool isEditor: spec.editor === true
                    function claim() {
                        if (!isEditor) return
                        editor.text = sticker.noteText
                        sticker.editorItem = editor
                    }
                    onIsEditorChanged: claim()
                    Component.onCompleted: claim()
                    Component.onDestruction: if (sticker.editorItem === editor) sticker.editorItem = null
                    width: isEditor ? editRow.width : lineText.width
                    height: isEditor ? editRow.height : lineText.height
                    // The unfold: rows below the counter are laid out but not yet drawn.
                    opacity: index < sticker.revealed ? 1 : 0

                    Line {
                        id: lineText
                        visible: !row.isEditor
                        text: row.isEditor ? "" : row.spec.text
                        color: sticker.paint(row.isEditor ? "dim" : row.spec.role)
                    }

                    // The editor row: the frame's sides stand beside the text field, one
                    // character per line of it, so the frame grows with the note.
                    Row {
                        id: editRow
                        visible: row.isEditor
                        spacing: 0

                        Line {
                            text: (sticker.f[3] + " \n").repeat(Math.max(1, editor.lineCount)).replace(/\s+$/, "")
                            color: sticker.colorDim
                        }
                        TextEdit {
                            id: editor
                            width: sticker.width_ * cell.advanceWidth
                            font.family: sticker.fontFamily
                            font.pointSize: sticker.fontSize
                            color: sticker.colorNote
                            selectionColor: sticker.colorDim
                            wrapMode: TextEdit.Wrap
                            renderType: Text.NativeRendering
                            textFormat: TextEdit.PlainText
                            selectByMouse: true
                            onTextChanged: if (row.isEditor) sticker.noteText = text
                            Keys.onEscapePressed: sticker.visible = false
                        }
                        Line {
                            text: (" " + sticker.f[3] + "\n").repeat(Math.max(1, editor.lineCount)).replace(/\s+$/, "")
                            color: sticker.colorDim
                        }
                    }
                }
            }
        }
    }
}
