import QtQuick

// The calendar as text: a wall calendar's page — the month's grid of day numbers under a
// row of weekday names, the ISO week number in front of every row — drawn the way the
// monitor draws its lines: monospace, no frames. One month or three, the previous, the
// current and the next one under another, as the quarterly calendars on an office wall.
// Everything the grid says comes from the machine's locale: the names, the first day of
// the week, which days are the weekend. Nothing is fetched and nothing is polled: the
// grid is rebuilt when a setting changes and when the day turns.
Item {
    id: view

    // ── Inputs ────────────────────────────────────────────────────────────────
    property int months: 3            // 1: the current month; 3: the previous, current, next
    property int cellWidth: 4         // a day's column in characters, the number inside
    property bool weekNumbers: true
    // 0: the locale's first day of the week; otherwise a Qt day, 1 Monday … 7 Sunday.
    property int firstDay: 0
    property bool fillDays: false     // the neighbouring months' days in the empty cells
    property bool weekendAccent: true

    // Notes: the document notes.py prints — days: {date: [entries]}, upcoming: [entries],
    // accounts: [{id, name, error}] — and whether the grid takes clicks and marks days.
    property var notes: ({ days: {}, upcoming: [], accounts: [] })
    property bool notesOn: true
    property int upcoming: 3          // lines of upcoming entries under the months, 0 none
    property color colorNote: "#8FB6E0"
    // Holidays: dateKey → [{title, public, world}] (Holidays.qml). A day off takes the
    // weekend's colour, any other holiday its own.
    property var holidays: ({})
    property color colorHoliday: "#C8A35A"

    // A day was clicked: its date and its cell, in the view's coordinates.
    signal dayClicked(string dateKey, real x, real y, real w, real h)
    // A missed reminder's line under the months was clicked: the alarm, as notes.py lists it.
    signal missedClicked(var alarm)

    property string fontFamily: "JetBrainsMono Nerd Font Mono"
    property int fontSize: 10
    property color colorFg: "#C8CCD4"
    property color colorAccent: "#E05561"
    property color colorDim: "#6B7280"
    property color colorToday: "#8FB6E0"

    // ── Geometry, in characters and lines ─────────────────────────────────────
    // The host sizes the applet from the same numbers, so the hint stays constant for
    // the given settings: a month's block is eight lines — the title, the names, six
    // rows, six always, as the longest month needs — and a blank line stands between
    // blocks. Four is the least cell that holds "[31]".
    readonly property int cw: Math.max(4, cellWidth)
    readonly property int shown: months >= 3 ? 3 : 1
    readonly property int columns: (weekNumbers ? 4 : 0) + 7 * cw
    readonly property int linesPerMonth: 8
    readonly property int upcomingLines: (notesOn && upcoming > 0) ? upcoming + 1 : 0
    readonly property int lineCount: shown * linesPerMonth + (shown - 1) + upcomingLines

    // ── Today ─────────────────────────────────────────────────────────────────
    // The day as a string, so the grid is rebuilt when the day turns and not every
    // minute: a string compares by value, a Date is a new object each time.
    property string todayKey: dayKey(new Date())

    // ISO, zero-padded: the same key notes.py uses for its days.
    function dayKey(d) {
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0")
    }

    function hasNote(key) {
        const days = notes && notes.days ? notes.days : null
        return days !== null && days[key] !== undefined && days[key].length > 0
    }

    function accountName(id) {
        const list = notes && notes.accounts ? notes.accounts : []
        for (let i = 0; i < list.length; i++)
            if (list[i].id === id)
                return list[i].name || id
        return id
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            const k = view.dayKey(new Date())
            if (k !== view.todayKey)
                view.todayKey = k
        }
    }

    // ── The week ──────────────────────────────────────────────────────────────
    // The setting counts the days of the week from Monday as 1 to Sunday as 7;
    // JavaScript's Date, and QML's Locale (firstDayOfWeek, weekDays), count from
    // Sunday as 0 — dayName() takes both 0 and 7 for Sunday. The grid's first column
    // is a day from the setting or the locale.
    readonly property int startDay: (firstDay >= 1 && firstDay <= 7) ? firstDay : Qt.locale().firstDayOfWeek

    function jsDay(qtDay) {
        return qtDay % 7
    }

    // The weekend: the days the locale does not list among its working days, as
    // JavaScript days. Saturday and Sunday when the locale says nothing usable — an
    // empty list or all seven. Read by index, not through Array methods: the list comes
    // from C++ and need not be a JavaScript array.
    readonly property var weekend: {
        const work = Qt.locale().weekDays
        const working = ({})
        for (let i = 0; work && i < work.length; i++)
            working[Number(work[i])] = true
        const out = []
        for (let q = 1; q <= 7; q++)
            if (!working[q % 7])
                out.push(q % 7)
        return (out.length === 0 || out.length === 7) ? [6, 0] : out
    }

    function isWeekend(jsDayOfWeek) {
        return weekend.indexOf(jsDayOfWeek) >= 0
    }

    // ISO 8601: the week of the year that holds the given day's Thursday. Counted in
    // UTC, so a daylight-time change cannot make a day 23 hours long and shift the count.
    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
        const day = t.getUTCDay() || 7
        t.setUTCDate(t.getUTCDate() + 4 - day)
        const jan1 = Date.UTC(t.getUTCFullYear(), 0, 1)
        return Math.ceil(((t.getTime() - jan1) / 86400000 + 1) / 7)
    }

    // ── Lines ─────────────────────────────────────────────────────────────────
    // Each line is a list of parts with a role — "fg", "dim", "accent", "today" — as in
    // the monitor and the weather. Parts of one role run together, so a row is a few
    // Text items rather than one per cell.
    function push(parts, text, role) {
        if (text.length === 0)
            return
        const last = parts.length > 0 ? parts[parts.length - 1] : null
        if (last !== null && last.role === role)
            last.text += text
        else
            parts.push({ text: text, role: role })
    }

    // Cuts a line of parts to the column width, ending it with an ellipsis. Code points,
    // not UTF-16 units, so a non-Latin month name is not cut in half.
    function fit(parts) {
        let left = columns
        const out = []
        for (const p of parts) {
            if (left <= 0)
                break
            const chars = Array.from(p.text)
            if (chars.length <= left) {
                out.push(p)
                left -= chars.length
            } else {
                out.push({ text: chars.slice(0, Math.max(0, left - 1)).join("") + "…", role: p.role })
                left = 0
            }
        }
        return out
    }

    // One month's block: the title, the names, six rows — and, into `cells`, the day key
    // under every cell of the six rows ("" where there is none), for the clicks. `month`
    // counts from 0, as Date does; `today` is a day key.
    function monthBlock(year, month, today, cells) {
        const loc = Qt.locale()
        const out = []

        // ⚠️ standaloneMonthName, not monthName: in Russian and the other Slavic
        // languages monthName is the genitive — "октября", the form that follows a day
        // number — while a title wants the nominative, "октябрь". Uppercase, as every
        // header in these widgets. QML's Locale counts the months from 0, as Date does:
        // 9 is October.
        const title = String(loc.standaloneMonthName(month, Locale.LongFormat)).toUpperCase()
        out.push(fit([{ text: title, role: "fg" }, { text: " " + year, role: "dim" }]))

        // The names, one per column, ending where the numbers under them end; a weekend's
        // name in the weekend's colour, as its numbers. Lowercase: the locale's short
        // names are "Mon" in English and "пн" in Russian, and one case reads as one text.
        const head = []
        push(head, weekNumbers ? "    " : "", "dim")
        for (let i = 0; i < 7; i++) {
            const q = ((startDay - 1 + i) % 7) + 1
            const name = Array.from(String(loc.dayName(q, Locale.ShortFormat)).toLowerCase())
            const cell = name.slice(0, cw - 1).join("").padStart(cw - 1) + " "
            push(head, cell, (weekendAccent && isWeekend(jsDay(q))) ? "accent" : "dim")
        }
        out.push(head)

        // The rows. `rowFirst` is the month-day of a row's first cell — 0 or less in the
        // first row before the 1st, past the length in the last ones — and Date takes
        // such numbers as the neighbouring months' days by itself.
        const daysIn = new Date(year, month + 1, 0).getDate()
        const offset = (new Date(year, month, 1).getDay() - jsDay(startDay) + 7) % 7
        for (let r = 0; r < 6; r++) {
            const parts = []
            const keys = ["", "", "", "", "", "", ""]
            cells.push(keys)
            const rowFirst = r * 7 - offset + 1
            const inside = rowFirst <= daysIn && rowFirst + 6 >= 1
            // A row with nothing of this month in it stays blank — the board keeps its
            // six rows, so the next block does not move — unless the neighbours fill it.
            if (!inside && !fillDays) {
                out.push(parts)
                continue
            }
            if (weekNumbers) {
                // The row's own Thursday names the week, so a row that starts on Sunday
                // or Saturday is numbered by the week most of it lies in.
                const base = new Date(year, month, rowFirst)
                const thursday = new Date(year, month, rowFirst + ((4 - base.getDay() + 7) % 7))
                push(parts, String(isoWeek(thursday)).padStart(2) + "  ", "dim")
            }
            for (let i = 0; i < 7; i++) {
                const d = new Date(year, month, rowFirst + i)
                const own = d.getMonth() === month
                if (!own && !fillDays) {
                    push(parts, " ".repeat(cw), "dim")
                    continue
                }
                const body = String(d.getDate()).padStart(cw - 2)
                const key = dayKey(d)
                keys[i] = key
                // A day with an entry takes the note colour; a holiday that is a day off
                // the weekend's, any other holiday its own; then the weekend.
                const hol = own ? (holidays[key] || []) : []
                const role = !own ? "dim"
                    : ((notesOn && hasNote(key)) ? "note"
                       : hol.some(h => h["public"]) ? "accent"
                       : hol.length > 0 ? "holiday"
                       : ((weekendAccent && isWeekend(d.getDay())) ? "accent" : "fg"))
                // Today is in brackets — the ring on the wall calendar — in their own
                // colour; the number keeps the colour of its day.
                if (own && key === today) {
                    push(parts, "[", "today")
                    push(parts, body, role)
                    push(parts, "]", "today")
                } else {
                    push(parts, " " + body + " ", role)
                }
            }
            out.push(parts)
        }
        return out
    }

    // An upcoming entry as a line: the day, the time or the task's box, the summary, and
    // the account it came from.
    function upcomingLine(e) {
        const p = String(e.date).split("-").map(Number)
        const d = new Date(p[0], p[1] - 1, p[2])
        const when = d.toLocaleDateString(Qt.locale(), "ddd d MMM").toLowerCase()
        let head = ""
        if (e.kind === "todo")
            head = e.done ? "[x] " : "[ ] "
        else if (e.time && e.time.length > 0)
            head = e.time + " "
        // A reminder that rang unanswered: "!" and the accent until "done"; a click opens it.
        if (e.missed === true)
            head = "! " + head
        const parts = [{ text: when + "  ", role: "dim" },
                       { text: head + e.summary, role: e.missed === true ? "accent" : e.own ? "note" : "fg" }]
        if (e.account !== "local")
            parts.push({ text: "  · " + accountName(e.account), role: "dim" })
        return fit(parts)
    }

    // The months' lines and the day key under every cell, built together.
    readonly property var grid: {
        const out = []
        const cells = []
        // The months are taken from the day key, not from a fresh Date: the key is what
        // the rebuild follows, and the two must name the same day.
        const p = todayKey.split("-").map(Number)
        const now = new Date(p[0], p[1] - 1, p[2])
        const span = shown === 3 ? [-1, 0, 1] : [0]
        for (let k = 0; k < span.length; k++) {
            if (k > 0)
                out.push([])
            const m = new Date(now.getFullYear(), now.getMonth() + span[k], 1)
            const block = []
            for (const l of monthBlock(m.getFullYear(), m.getMonth(), todayKey, block))
                out.push(l)
            cells.push(block)
        }
        if (upcomingLines > 0) {
            out.push([])
            const list = (notes && notes.upcoming) ? notes.upcoming : []
            for (let i = 0; i < upcoming; i++)
                out.push(i < list.length ? upcomingLine(list[i]) : [])
        }
        return { lines: out, cells: cells }
    }
    readonly property var lines: grid.lines
    readonly property var cellMap: grid.cells

    function paint(role) {
        switch (role) {
        case "accent": return view.colorAccent
        case "dim": return view.colorDim
        case "today": return view.colorToday
        case "note": return view.colorNote
        case "holiday": return view.colorHoliday
        default: return view.colorFg
        }
    }

    // The months the grid shows, as [year, month 1–12] — what the holidays are read for.
    readonly property var shownMonths: {
        const p = todayKey.split("-").map(Number)
        const span = shown === 3 ? [-1, 0, 1] : [0]
        return span.map(k => {
            const m = new Date(p[0], p[1] - 1 + k, 1)
            return [m.getFullYear(), m.getMonth() + 1]
        })
    }

    // ── The mouse ─────────────────────────────────────────────────────────────
    // The day under a point: the row says which month block and which of its six rows,
    // the column which cell; the key comes from the map built with the lines.
    TextMetrics {
        id: cell
        font.family: view.fontFamily
        font.pointSize: view.fontSize
        text: "0"
    }
    readonly property real charWidth: cell.advanceWidth
    readonly property real leftColumn: (weekNumbers ? 4 : 0) * charWidth

    // The cell under a point: its month block, row, column and day key, or null.
    function cellAt(x, y) {
        const row = Math.floor(y / lineHeight)
        const block = Math.floor(row / (linesPerMonth + 1))
        const inBlock = row - block * (linesPerMonth + 1)
        if (block < 0 || block >= shown || inBlock < 2 || inBlock > 7)
            return null
        const col = Math.floor((x - leftColumn) / (cw * charWidth))
        if (col < 0 || col > 6)
            return null
        const rows = cellMap[block]
        const key = rows && rows[inBlock - 2] ? (rows[inBlock - 2][col] || "") : ""
        return key.length > 0 ? { block: block, key: key } : null
    }

    function dayAt(x, y) {
        const c = cellAt(x, y)
        return c ? c.key : ""
    }

    // The cell of a key: for the frame, and for the sticker to open from. With the
    // neighbouring months shown a day stands in two blocks — the 1st of October also in
    // September's last row — so the block the pointer is in comes first; without one,
    // the first block that has the day.
    function cellRect(key, block) {
        if (key.length === 0)
            return Qt.rect(0, 0, 0, 0)
        const at = (b, r, c) => Qt.rect(leftColumn + c * cw * charWidth,
                                         (b * (linesPerMonth + 1) + 2 + r) * lineHeight,
                                         cw * charWidth, lineHeight)
        // No block given (a reminder, say): the block of the day's own month first — the
        // middle of a block's third row always belongs to it.
        if (block === undefined || block < 0 || block >= cellMap.length) {
            block = -1
            for (let b = 0; b < cellMap.length; b++) {
                const mid = cellMap[b][2] ? String(cellMap[b][2][3] || "") : ""
                if (mid.slice(0, 7) === key.slice(0, 7)) { block = b; break }
            }
        }
        const order = []
        if (block >= 0)
            order.push(block)
        for (let b = 0; b < cellMap.length; b++)
            if (b !== block)
                order.push(b)
        for (const b of order)
            for (let r = 0; r < cellMap[b].length; r++)
                for (let c = 0; c < 7; c++)
                    if (cellMap[b][r][c] === key)
                        return at(b, r, c)
        return Qt.rect(0, 0, 0, 0)
    }

    // The rows of day numbers of every month, as one rectangle: what takes the mouse
    // while the rest of the widget lets clicks through (the host's mask).
    readonly property rect gridRect: Qt.rect(0, 2 * lineHeight, width, (shown * (linesPerMonth + 1) - 3) * lineHeight)

    // The upcoming line under a point, or null; the first sits after the blank line that
    // follows the months.
    readonly property var upcomingList: (notes && notes.upcoming) ? notes.upcoming : []
    function upcomingAt(y) {
        if (upcomingLines === 0) return null
        const i = Math.floor(y / lineHeight) - (shown * linesPerMonth + shown)
        return (i >= 0 && i < upcoming && i < upcomingList.length) ? upcomingList[i] : null
    }
    readonly property bool anyMissed: upcomingList.some(u => u.missed === true)
    // What takes the mouse while clicks pass through: the day rows, and the upcoming lines
    // too while a missed reminder waits there.
    readonly property rect clickRect: anyMissed ? Qt.rect(0, 2 * lineHeight, width, (lineCount - 2) * lineHeight) : gridRect
    property bool hoverMissed: false

    // The day under the pointer, and the day whose sticker is open (set by the host):
    // either is framed, so the eye knows which cell a click lands on.
    property string hoverKey: ""
    property string activeKey: ""
    // The blocks they were taken in: a day of a neighbouring month stands in two.
    property int hoverBlock: -1
    property int activeBlock: -1
    readonly property string framedKey: hoverKey.length > 0 ? hoverKey : activeKey

    MouseArea {
        anchors.fill: parent
        enabled: view.notesOn
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: (view.hoverKey.length > 0 || view.hoverMissed) ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPositionChanged: mouse => {
            const c = view.cellAt(mouse.x, mouse.y)
            view.hoverBlock = c ? c.block : -1
            view.hoverKey = c ? c.key : ""
            const u = c ? null : view.upcomingAt(mouse.y)
            view.hoverMissed = u !== null && u.missed === true
        }
        onExited: { view.hoverKey = ""; view.hoverMissed = false }
        onClicked: mouse => {
            const c = view.cellAt(mouse.x, mouse.y)
            if (!c) {
                const u = view.upcomingAt(mouse.y)
                if (u && u.missed === true)
                    view.missedClicked(u)
                return
            }
            view.activeBlock = c.block
            const r = view.cellRect(c.key, c.block)
            view.dayClicked(c.key, r.x, r.y, r.width, r.height)
        }
    }

    // The frame: one pixel, no fill, the note colour — the cell's rectangle a pixel in
    // from its edges, so two framed neighbours would not touch.
    Rectangle {
        readonly property rect r: view.cellRect(view.framedKey, view.hoverKey.length > 0 ? view.hoverBlock : view.activeBlock)
        visible: view.notesOn && view.framedKey.length > 0 && r.width > 0
        x: r.x + 1
        y: r.y + 1
        width: Math.max(0, r.width - 2)
        height: Math.max(0, r.height - 2)
        color: "transparent"
        border.width: 1
        border.color: view.colorNote
        opacity: view.hoverKey.length > 0 ? 1 : 0.6
        Behavior on opacity { NumberAnimation { duration: 80 } }
    }

    // A widget line: monospace text, colour and size set in place. PlainText: a Text
    // with the default format accepts the left button (docs/GOTCHAS.md); none here may.
    component Line: Text {
        color: view.colorFg
        font.family: view.fontFamily
        font.pointSize: view.fontSize
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
    }

    // ── Layout ────────────────────────────────────────────────────────────────
    // One line of the widget's font. A hidden Text, not FontMetrics: NativeRendering
    // rounds the line to whole pixels (docs/GOTCHAS.md). The rows are placed by index,
    // so a blank line takes its place whether or not it has anything to draw.
    // ⚠️ Every Text here is PlainText: with the default format a Text takes the left
    // button, and under the host's partial mask that would arm the desktop's edit mode.
    Text {
        id: lineProbe
        visible: false
        text: "0"
        font.family: view.fontFamily
        font.pointSize: view.fontSize
        renderType: Text.NativeRendering
    }
    readonly property real lineHeight: lineProbe.implicitHeight

    // The model is a count, not the array: with a count the delegates stay when the
    // lines are rebuilt, and a Text whose string did not change does nothing
    // (docs/GOTCHAS.md, the Repeater note).
    Repeater {
        model: view.lines.length

        Row {
            id: lineRow
            required property int index
            readonly property var parts: view.lines[index] || []
            spacing: 0
            x: 0
            y: index * view.lineHeight

            Repeater {
                model: lineRow.parts.length

                Line {
                    required property int index
                    readonly property var part: lineRow.parts[index] || ({ text: "", role: "fg" })
                    text: part.text
                    color: view.paint(part.role)
                }
            }
        }
    }
}
