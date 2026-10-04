import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

// Plasmoid host for the calendar. The grid and the drawing live in CalendarView.qml next
// to this file, the sticker in Sticker.qml; this one is the shell-facing part — size,
// settings, click-through, the notes script — and has the same shape as the weather's
// and the player's hosts.
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
    // after every note saved. Only the last answer is kept, in memory: the script's own
    // caches carry the state across a shell restart.
    readonly property string notesScript: Qt.resolvedUrl("../code/notes.py").toString().replace("file://", "")
    property var notesDoc: ({ days: {}, upcoming: [], accounts: [] })

    function takeDocument(stdout) {
        try {
            const doc = JSON.parse(String(stdout))
            if (doc && doc.days)
                root.notesDoc = doc
        } catch (e) {
            console.warn("plaincalendar: notes.py did not answer with a document:", e)
        }
    }

    P5Support.DataSource {
        id: notesSource
        engine: "executable"
        interval: Math.max(1, root.cfg.syncMinutes) * 60000
        connectedSources: root.cfg.notes
            ? ["python3 '" + root.notesScript + "' sync --every " + Math.max(1, root.cfg.syncMinutes)
               + " --upcoming " + Math.max(1, root.cfg.upcoming)]
            : []
        onNewData: function(source, data) { root.takeDocument(data.stdout) }
    }

    // One-shot commands — a save, a delete — each its own source, dropped once answered.
    // UTF-8 goes through base64, so no quoting of the text ever reaches a shell.
    P5Support.DataSource {
        id: notesWriter
        engine: "executable"
        interval: 0
        onNewData: function(source, data) {
            disconnectSource(source)
            root.takeDocument(data.stdout)
        }
    }

    function saveNote(dateKey, text) {
        const account = root.cfg.noteAccount.length > 0 ? root.cfg.noteAccount : "local"
        const cmd = text.trim().length > 0
            ? "python3 '" + root.notesScript + "' set '" + account + "' '" + dateKey + "' '"
              + Qt.btoa(unescape(encodeURIComponent(text))) + "'"
            : "python3 '" + root.notesScript + "' delete '" + account + "' '" + dateKey + "'"
        notesWriter.connectSource(cmd + " # " + Date.now())
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

        Sticker {
            id: sticker
            accounts: root.notesDoc && root.notesDoc.accounts ? root.notesDoc.accounts : []
            noteAccount: root.cfg.noteAccount.length > 0 ? root.cfg.noteAccount : "local"

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
    }
}
