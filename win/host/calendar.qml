import QtQuick
import plaintop

// The calendar's window host. The grid, the sticker and the reminder sheet are the
// plasmoid's files copied in by win/build.py; the holidays come from a Holidays.qml of
// this host's own (the `holidays` package through the service); this file is the
// shell-facing part — size, settings, the notes script through the service's /notes, the
// alarm clock — with the same shape as the plasmoid's main.qml.
import "calendar"

WidgetWindow {
    id: root
    widget: "calendar"

    readonly property string face: fixedFace("fontFamily")
    TextMetrics {
        id: cell
        font.family: root.face
        font.pointSize: root.num("fontSize", 10)
        text: "0"
    }
    Text {
        id: lineProbe
        visible: false
        text: "0"
        font.family: root.face
        font.pointSize: root.num("fontSize", 10)
        renderType: Text.NativeRendering
    }

    readonly property int shown: num("months", 3) >= 3 ? 3 : 1
    readonly property var doc: notesDoc
    readonly property var holidayDaysMap: holidayDays.days
    readonly property bool stickerOpen: sticker.visible
    function clickDay(key) { const r = view.cellRect(key, -1); if (r.width > 0) view.dayClicked(key, r.x, r.y, r.width, r.height); return r }
    readonly property int columns: (flag("weekNumbers", true) ? 4 : 0) + 7 * Math.max(4, num("cellWidth", 4))
    readonly property int lineCount: shown * 8 + (shown - 1)
        + ((flag("notes", true) && num("upcoming", 3) > 0) ? num("upcoming", 3) + 1 : 0)
    width: Math.ceil(cell.advanceWidth * columns)
    height: Math.ceil(lineProbe.implicitHeight * lineCount)

    // ── Notes ─────────────────────────────────────────────────────────────────
    // The document from notes.py, run by the service: every minute, and once more after
    // every note saved, alarm acknowledged or snoozed; writes go one at a time.
    property var notesDoc: ({ days: {}, upcoming: [], accounts: [], alarms: [] })

    readonly property string remindHour: /^\d{1,2}[:.]\d{2}$/.test(str("remindHour", "09:00").trim())
        ? str("remindHour", "09:00").trim().replace(".", ":") : "09:00"
    readonly property var alarmOptions: {
        const out = ["--upcoming", String(Math.max(1, num("upcoming", 3))),
                     "--lead", String(flag("reminders", true) ? Math.max(-1, num("remindLead", 10)) : -1),
                     "--hour", remindHour,
                     "--missed", String(Math.max(0, num("remindMissed", 12)))]
        if (!flag("remindEvents", true)) out.push("--no-events")
        if (!flag("reminders", true)) out.push("--no-alarms")
        return out
    }

    function takeDocument(stdout) {
        try {
            const doc = JSON.parse(String(stdout))
            if (doc && doc.days) {
                if (!doc.alarms) doc.alarms = []
                root.notesDoc = doc
            }
        } catch (e) {
            console.warn("plaincalendar: notes.py did not answer with a document:", e)
        }
    }

    function notes(args, cb) {
        Service.postJson("/notes", { args: args }, function(d) {
            if (d && d.stdout !== undefined) root.takeDocument(d.stdout)
            if (cb) cb(d)
        }, 60000)
    }

    Timer {
        interval: 60000
        running: root.ready && root.flag("notes", true)
        repeat: true
        triggeredOnStart: true
        onTriggered: root.notes(["sync", "--every", String(Math.max(1, root.num("syncMinutes", 15)))].concat(root.alarmOptions))
    }

    property var writes: []
    property bool writing: false
    function write(args) {
        writes.push(args)
        if (!writing) nextWrite()
    }
    function nextWrite() {
        if (writes.length === 0) { writing = false; return }
        writing = true
        notes(writes.shift(), function() { root.nextWrite() })
    }

    function saveNote(dateKey, text, lead, uid) {
        const account = str("noteAccount", "local").length > 0 ? str("noteAccount", "local") : "local"
        const own = (lead !== undefined && lead !== null) ? ["--lead", String(Math.max(-1, Number(lead)))] : []
        const which = uid ? ["--uid", String(uid)] : []
        const args = text.trim().length > 0
            ? ["set", account, dateKey, Qt.btoa(text)].concat(which, root.alarmOptions, own)
            : ["delete", account, dateKey].concat(which, root.alarmOptions)
        root.write(args)
    }

    // ── Reminders ─────────────────────────────────────────────────────────────
    property var taken: ({})

    function dueAlarms() {
        const now = Date.now()
        const list = (root.notesDoc && root.notesDoc.alarms) ? root.notesDoc.alarms : []
        const out = []
        for (let i = 0; i < list.length; i++) {
            const a = list[i]
            const ring = a.key + "|" + a.at
            if (root.taken[ring] === true) continue
            const p = String(a.at).match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/)
            if (!p) continue
            const when = new Date(Number(p[1]), Number(p[2]) - 1, Number(p[3]), Number(p[4]), Number(p[5])).getTime()
            if (when <= now) out.push({ alarm: a, when: when, ring: ring })
        }
        out.sort((x, y) => x.when - y.when)
        return out
    }

    function checkAlarms() {
        if (!root.flag("notes", true) || !root.flag("reminders", true)) return
        if (reminder.visible) return
        const due = root.dueAlarms()
        if (due.length === 0) return
        const first = due[0]
        root.taken[first.ring] = true
        notes(["claim", String(first.ring)], function(d) {
            let claimed = false
            try { claimed = JSON.parse(String(d.stdout)).claimed === true } catch (e) { claimed = false }
            if (claimed) rep.showReminder(first.alarm, Date.now() - first.when > 10 * 60000)
            else Qt.callLater(root.checkAlarms)
        })
    }

    Timer {
        interval: 30000
        running: root.ready && root.flag("notes", true) && root.flag("reminders", true)
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkAlarms()
    }
    onNotesDocChanged: Qt.callLater(root.checkAlarms)

    function settle(what, a) {
        let args
        switch (what) {
        case "snooze": args = ["snooze", String(a.key), String(Math.max(1, num("snoozeMinutes", 10)))]; break
        case "hour": args = ["snooze", String(a.key), "60"]; break
        case "tomorrow": {
            const d = new Date()
            d.setDate(d.getDate() + 1)
            const stamp = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-"
                        + String(d.getDate()).padStart(2, "0") + "T" + root.remindHour.padStart(5, "0")
            args = ["snooze", String(a.key), stamp]
            break
        }
        case "complete": args = ["done", String(a.account), String(a.uid), String(a.key)]; break
        default: args = ["ack", String(a.key)]
        }
        delete root.taken[a.key]
        root.write(args.concat(root.alarmOptions))
    }

    // The optional system notification and the sound, through the service (a toast and
    // winsound — what notify-send and pw-play do on Plasma).
    readonly property var builtinSounds: ["bell", "blip", "chime", "pager", "tick"]
    function announce(a) {
        const req = {}
        if (flag("remindSystem", false)) {
            req.title = (a.time ? a.time + "  " : "") + String(a.summary || "")
            req.text = String(a.description || "").split("\n")[0]
        }
        const name = str("remindSound", "").trim()
        if (name.length > 0)
            req.sound = builtinSounds.indexOf(name) >= 0 ? "builtin:" + name : name
        if (req.title !== undefined || req.sound !== undefined)
            Service.postJson("/notify", req)
    }

    // ── The face ──────────────────────────────────────────────────────────────
    Item {
        id: rep
        anchors.fill: parent

        function showReminder(a, missed) {
            const r = view.cellRect(String(a.date || ""), -1)
            if (r.width > 0) {
                remindAnchor.x = r.x; remindAnchor.y = r.y; remindAnchor.width = r.width; remindAnchor.height = r.height
            } else {
                remindAnchor.x = 0; remindAnchor.y = 0; remindAnchor.width = view.width; remindAnchor.height = view.lineHeight
            }
            reminder.open(a, remindAnchor, missed)
            root.announce(a)
        }

        CalendarView {
            id: view
            anchors.fill: parent

            months: root.num("months", 3)
            cellWidth: root.num("cellWidth", 4)
            weekNumbers: root.flag("weekNumbers", true)
            firstDay: root.num("firstDay", 0)
            fillDays: root.flag("fillDays", false)
            weekendAccent: root.flag("weekendAccent", true)

            notes: root.notesDoc
            notesOn: root.flag("notes", true)
            upcoming: root.num("upcoming", 3)
            activeKey: sticker.visible ? sticker.dateKey : ""

            fontFamily: root.face
            fontSize: root.num("fontSize", 10)
            colorFg: root.str("colorFg", "#C8CCD4")
            colorAccent: root.str("colorAccent", "#E05561")
            colorDim: root.str("colorDim", "#6B7280")
            colorToday: root.str("colorToday", "#8FB6E0")
            colorNote: root.str("colorNote", "#8FB6E0")
            colorHoliday: root.str("colorHoliday", "#C8A35A")
            holidays: holidayDays.days

            onMissedClicked: a => {
                if (reminder.visible) return
                const p = String(a.at).match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/)
                const when = p ? new Date(Number(p[1]), Number(p[2]) - 1, Number(p[3]), Number(p[4]), Number(p[5])).getTime() : Date.now()
                rep.showReminder(a, Date.now() - when > 10 * 60000)
            }
            onDayClicked: (key, x, y, w, h) => {
                anchor.x = x; anchor.y = y; anchor.width = w; anchor.height = h
                const days = root.notesDoc && root.notesDoc.days ? root.notesDoc.days : {}
                sticker.holidays = holidayDays.days[key] || []
                sticker.open(key, days[key] || [], anchor)
            }
        }

        Holidays {
            id: holidayDays
            active: root.flag("holidays", true)
            months: view.shownMonths
            kind: root.num("holidayKind", 0)
            world: root.flag("worldDays", false)
            regions: root.str("holidayRegions", "")
        }

        Item { id: anchor; visible: false }
        Item { id: remindAnchor; visible: false }

        Sticker {
            id: sticker
            accounts: root.notesDoc && root.notesDoc.accounts ? root.notesDoc.accounts : []
            noteAccount: root.str("noteAccount", "local").length > 0 ? root.str("noteAccount", "local") : "local"
            reminders: root.flag("reminders", true)
            remindHour: root.remindHour
            remindLead: root.num("remindLead", 10)

            fontFamily: root.face
            fontSize: root.num("fontSize", 10)
            colorFg: root.str("colorFg", "#C8CCD4")
            colorAccent: root.str("colorAccent", "#E05561")
            colorDim: root.str("colorDim", "#6B7280")
            colorNote: root.str("colorNote", "#8FB6E0")
            colorHoliday: root.str("colorHoliday", "#C8A35A")
            colorPaper: root.str("colorPaper", "#141820")
            paperOpacity: root.num("paperOpacity", 94)
            frame: root.str("frame", "┌─┐│└┘├┤")
            columns: root.num("stickerColumns", 40)
            animation: root.num("stickerAnimation", 2)

            onSave: (key, text, lead, uid) => root.saveNote(key, text, lead, uid)
        }

        Reminder {
            id: reminder
            accounts: root.notesDoc && root.notesDoc.accounts ? root.notesDoc.accounts : []
            snoozeMinutes: root.num("snoozeMinutes", 10)
            hour: root.remindHour

            fontFamily: root.face
            fontSize: root.num("fontSize", 10)
            colorFg: root.str("colorFg", "#C8CCD4")
            colorAccent: root.str("colorAccent", "#E05561")
            colorDim: root.str("colorDim", "#6B7280")
            colorNote: root.str("colorNote", "#8FB6E0")
            colorPaper: root.str("colorPaper", "#141820")
            paperOpacity: root.num("paperOpacity", 94)
            frame: root.str("frame", "┌─┐│└┘├┤")
            columns: root.num("stickerColumns", 40)
            animation: root.num("stickerAnimation", 2)

            onChoose: (what, a) => root.settle(what, a)
        }
    }
}
