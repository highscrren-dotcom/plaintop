import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

// Plasmoid host for the calendar. The grid and the drawing live in CalendarView.qml next
// to this file, the sticker in Sticker.qml, the reminder sheet in Reminder.qml; this one
// is the shell-facing part — size, settings, click-through, the notes script, the alarm
// clock — and has the same shape as the weather's and the player's hosts.
PlasmoidItem {
    id: root

    // The widget lives on the wallpaper: no plate, no frame. The user can put one back
    // through the standard dialog.
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    preferredRepresentation: fullRepresentation

    readonly property var cfg: Plasmoid.configuration

    // The configured family when it is installed, else the system's monospace face: a
    // missing font would otherwise go to fontconfig's heuristics, which need not pick a
    // monospace one. (The QML font type has no `families` list to say this directly.)
    readonly property string face: Qt.fontFamilies().includes(cfg.fontFamily) ? cfg.fontFamily : "monospace"

    // One character and one line of the widget's font. The applet is as wide as the
    // grid — seven cells and the week-number column — and as tall as the months shown,
    // eight lines each and a blank line between, plus the upcoming lines: the same
    // arithmetic as in the view, repeated here because the root cannot reach an id
    // inside fullRepresentation.
    TextMetrics {
        id: cell
        font.family: root.face
        font.pointSize: root.cfg.fontSize
        text: "0"
    }
    // ⚠️ A real Text, not FontMetrics: with NativeRendering a line comes out at the
    // hinted height (18 px here at 10 pt), while FontMetrics.height says 17.14 — five
    // lines short by four pixels. Measured in the offscreen host, 2026-09-23.
    Text {
        id: lineProbe
        visible: false
        text: "0"
        font.family: root.face
        font.pointSize: root.cfg.fontSize
        renderType: Text.NativeRendering
    }

    // ⚠️ The containment takes the applet size from Layout.* ON THE ROOT, and the hint
    // must be constant for the given settings: a hint that followed the rows a month
    // needs would make the containment relayout at every month and drop the widget into
    // the 0,0 corner. See docs/GOTCHAS.md. Hence six rows a month, whatever the month,
    // and as many upcoming lines as the setting says, whether or not there are entries.
    readonly property int shown: cfg.months >= 3 ? 3 : 1
    readonly property int columns: (cfg.weekNumbers ? 4 : 0) + 7 * Math.max(4, cfg.cellWidth)
    readonly property int lineCount: shown * 8 + (shown - 1) + ((cfg.notes && cfg.upcoming > 0) ? cfg.upcoming + 1 : 0)
    readonly property real boardWidth: Math.ceil(cell.advanceWidth * columns)
    readonly property real boardHeight: Math.ceil(lineProbe.implicitHeight * lineCount)

    Layout.minimumWidth: boardWidth
    Layout.minimumHeight: boardHeight
    Layout.preferredWidth: boardWidth
    Layout.preferredHeight: boardHeight

    // ── Notes ─────────────────────────────────────────────────────────────────
    // The document from contents/code/notes.py: fetched on a timer through the
    // executable engine (the script decides which accounts are due), and once more
    // after every note saved, alarm acknowledged or snoozed. Only the last answer is kept,
    // in memory: the script's own caches carry the state across a shell restart.
    readonly property string notesScript: Qt.resolvedUrl("../code/notes.py").toString().replace("file://", "")
    property var notesDoc: ({ days: {}, upcoming: [], accounts: [], alarms: [] })

    // The alarm options every document-printing command takes, from the settings: the
    // schedule follows them whichever command refreshed the document. The hour is checked
    // here so a half-typed setting cannot break the command line.
    readonly property string remindHour: /^\d{1,2}[:.]\d{2}$/.test(String(cfg.remindHour).trim())
        ? String(cfg.remindHour).trim().replace(".", ":") : "09:00"
    readonly property string alarmOptions: " --upcoming " + Math.max(1, cfg.upcoming)
        + " --lead " + (cfg.reminders ? Math.max(-1, cfg.remindLead) : -1)
        + " --hour " + remindHour
        + " --missed " + Math.max(0, cfg.remindMissed)
        + (cfg.remindEvents ? "" : " --no-events")
        + (cfg.reminders ? "" : " --no-alarms")

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

    P5Support.DataSource {
        id: notesSource
        engine: "executable"
        interval: Math.max(1, root.cfg.syncMinutes) * 60000
        connectedSources: root.cfg.notes
            ? ["python3 '" + root.notesScript + "' sync --every " + Math.max(1, root.cfg.syncMinutes) + root.alarmOptions]
            : []
        onNewData: function(source, data) { root.takeDocument(data.stdout) }
    }

    // One-shot commands — a save, a delete, an acknowledgement, a snooze — each its own
    // source, dropped once answered; every one prints the document back. UTF-8 goes
    // through base64, so no quoting of the text ever reaches a shell.
    P5Support.DataSource {
        id: notesWriter
        engine: "executable"
        interval: 0
        onNewData: function(source, data) {
            disconnectSource(source)
            root.takeDocument(data.stdout)
        }
    }

    function command(args) {
        // A nonce: the engine keys sources by their text, and the same command twice in
        // a row would otherwise not run again.
        return "python3 '" + root.notesScript + "' " + args + " # " + Date.now()
    }

    function saveNote(dateKey, text) {
        const account = root.cfg.noteAccount.length > 0 ? root.cfg.noteAccount : "local"
        const cmd = text.trim().length > 0
            ? "set '" + account + "' '" + dateKey + "' '" + Qt.btoa(text) + "'" + root.alarmOptions
            : "delete '" + account + "' '" + dateKey + "'" + root.alarmOptions
        notesWriter.connectSource(command(cmd))
    }

    // ── Reminders ─────────────────────────────────────────────────────────────
    // The document lists every alarm of the next 36 hours (and the missed ones of the
    // last few, as the settings say). The clock looks every half minute for the first
    // one that is due, asks the script to claim it — with two instances of the widget,
    // on two screens, the one that asks first shows it — and opens the sheet. The sheet
    // reports the choice; the script records it and prints the document anew, which
    // brings the next due alarm, if any, through the same door.
    // Rings claimed or lost, this run of the shell. A ring is an alarm at a time — the key
    // and `at` — so a snoozed alarm, back at a new time, is a new ring and is claimed anew.
    property var taken: ({})

    function dueAlarms() {
        const now = Date.now()
        const list = (root.notesDoc && root.notesDoc.alarms) ? root.notesDoc.alarms : []
        const out = []
        for (let i = 0; i < list.length; i++) {
            const a = list[i]
            const ring = a.key + "|" + a.at
            if (root.taken[ring] === true) continue
            // "YYYY-MM-DDTHH:MM" is local time; Date.parse would take it as UTC.
            const p = String(a.at).match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/)
            if (!p) continue
            const when = new Date(Number(p[1]), Number(p[2]) - 1, Number(p[3]), Number(p[4]), Number(p[5])).getTime()
            if (when <= now)
                out.push({ alarm: a, when: when, ring: ring })
        }
        out.sort((x, y) => x.when - y.when)
        return out
    }

    function checkAlarms() {
        if (!root.cfg.notes || !root.cfg.reminders) return
        const rep = root.fullRepresentationItem
        if (!rep || rep.reminderOpen()) return
        const due = root.dueAlarms()
        if (due.length === 0) return
        const first = due[0]
        root.taken[first.ring] = true
        claimer.pending = first
        claimer.connectSource(command("claim '" + String(first.ring).replace(/'/g, "'\\''") + "'"))
    }

    Timer {
        interval: 30000
        running: root.cfg.notes && root.cfg.reminders
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkAlarms()
    }
    onNotesDocChanged: Qt.callLater(root.checkAlarms)

    P5Support.DataSource {
        id: claimer
        engine: "executable"
        interval: 0
        property var pending: null
        onNewData: function(source, data) {
            disconnectSource(source)
            let claimed = false
            try {
                const got = JSON.parse(String(data.stdout))
                claimed = got && got.claimed === true
            } catch (e) {
                claimed = false
            }
            const it = claimer.pending
            claimer.pending = null
            if (claimed && it && root.fullRepresentationItem)
                root.fullRepresentationItem.showReminder(it.alarm, Date.now() - it.when > 10 * 60000)
            else
                Qt.callLater(root.checkAlarms)     // another instance has it: the next one
        }
    }

    // What the sheet chose: the script records it and answers with the document.
    function settle(what, a) {
        const key = "'" + String(a.key).replace(/'/g, "'\\''") + "'"
        let cmd = ""
        switch (what) {
        case "snooze": cmd = "snooze " + key + " " + Math.max(1, root.cfg.snoozeMinutes); break
        case "hour": cmd = "snooze " + key + " 60"; break
        case "tomorrow": {
            const d = new Date()
            d.setDate(d.getDate() + 1)
            const stamp = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-"
                        + String(d.getDate()).padStart(2, "0") + "T" + root.remindHour.padStart(5, "0")
            cmd = "snooze " + key + " " + stamp
            break
        }
        case "complete":
            cmd = "done '" + String(a.account).replace(/'/g, "'\\''") + "' '" + String(a.uid).replace(/'/g, "'\\''") + "' " + key
            break
        default: cmd = "ack " + key
        }
        delete root.taken[a.key]
        notesWriter.connectSource(command(cmd + root.alarmOptions))
    }

    // The optional system notification and sound, beside the sheet.
    P5Support.DataSource {
        id: side
        engine: "executable"
        interval: 0
        onNewData: function(source, data) { disconnectSource(source) }
    }
    function shQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function announce(a) {
        if (root.cfg.remindSystem) {
            const title = (a.time ? a.time + "  " : "") + String(a.summary || "")
            side.connectSource("notify-send -a plaincalendar -i office-calendar " + shQuote(title)
                               + " " + shQuote(String(a.description || "").split("\n")[0]) + " # " + Date.now())
        }
        const sound = String(root.cfg.remindSound || "").trim()
        if (sound.length > 0)
            side.connectSource("(pw-play " + shQuote(sound) + " || paplay " + shQuote(sound) + ") >/dev/null 2>&1 & # " + Date.now())
    }

    // ── The mouse ─────────────────────────────────────────────────────────────
    // The shell's edit mode: the one moment a click-through widget must take the mouse.
    readonly property bool shellEditMode: (Plasmoid.containment && Plasmoid.containment.corona)
        ? Plasmoid.containment.corona.editMode : false
    readonly property bool passing: cfg.clickThrough && !shellEditMode

    // Click-through, in two shapes. With the notes off the widget takes no mouse at all:
    // the wrapper plasmashell puts around every desktop applet is disabled, both buttons
    // land on the desktop, and an empty containment mask keeps the desktop's right-click
    // menu (decision 8, the weather's way). With the notes on, the day rows must still
    // take clicks, so the wrapper stays enabled and gets a containmentMask of the rows'
    // rectangle instead — the player's way (decision 11): inside it the left button
    // reaches the view's MouseArea, outside it everything goes through, and the widget's
    // own menu opens over the rows only. Off in edit mode, so the shell's handles apply.
    readonly property bool maskedRows: passing && cfg.notes
    Binding {
        target: root.parent
        property: "enabled"
        value: !root.passing || root.cfg.notes
        when: root.parent !== null && ("editModeCondition" in root.parent)
    }
    Binding {
        target: root.parent
        property: "containmentMask"
        value: root.maskedRows ? root.fullRepresentationItem?.wrapperMask ?? null : null
        when: root.parent !== null && ("editModeCondition" in root.parent)
    }
    // ⚠️ "containmentMask:" on a PlasmoidItem is a compile error (revision 2.11 is not
    // pulled in by org.kde.plasma.plasmoid); a Binding by name goes through QQmlProperty,
    // which does not check revisions. See docs/GOTCHAS.md.
    Binding {
        target: root
        property: "containmentMask"
        value: !root.passing ? null
            : (root.cfg.notes ? root.fullRepresentationItem?.rootMask ?? null : noHitMask)
    }
    Item { id: noHitMask; width: 0; height: 0; visible: false }

    fullRepresentation: Item {
        id: rep

        // Input off on the widget itself while everything passes through; with the notes
        // on the view's MouseArea is the one thing that takes the mouse.
        enabled: !root.passing || root.cfg.notes

        implicitWidth: root.boardWidth
        implicitHeight: root.boardHeight

        // The two masks for the bindings above: the day rows' rectangle mapped into the
        // wrapper's and into the PlasmoidItem's coordinates. mapToItem() is a function, so
        // the positions along the chain are read first and the binding follows a move.
        readonly property Item wrapperMask: wrapperMaskItem
        readonly property Item rootMask: rootMaskItem

        function maskRect(into) {
            const chain = [root.x, root.y, rep.x, rep.y, view.x, view.y]
            const g = view.gridRect
            return (into && chain) ? view.mapToItem(into, g.x, g.y, g.width, g.height) : Qt.rect(0, 0, 0, 0)
        }
        Item {
            id: wrapperMaskItem
            visible: false
            readonly property rect r: rep.maskRect(root.parent)
            x: r.x; y: r.y; width: r.width; height: r.height
        }
        Item {
            id: rootMaskItem
            visible: false
            readonly property rect r: rep.maskRect(root)
            x: r.x; y: r.y; width: r.width; height: r.height
        }

        // The reminder sheet hangs from the alarm's day when the grid shows it, else from
        // the widget's first line.
        function reminderOpen() { return reminder.visible }
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

            months: root.cfg.months
            cellWidth: root.cfg.cellWidth
            weekNumbers: root.cfg.weekNumbers
            firstDay: root.cfg.firstDay
            fillDays: root.cfg.fillDays
            weekendAccent: root.cfg.weekendAccent

            notes: root.notesDoc
            notesOn: root.cfg.notes
            upcoming: root.cfg.upcoming
            activeKey: sticker.visible ? sticker.dateKey : ""

            fontFamily: root.face
            fontSize: root.cfg.fontSize
            colorFg: root.cfg.colorFg
            colorAccent: root.cfg.colorAccent
            colorDim: root.cfg.colorDim
            colorToday: root.cfg.colorToday
            colorNote: root.cfg.colorNote

            onDayClicked: (key, x, y, w, h) => {
                // The sticker hangs from an invisible item laid over the clicked cell.
                anchor.x = x; anchor.y = y; anchor.width = w; anchor.height = h
                const days = root.notesDoc && root.notesDoc.days ? root.notesDoc.days : {}
                sticker.open(key, days[key] || [], anchor)
            }
        }

        Item { id: anchor; visible: false }
        Item { id: remindAnchor; visible: false }

        Sticker {
            id: sticker
            accounts: root.notesDoc && root.notesDoc.accounts ? root.notesDoc.accounts : []
            noteAccount: root.cfg.noteAccount.length > 0 ? root.cfg.noteAccount : "local"
            reminders: root.cfg.reminders
            remindHour: root.remindHour

            fontFamily: root.face
            fontSize: root.cfg.fontSize
            colorFg: root.cfg.colorFg
            colorAccent: root.cfg.colorAccent
            colorDim: root.cfg.colorDim
            colorNote: root.cfg.colorNote
            colorPaper: root.cfg.colorPaper
            paperOpacity: root.cfg.paperOpacity
            frame: root.cfg.frame
            columns: root.cfg.stickerColumns
            animation: root.cfg.stickerAnimation

            onSave: (key, text) => root.saveNote(key, text)
        }

        Reminder {
            id: reminder
            accounts: root.notesDoc && root.notesDoc.accounts ? root.notesDoc.accounts : []
            snoozeMinutes: root.cfg.snoozeMinutes
            hour: root.remindHour

            fontFamily: root.face
            fontSize: root.cfg.fontSize
            colorFg: root.cfg.colorFg
            colorAccent: root.cfg.colorAccent
            colorDim: root.cfg.colorDim
            colorNote: root.cfg.colorNote
            colorPaper: root.cfg.colorPaper
            paperOpacity: root.cfg.paperOpacity
            frame: root.cfg.frame
            columns: root.cfg.stickerColumns
            animation: root.cfg.stickerAnimation

            onChoose: (what, a) => root.settle(what, a)
        }
    }
}
