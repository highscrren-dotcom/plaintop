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
    readonly property int lineCount: shown * linesPerMonth + (shown - 1)

    // ── Today ─────────────────────────────────────────────────────────────────
    // The day as a string, so the grid is rebuilt when the day turns and not every
    // minute: a string compares by value, a Date is a new object each time.
    property string todayKey: dayKey(new Date())

    function dayKey(d) {
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
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

    // One month's block: the title, the names, six rows. `month` counts from 0, as Date
    // does; `today` is a day key, or "" for a month with no today in it.
    function monthBlock(year, month, today) {
        const loc = Qt.locale()
        const out = []

        // ⚠️ standaloneMonthName, not monthName: in Russian and the other Slavic
        // languages monthName is the genitive — "октября", the form that follows a day
        // number — while a title wants the nominative, "октябрь". Uppercase, as every
        // header in these widgets.
        const title = String(loc.standaloneMonthName(month + 1, Locale.LongFormat)).toUpperCase()
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
                const role = !own ? "dim" : ((weekendAccent && isWeekend(d.getDay())) ? "accent" : "fg")
                // Today is in brackets — the ring on the wall calendar — in their own
                // colour; the number keeps the colour of its day.
                if (own && dayKey(d) === today) {
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

    readonly property var lines: {
        const out = []
        // The months are taken from the day key, not from a fresh Date: the key is what
        // the rebuild follows, and the two must name the same day.
        const p = todayKey.split("-").map(Number)
        const now = new Date(p[0], p[1] - 1, p[2])
        const span = shown === 3 ? [-1, 0, 1] : [0]
        for (let k = 0; k < span.length; k++) {
            if (k > 0)
                out.push([])
            const m = new Date(now.getFullYear(), now.getMonth() + span[k], 1)
            for (const l of monthBlock(m.getFullYear(), m.getMonth(), todayKey))
                out.push(l)
        }
        return out
    }

    function paint(role) {
        switch (role) {
        case "accent": return view.colorAccent
        case "dim": return view.colorDim
        case "today": return view.colorToday
        default: return view.colorFg
        }
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
