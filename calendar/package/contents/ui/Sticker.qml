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
    // The reminder choices: the hour an all-day note rings at, the settings' lead before a
    // timed one.
    property bool reminders: true
    property string remindHour: "09:00"
    property int remindLead: 10

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
    // The "time" and "remind" rows under the note. The time field's text, and the choice —
    // a lead before a timed note (-1: none), or the hour ("!") for an all-day one. On close
    // they go back into what the script reads: "14:30 …" or "!…" in front of the text, and
    // the lead. Typing "14:30 …" into the note itself still works.
    property string noteTime: ""
    property TextInput timeItem: null
    property int chosenLead: 10
    property bool chosenBang: false
    property string originalSig: ""
    signal save(string dateKey, string text, int lead)

    function validTime(t) {
        const m = String(t).match(/^\s*(\d{1,2})[:.](\d{2})\s*$/)
        return (m && Number(m[1]) < 24 && Number(m[2]) < 60) ? String(Number(m[1])).padStart(2, "0") + ":" + m[2] : ""
    }
    readonly property string timeSet: validTime(noteTime)
    // Timed: the field, or a time the note's text starts with ("9.00-10.30 Standup").
    readonly property bool timed: timeSet.length > 0 || /^\s*\d{1,2}[:.]\d{2}/.test(noteText)
    readonly property int leadDefault: remindLead > 0 ? remindLead : 10
    function leadText(l) {
        return l < 0 ? i18nc("the sticker's reminder choice", "none")
             : l === 60 ? i18nc("the sticker's reminder choice", "an hour before")
             : i18ncp("the sticker's reminder choice", "%1 min before", "%1 min before", l)
    }
    readonly property var allDayChoices: [
        { text: i18nc("the sticker's reminder choice", "none"), bang: false },
        { text: i18nc("the sticker's reminder choice: at an hour of the note's day", "at %1", remindHour), bang: true }
    ]
    readonly property var timedChoices: {
        const leads = [-1, leadDefault]
        if (leadDefault !== 60) leads.push(60)
        if (leads.indexOf(chosenLead) < 0) leads.push(chosenLead)
        return leads.map(l => ({ text: leadText(l), lead: l }))
    }
    readonly property var choices: timed ? timedChoices : allDayChoices
    function chosen(c) { return timed ? c.lead === chosenLead : c.bang === chosenBang }
    function choose(i) {
        const c = choices[i]
        if (!c) return
        if (timed) chosenLead = c.lead
        else chosenBang = c.bang
    }
    // What goes back: the text as the script reads it, and the lead.
    function composed() {
        const body = noteText
        if (body.trim().length === 0) return ""
        if (timeSet.length > 0) return timeSet + " " + body.replace(/^\s+/, "")
        if (!timed && chosenBang && !/^\s*!/.test(body)) return "!" + body
        return body
    }
    function signature() { return composed() + "|" + (timed ? chosenLead : "") }

    // The rows' labels and the choices laid out in lines within the frame; the number of
    // lines is the larger of the two sets', so the rows do not change while one types —
    // a change would rebuild every row, the editor too.
    readonly property string labelTime: i18nc("the sticker's time field", "time:")
    readonly property string labelRemind: i18nc("the sticker's reminder row", "remind:")
    readonly property int labelWidth: Math.max(Array.from(labelTime).length, Array.from(labelRemind).length) + 1
    function linesFor(set) {
        const room = width_ - labelWidth
        const out = [[]]
        let used = 0
        for (let i = 0; i < set.length; i++) {
            const w = Array.from(set[i].text).length + 2
            const line = out[out.length - 1]
            if (line.length > 0 && used + 1 + w > room) {
                out.push([i])
                used = w
            } else {
                used += (line.length > 0 ? 1 : 0) + w
                line.push(i)
            }
        }
        return out
    }
    readonly property var remindLines: linesFor(choices)
    readonly property int remindLineCount: Math.max(linesFor(allDayChoices).length, linesFor(timedChoices).length)
    function usedWidth(line) {
        let w = 0
        for (let j = 0; j < line.length; j++)
            w += (j > 0 ? 1 : 0) + Array.from(choices[line[j]].text).length + 2
        return w
    }

    function open(key, dayEntries, anchor) {
        const list = dayEntries || []
        let own = ""
        let ownEntry = null
        for (let i = 0; i < list.length; i++) {
            const e = list[i]
            if (e.own && e.account === noteAccount) {
                ownEntry = e
                // The script rebuilds the editor's text: the time or the "!" in front.
                own = (e.text !== undefined && e.text !== null && String(e.text).length > 0)
                    ? String(e.text)
                    : e.summary + (e.description.length > 0 ? "\n" + e.description : "")
                break
            }
        }
        // The time and the "!" leave the text for their rows; a range stays in the text.
        let time = ""
        let body = own
        let bang = false
        const m = own.match(/^(\d{1,2})[:.](\d{2})(?:[ \t]+|$)([\s\S]*)$/)
        if (m && validTime(m[1] + ":" + m[2]).length > 0) {
            time = validTime(m[1] + ":" + m[2])
            body = m[3]
        } else if (own.startsWith("!")) {
            bang = true
            body = own.slice(1)
        }
        chosenBang = bang
        chosenLead = (ownEntry && ownEntry.time && ownEntry.lead !== undefined) ? Number(ownEntry.lead) : leadDefault
        // The text first: a rebuilt editor row takes it as it is created.
        original = body
        noteText = body
        noteTime = time
        if (editorItem)
            editorItem.text = body
        if (timeItem)
            timeItem.text = time
        dateKey = key
        entries = list
        originalSig = signature()
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
        } else if (signature() !== originalSig) {
            save(dateKey, composed(), timed ? chosenLead : -1)
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
                // A task's box, an entry's time, and "!" on a note of yours that rings.
                let head = ""
                if (e.kind === "todo")
                    head = (e.done ? "[x] " : "[ ] ")
                else if (e.time.length > 0)
                    head = e.time + " "
                else if (e.own && e.alarm === true)
                    head = "!"
                out.push({ text: framed(head + e.summary), role: e.done ? "dim" : "fg" })
                if (e.description.length > 0)
                    out.push({ text: framed("  " + e.description.split("\n")[0]), role: "dim" })
            }
        }
        out.push({ text: separator, role: "dim" })
        out.push({ editor: true })
        out.push({ text: separator, role: "dim" })
        out.push({ time: true })
        for (let k = 0; k < remindLineCount; k++)
            out.push({ remind: true, line: k })
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
                    readonly property bool isTime: spec.time === true
                    readonly property bool isRemind: spec.remind === true
                    readonly property bool isPlain: !isEditor && !isTime && !isRemind
                    function claim() {
                        if (isEditor) {
                            editor.text = sticker.noteText
                            sticker.editorItem = editor
                        } else if (isTime) {
                            timeInput.text = sticker.noteTime
                            sticker.timeItem = timeInput
                        }
                    }
                    onIsEditorChanged: claim()
                    onIsTimeChanged: claim()
                    Component.onCompleted: claim()
                    Component.onDestruction: {
                        if (sticker.editorItem === editor) sticker.editorItem = null
                        if (sticker.timeItem === timeInput) sticker.timeItem = null
                    }
                    readonly property Item shownRow: isEditor ? editRow : isTime ? timeRow : isRemind ? remindRow : lineText
                    width: shownRow.width
                    height: shownRow.height
                    // The unfold: rows below the counter are laid out but not yet drawn.
                    opacity: index < sticker.revealed ? 1 : 0

                    // A framed row, "│ text │", keeps its sides in the frame's colour; only
                    // the text between them takes the row's.
                    readonly property var chars: row.isPlain ? Array.from(String(row.spec.text)) : []
                    readonly property bool sided: chars.length >= 4 && chars[0] === sticker.f[3]
                                                  && chars[chars.length - 1] === sticker.f[3]
                    Row {
                        id: lineText
                        visible: row.isPlain
                        Line {
                            text: row.sided ? row.chars.slice(0, 2).join("") : ""
                            color: sticker.colorDim
                        }
                        Line {
                            text: row.sided ? row.chars.slice(2, -2).join("") : row.chars.join("")
                            color: sticker.paint(row.isPlain ? row.spec.role : "dim")
                        }
                        Line {
                            text: row.sided ? row.chars.slice(-2).join("") : ""
                            color: sticker.colorDim
                        }
                    }

                    // The editor row: the frame's sides stand beside the text field, one
                    // character per line of it, so the frame grows with the note.
                    Row {
                        id: editRow
                        visible: row.isEditor
                        spacing: 0

                        Line {
                            text: (sticker.f[3] + " \n").repeat(Math.max(1, editor.lineCount)).replace(/\n$/, "")
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
                            text: (" " + sticker.f[3] + "\n").repeat(Math.max(1, editor.lineCount)).replace(/\n$/, "")
                            color: sticker.colorDim
                        }
                    }

                    // "│ time:    __:__        │" — the field takes digits; empty means all day.
                    Row {
                        id: timeRow
                        visible: row.isTime
                        Line { text: sticker.f[3] + " "; color: sticker.colorDim }
                        Line { text: sticker.labelTime.padEnd(sticker.labelWidth); color: sticker.colorDim }
                        TextInput {
                            id: timeInput
                            width: 5 * cell.advanceWidth
                            font.family: sticker.fontFamily
                            font.pointSize: sticker.fontSize
                            color: sticker.colorNote
                            selectionColor: sticker.colorDim
                            renderType: Text.NativeRendering
                            inputMask: "99:99;_"
                            selectByMouse: true
                            onTextEdited: if (row.isTime) sticker.noteTime = text
                            // Typing starts at the left: an empty field keeps the cursor at
                            // the first digit wherever the click lands, a set time is
                            // selected whole on focus, so new digits replace it.
                            readonly property bool blank: text.replace(/[^0-9]/g, "").length === 0
                            onCursorPositionChanged: if (activeFocus && blank && cursorPosition !== 0) cursorPosition = 0
                            onActiveFocusChanged: if (activeFocus) Qt.callLater(() => blank ? (cursorPosition = 0) : selectAll())
                            Keys.onEscapePressed: sticker.visible = false
                            Keys.onReturnPressed: if (sticker.editorItem) sticker.editorItem.forceActiveFocus()
                        }
                        Line { text: " ".repeat(Math.max(0, sticker.width_ - sticker.labelWidth - 5)) + " " + sticker.f[3]; color: sticker.colorDim }
                    }

                    // "│ remind: > none  10 min before  an hour before │" — a click chooses.
                    Row {
                        id: remindRow
                        visible: row.isRemind
                        readonly property var items: row.isRemind ? (sticker.remindLines[row.spec.line] || []) : []
                        Line { text: sticker.f[3] + " "; color: sticker.colorDim }
                        Line {
                            text: (row.spec.line === 0 ? sticker.labelRemind : "").padEnd(sticker.labelWidth)
                            color: sticker.colorDim
                        }
                        Repeater {
                            model: remindRow.items.length
                            Line {
                                required property int index
                                readonly property int choice: remindRow.items[index]
                                readonly property var c: sticker.choices[choice] || ({ text: "" })
                                readonly property bool marked: sticker.chosen(c)
                                text: (index > 0 ? " " : "") + (marked ? "> " : "  ") + c.text
                                color: marked ? sticker.colorNote : sticker.colorFg
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: sticker.choose(parent.choice)
                                }
                            }
                        }
                        Line {
                            text: " ".repeat(Math.max(0, sticker.width_ - sticker.labelWidth - sticker.usedWidth(remindRow.items))) + " " + sticker.f[3]
                            color: sticker.colorDim
                        }
                    }
                }
            }
        }
    }
}
