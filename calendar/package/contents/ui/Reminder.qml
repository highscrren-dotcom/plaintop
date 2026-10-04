import QtQuick
import org.kde.plasma.core as PlasmaCore

// A reminder: one alarm of the document, on a sheet framed with characters by the day's
// cell — the sticker's kind of window — with the ways out as rows marked with ">": snooze
// a while, snooze an hour, tomorrow at the hour "!" notes ring at, done; a task also
// offers to be completed. A Notification-type window: it does not take the focus from
// what you are typing, so it is driven by the pointer — hover marks a row, a click
// chooses. The host decides what to show and runs what is chosen.
PlasmaCore.Dialog {
    id: reminder

    type: PlasmaCore.Dialog.Notification
    location: PlasmaCore.Types.Floating
    backgroundHints: PlasmaCore.Dialog.NoBackground
    hideOnWindowDeactivate: false

    // Set by the host for each opening.
    property var alarm: ({})            // one item of the document's `alarms`
    property var accounts: []
    property bool missed: false         // it was due a while ago
    property int snoozeMinutes: 10
    property string hour: "09:00"

    property string fontFamily: "JetBrainsMono Nerd Font Mono"
    property int fontSize: 10
    property color colorFg: "#C8CCD4"
    property color colorAccent: "#E05561"
    property color colorDim: "#6B7280"
    property color colorNote: "#8FB6E0"
    property color colorPaper: "#141820"
    property int paperOpacity: 94
    property string frame: "┌─┐│└┘├┤"
    property int columns: 40
    property int animation: 2           // 0 none, 1 fade, 2 unfold

    property int current: 3             // the marked option: "done" by default
    // "snooze", "hour", "tomorrow", "done", "complete" — with the alarm it is about.
    signal choose(string what, var alarm)

    function open(a, anchor, isMissed) {
        alarm = a || ({})
        missed = isMissed === true
        current = 3
        visualParent = anchor
        revealed = animation === 2 ? 0 : 1000
        visible = true
    }

    onVisibleChanged: if (visible && animation === 2) unfold.restart()

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

    function accountName(id) {
        for (let i = 0; i < accounts.length; i++)
            if (accounts[i].id === id)
                return accounts[i].name || id
        return id
    }

    // The ways out, in order; a task gets one more.
    readonly property var options: {
        const out = [
            { what: "snooze", text: i18nc("reminder: snooze for N minutes", "in %1 min", snoozeMinutes) },
            { what: "hour", text: i18nc("reminder: snooze for an hour", "in an hour") },
            { what: "tomorrow", text: i18nc("reminder: tomorrow at an hour", "tomorrow at %1", hour) },
            { what: "done", text: i18nc("reminder: acknowledged, never again", "done") }
        ]
        if (alarm && alarm.kind === "todo" && alarm.account !== "local")
            out.push({ what: "complete", text: i18nc("reminder: complete the task on its server", "task done") })
        return out
    }

    // The rows: borders, the title — the day and the time, MISSED when it is late — the
    // entry, its account, a separator, the options.
    readonly property var rows: {
        const out = [{ text: top, role: "dim", pick: -1 }]
        const a = alarm || {}
        const at = String(a.at || "")
        const p = String(a.date || at.slice(0, 10)).split("-").map(Number)
        const day = p.length === 3 ? new Date(p[0], p[1] - 1, p[2]) : new Date()
        let title = day.toLocaleDateString(Qt.locale(), "dddd, d MMMM").toUpperCase()
        if (a.time && String(a.time).length > 0)
            title += " · " + a.time + (a.end ? "–" + a.end : "")
        if (missed)
            title = i18nc("reminder: it was due earlier", "MISSED") + " · " + title
        out.push({ text: framed(title), role: missed ? "accent" : "note", pick: -1 })
        const head = a.kind === "todo" ? "[ ] " : ""
        out.push({ text: framed(head + String(a.summary || "")), role: "fg", pick: -1 })
        if (a.description && String(a.description).length > 0)
            out.push({ text: framed("  " + String(a.description).split("\n")[0]), role: "dim", pick: -1 })
        if (a.account && a.account !== "local")
            out.push({ text: framed("· " + accountName(a.account)), role: "dim", pick: -1 })
        out.push({ text: separator, role: "dim", pick: -1 })
        for (let i = 0; i < options.length; i++)
            out.push({ text: framed((i === current ? "> " : "  ") + options[i].text),
                       role: i === current ? "note" : "fg", pick: i })
        out.push({ text: bottom, role: "dim", pick: -1 })
        return out
    }

    function pick(index) {
        if (index < 0 || index >= options.length) return
        const what = options[index].what
        const a = alarm
        visible = false
        choose(what, a)
    }

    // ── Animation ─────────────────────────────────────────────────────────────
    property int revealed: 1000

    function paint(role) {
        switch (role) {
        case "accent": return reminder.colorAccent
        case "dim": return reminder.colorDim
        case "note": return reminder.colorNote
        default: return reminder.colorFg
        }
    }

    component Line: Text {
        color: reminder.colorFg
        font.family: reminder.fontFamily
        font.pointSize: reminder.fontSize
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
    }

    mainItem: Item {
        id: sheet
        // A Dialog's default property is mainItem: anything declared at the dialog's root
        // would be assigned there too, so the timer lives in the sheet (docs/GOTCHAS.md).
        Timer {
            id: unfold
            interval: 22
            repeat: true
            running: false
            onTriggered: {
                reminder.revealed++
                if (reminder.revealed > reminder.rows.length)
                    stop()
            }
        }

        implicitWidth: column.width
        implicitHeight: column.height
        // The dialog sizes its window from width/height and may keep the first ones:
        // re-apply the implicit size on every change (docs/GOTCHAS.md).
        onImplicitWidthChanged: width = implicitWidth
        onImplicitHeightChanged: height = implicitHeight

        Rectangle {
            anchors.fill: column
            color: reminder.colorPaper
            opacity: reminder.paperOpacity / 100
        }

        Column {
            id: column
            spacing: 0
            opacity: reminder.visible || reminder.animation !== 1 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: reminder.animation === 1 ? 140 : 0 } }

            Repeater {
                model: reminder.rows.length

                Item {
                    id: row
                    required property int index
                    readonly property var spec: reminder.rows[index] || ({ text: "", role: "dim", pick: -1 })
                    width: lineText.width
                    height: lineText.height
                    opacity: index < reminder.revealed ? 1 : 0

                    // A framed row keeps its sides in the frame's colour; the text between
                    // them takes the row's (docs/GOTCHAS.md).
                    readonly property var chars: Array.from(String(spec.text))
                    readonly property bool sided: chars.length >= 4 && chars[0] === reminder.f[3]
                                                  && chars[chars.length - 1] === reminder.f[3]
                    Row {
                        id: lineText
                        Line {
                            text: row.sided ? row.chars.slice(0, 2).join("") : ""
                            color: reminder.colorDim
                        }
                        Line {
                            text: row.sided ? row.chars.slice(2, -2).join("") : row.chars.join("")
                            color: reminder.paint(row.spec.role)
                        }
                        Line {
                            text: row.sided ? row.chars.slice(-2).join("") : ""
                            color: reminder.colorDim
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: row.spec.pick >= 0
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: reminder.current = row.spec.pick
                        onClicked: reminder.pick(row.spec.pick)
                    }
                }
            }
        }
    }
}
