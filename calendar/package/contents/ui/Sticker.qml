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
    property var holidays: []          // the day's holidays, [{title, public, world}], set by the host
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
    property color colorHoliday: "#C8A35A"
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
    // `uid`: the note to write ("new" for one not saved yet); an empty text deletes it.
    signal save(string dateKey, string text, int lead, string uid)

    // The day's notes of yours in the account notes go to, each {uid, time, body, bang,
    // lead, original}: uid "" is a note not saved yet, `original` its state when the
    // sheet opened. The editor and the two rows hold the one at `current`.
    property var notes: []
    property int current: 0
    function timedOf(n) { return validTime(n.time).length > 0 || /^\s*\d{1,2}[:.]\d{2}/.test(n.body) }
    function composeOf(n) {
        if (String(n.body).trim().length === 0) return ""
        const t = validTime(n.time)
        if (t.length > 0) return t + " " + String(n.body).replace(/^\s+/, "")
        if (!timedOf(n) && n.bang && !/^\s*!/.test(n.body)) return "!" + n.body
        return String(n.body)
    }
    function sigOf(n) { return composeOf(n) + "|" + (timedOf(n) ? n.lead : "") }
    function editing() { return { uid: "", time: noteTime, body: noteText, bang: chosenBang, lead: chosenLead } }
    // An entry as the editor takes it: the time and the "!" out of the text into their
    // rows; a range ("9.00-10.30 …") stays in the text.
    function noteOf(e) {
        const own = (e.text !== undefined && e.text !== null && String(e.text).length > 0)
            ? String(e.text) : e.summary + (e.description.length > 0 ? "\n" + e.description : "")
        let time = "", body = own, bang = false
        const m = own.match(/^(\d{1,2})[:.](\d{2})(?:[ \t]+|$)([\s\S]*)$/)
        if (m && validTime(m[1] + ":" + m[2]).length > 0) {
            time = validTime(m[1] + ":" + m[2])
            body = m[3]
        } else if (own.startsWith("!")) {
            bang = true
            body = own.slice(1)
        }
        const n = { uid: String(e.uid || ""), time: time, body: body, bang: bang,
                    lead: (e.time && e.lead !== undefined) ? Number(e.lead) : leadDefault }
        n.original = sigOf(n)
        return n
    }
    function blankNote() {
        const n = { uid: "", time: "", body: "", bang: false, lead: leadDefault }
        n.original = sigOf(n)
        return n
    }
    // The editor's state back into the list, and a note of the list into the editor.
    function keep() {
        if (current < 0 || current >= notes.length) return
        const list = notes.slice()
        const n = Object.assign({}, list[current])
        n.time = noteTime; n.body = noteText; n.bang = chosenBang; n.lead = chosenLead
        list[current] = n
        notes = list
    }
    function load(i) {
        current = i
        const n = notes[i]
        noteText = n.body
        noteTime = n.time
        chosenBang = n.bang
        chosenLead = n.lead
        if (editorItem) editorItem.text = n.body
        if (timeItem) timeItem.text = n.time
    }
    function focusEditor() {
        if (editorItem) {
            editorItem.forceActiveFocus()
            editorItem.cursorPosition = editorItem.length
        }
    }
    function select(i) {
        if (i === current) return
        keep()
        load(i)
        Qt.callLater(focusEditor)
    }
    function addNote() {
        keep()
        const list = notes.slice()
        list.push(blankNote())
        notes = list
        load(list.length - 1)
        Qt.callLater(focusEditor)
    }
    // A line of the list: the time or the "!" and the first line of the text.
    function noteLabel(i) {
        const n = i === current ? editing() : notes[i]
        if (!n) return ""
        const t = validTime(n.time)
        const first = String(n.body).split("\n")[0].trim()
        const text = (t.length > 0 ? t + " " : (n.bang && !timedOf(n) ? "!" : "")) + first
        return text.length > 0 ? text : i18nc("the sticker: a note with no text yet", "(empty)")
    }

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
    // What goes back for the note in the editor: the text as the script reads it.
    function composed() { return composeOf(editing()) }

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
        const mine = []
        for (let i = 0; i < list.length; i++)
            if (list[i].own && list[i].account === noteAccount)
                mine.push(noteOf(list[i]))
        if (mine.length === 0)
            mine.push(blankNote())
        // The notes first: rebuilt editor and time rows take the state as they are created.
        notes = mine
        load(0)
        original = noteText
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
        } else {
            keep()
            // A new note takes the day's own uid ("") while the day has no note saved —
            // the one-note case stays as it was; next to saved ones it asks for "new".
            let fresh = notes.every(x => x.uid.length === 0)
            for (const n of notes) {
                if (sigOf(n) === n.original) continue
                const text = composeOf(n)
                if (text.length === 0 && n.uid.length === 0) continue
                const uid = n.uid.length > 0 ? n.uid : (fresh ? "" : "new")
                if (n.uid.length === 0) fresh = false
                save(dateKey, text, timedOf(n) ? n.lead : -1, uid)
            }
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
        // The day's holidays under its name: a day off in the weekend's colour.
        for (const h of holidays)
            out.push({ text: framed("* " + h.title), role: h["public"] ? "accent" : "holiday" })
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
        // The notes of yours, once there is more than the one being written: a line each,
        // the one in the editor marked, and a line that starts another.
        if (notes.length > 1 || (notes.length === 1 && notes[0].uid.length > 0)) {
            out.push({ text: separator, role: "dim" })
            for (let i = 0; i < notes.length; i++)
                out.push({ note: true, line: i })
            out.push({ note: true, line: -1 })
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
        case "holiday": return sticker.colorHoliday
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
                    readonly property bool isNote: spec.note === true
                    readonly property bool isPlain: !isEditor && !isTime && !isRemind && !isNote
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
                    readonly property Item shownRow: isEditor ? editRow : isTime ? timeRow : isRemind ? remindRow
                                                   : isNote ? noteRow : lineText
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

                    // "│ > 19:00 test │" — a note of yours; a click puts it in the editor. The
                    // last line, "+ new note", starts another.
                    Row {
                        id: noteRow
                        visible: row.isNote
                        readonly property bool adder: row.isNote && row.spec.line < 0
                        readonly property bool marked: row.isNote && row.spec.line === sticker.current
                        Line { text: sticker.f[3] + " "; color: sticker.colorDim }
                        Line {
                            text: !row.isNote ? ""
                                : sticker.pad(noteRow.adder ? "+ " + i18nc("the sticker's line that starts another note", "new note")
                                                            : (noteRow.marked ? "> " : "  ") + sticker.noteLabel(row.spec.line))
                            color: noteRow.marked ? sticker.colorNote : noteRow.adder ? sticker.colorDim : sticker.colorFg
                            MouseArea {
                                anchors.fill: parent
                                enabled: row.isNote
                                cursorShape: Qt.PointingHandCursor
                                onClicked: noteRow.adder ? sticker.addNote() : sticker.select(row.spec.line)
                            }
                        }
                        Line { text: " " + sticker.f[3]; color: sticker.colorDim }
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
                        // The side on its own, as on every other row: a Text starts on a pixel,
                        // and glued to the filler the side landed a pixel off.
                        Line { text: " ".repeat(Math.max(0, sticker.width_ - sticker.labelWidth - 5)); color: sticker.colorDim }
                        Line { text: " " + sticker.f[3]; color: sticker.colorDim }
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
                            text: " ".repeat(Math.max(0, sticker.width_ - sticker.labelWidth - sticker.usedWidth(remindRow.items)))
                            color: sticker.colorDim
                        }
                        Line { text: " " + sticker.f[3]; color: sticker.colorDim }
                    }
                }
            }
        }
    }
}
