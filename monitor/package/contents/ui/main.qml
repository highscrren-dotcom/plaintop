import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

import "../code/description.js" as Description

// Plasmoid host for the text monitor. The data and the drawing live in
// shared/MonitorData.qml and shared/MonitorView.qml, which install.sh copies in next to
// this file — the standalone click-through window used the same two files. The menu of an
// active line is ActionMenu.qml beside this file; running what it chooses is done here.
PlasmoidItem {
    id: root

    // The widget lives on the desktop background: no frame and no backdrop needed, but
    // the user can bring them back through the standard dialog.
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    preferredRepresentation: fullRepresentation

    readonly property var cfg: Plasmoid.configuration

    // ⚠️ The containment takes the applet size from Layout.* ON THE ROOT, and the hint
    // must be constant. While it depended on the text height, the containment rebuilt the
    // layout on every change of the line count and reset the widget to the 0,0 corner.
    Layout.minimumWidth: cfg.widgetWidth
    Layout.minimumHeight: cfg.widgetHeight
    Layout.preferredWidth: cfg.widgetWidth
    Layout.preferredHeight: cfg.widgetHeight

    // What to show and in which order comes from the description. The user's edit sits in
    // the settings as a JSON string; when it is empty, take the one generated from
    // schema/widget.json (monitor/generate.py puts it in the package).
    readonly property var blocks: {
        const raw = cfg.blocksJson
        if (raw && raw.length > 0) {
            try {
                const parsed = JSON.parse(raw)
                if (Array.isArray(parsed) && parsed.length > 0)
                    return parsed
            } catch (e) {
                console.warn("plaintop: the description in the settings does not parse, using the packaged one:", e)
            }
        }
        return Description.BLOCKS
    }

    // One character of the widget's font. The text area's width in characters comes from
    // it and the settings, so free-text lines are cut where the widget ends rather than
    // at a guessed count: 57 here at 500 px wide, 48 px of padding, 10 pt JetBrains Mono.
    TextMetrics {
        id: cell
        font.family: root.cfg.fontFamily
        font.pointSize: root.cfg.fontSize
        text: "0"
    }

    MonitorData {
        id: monitorData
        blocks: root.blocks
        rate: root.cfg.updateInterval
        processInterval: root.cfg.processInterval
        barWidth: root.cfg.barWidth
        barFill: root.cfg.barFill
        barEmpty: root.cfg.barEmpty
        separatorChar: root.cfg.separatorChar
        separatorWidth: root.cfg.separatorWidth
        sparkGlyphs: root.cfg.sparkGlyphs
        actions: root.cfg.actions
        servicesScript: Qt.resolvedUrl("../code/services.sh").toString().replace("file://", "")
        healthScript: Qt.resolvedUrl("../code/health.sh").toString().replace("file://", "")
        // Each column is cut at its own right edge: the first at the second column's
        // left edge while any block sits there, else at the widget's.
        columns: Math.max(20, Math.floor(((monitorData.twoColumns ? root.secondX : root.cfg.widgetWidth) - root.cfg.padLeft)
                                         / Math.max(1, cell.advanceWidth)))
        columns2: Math.max(20, Math.floor((root.cfg.widgetWidth - root.secondX) / Math.max(1, cell.advanceWidth)))
    }

    // The second column's left edge: the setting, or half the width.
    readonly property real secondX: root.cfg.secondColumn > 0 ? root.cfg.secondColumn : Math.round(root.cfg.widgetWidth / 2)

    // ── The mouse ─────────────────────────────────────────────────────────────
    // The shell's edit mode: the one moment a click-through widget must take the mouse.
    readonly property bool shellEditMode: (Plasmoid.containment && Plasmoid.containment.corona)
        ? Plasmoid.containment.corona.editMode : false
    readonly property bool passing: cfg.clickThrough && !shellEditMode
    readonly property bool actionsOn: cfg.actions

    // Click-through, in two shapes. With the active lines off the widget takes no mouse
    // at all: the wrapper plasmashell puts around every desktop applet (AppletContainer,
    // our parent item, which accepts the left button unconditionally) is disabled, so it
    // and everything inside it drop out of Qt's mouse delivery and both buttons land on
    // the desktop below; an empty containment mask keeps the desktop's right-click menu
    // (decision 8, verified on Plasma 6.7.5 — docs/GOTCHAS.md). With the active lines
    // on, those lines must still take clicks, so the wrapper stays enabled and gets a
    // containmentMask instead — the player's way (decision 11), but the mask is not a
    // rectangle: active lines are scattered down the column, so it is an object with a
    // contains(QPointF) method that asks the view whether an active line lies under the
    // point. Qt accepts any QObject with an invokable contains(QPointF) as a mask
    // (qquickitem.cpp, setContainmentMask); a QML function with typed parameters,
    // "function contains(p: point): bool", is such a method. Off in edit mode, so the
    // shell's own move, resize and configure handles apply to the whole widget.
    // Taken on the desktop and on the stand (test 18), Qt 6.11. Should a later Qt refuse
    // the object ("does not have an invokable contains method"), the mask reads back null
    // and `maskFallback` switches to a plain Item over the active lines' bounding
    // rectangle — coarser, but click-through holds.
    readonly property bool maskedLines: passing && actionsOn
    property bool maskFallback: false

    Binding {
        target: root.parent
        property: "enabled"
        value: !root.passing || root.actionsOn
        when: root.parent !== null && ("editModeCondition" in root.parent)
    }
    Binding {
        target: root.parent
        property: "containmentMask"
        value: root.maskedLines ? root.fullRepresentationItem?.wrapperMask ?? null : null
        when: root.parent !== null && ("editModeCondition" in root.parent)
    }
    // The right button needs the mask on the PlasmoidItem too: the desktop looks for the
    // applet under a right-click geometrically (ContainmentItem::mousePressEvent asks
    // every PlasmoidItem contains(pos) and never looks at enabled), so the widget's own
    // menu opens over an active line only, and the desktop's elsewhere.
    // ⚠️ Declared with revision 2.11 in QtQuick, and org.kde.plasma.plasmoid does not
    // pull that revision in, so "containmentMask:" on a PlasmoidItem is a compile error
    // ("not available in org.kde.plasma.plasmoid 255.255"). Binding by name goes through
    // QQmlProperty, which does not check revisions.
    Binding {
        target: root
        property: "containmentMask"
        value: !root.passing ? null
            : (root.actionsOn ? root.fullRepresentationItem?.rootMask ?? null : noHitMask)
    }
    Item { id: noHitMask; width: 0; height: 0; visible: false }

    // Did the wrapper take the function mask? A refused mask reads back null (a read the
    // engine may also decline, as undefined — then nothing is concluded).
    Timer {
        id: maskProbe
        interval: 400
        onTriggered: {
            const w = root.parent
            if (!w || !root.maskedLines || root.maskFallback) return
            if (w.containmentMask === null) {
                console.warn("plaintop: the function mask was refused — masking the active lines' bounding rectangle instead")
                root.maskFallback = true
            }
        }
    }
    onMaskedLinesChanged: if (maskedLines) maskProbe.restart()
    Component.onCompleted: if (maskedLines) maskProbe.restart()

    // ── Running the actions ───────────────────────────────────────────────────
    // One-shot commands through the executable engine, each its own source, dropped once
    // answered. A terminal or a GUI program is detached so the source answers at once,
    // and goes into a scope of its own (systemd-run --scope) so it outlives a restart of
    // the shell: setsid alone leaves it in plasma-plasmashell.service's cgroup, which
    // systemd kills whole on a restart (KillMode=control-group). Without systemd-run,
    // setsid only. A quick command — kill, systemctl, wpctl — runs attached, and a
    // non-zero exit shows its stderr in a notice.
    property string lastTitle: ""

    P5Support.DataSource {
        id: runner
        engine: "executable"
        interval: 0
        onNewData: function(source, data) {
            disconnectSource(source)
            const code = Number(data["exit code"])
            if (code !== 0 && !isNaN(code)) {
                const err = String(data.stderr || "").trim().split("\n")[0]
                root.fullRepresentationItem?.showNotice(root.lastTitle,
                    err.length > 0 ? err : i18nc("a line action failed: its exit code", "exit code %1", code))
            }
        }
    }

    // The shell command for an item: the editor's or the terminal's command from the
    // settings around it, a held terminal waits for Enter after the command ends.
    function command(it) {
        let cmd = String(it.run || "")
        if (it.editor === true)
            cmd = (String(root.cfg.editor).trim() || "kate") + " " + cmd
        if (it.terminal === true) {
            const body = it.hold === true ? cmd + "; printf '\\n[Enter] '; read -r _" : cmd
            cmd = (String(root.cfg.terminal).trim() || "konsole -e") + " sh -c " + monitorData.sh(body)
        }
        if (it.terminal === true || it.gui === true || it.editor === true)
            cmd = "if command -v systemd-run >/dev/null 2>&1; then setsid -f systemd-run --user --scope --quiet --collect -- "
                + cmd + " >/dev/null 2>&1; else setsid -f " + cmd + " >/dev/null 2>&1; fi"
        return cmd
    }

    function runItem(title, it) {
        if (!it) return
        if (it.configure === true) {
            Plasmoid.internalAction("configure").trigger()
            return
        }
        root.lastTitle = String(title || "")
        // A nonce: the engine keys sources by their text, and the same command twice
        // in a row would otherwise not run again.
        runner.connectSource(command(it) + " # " + Date.now())
    }

    fullRepresentation: Item {
        id: rep

        // Input off on the widget itself while everything passes through; with the active
        // lines on, their mouse areas are the one thing that takes the mouse.
        enabled: !root.passing || root.actionsOn

        implicitWidth: root.cfg.widgetWidth
        implicitHeight: root.cfg.widgetHeight

        // The two masks for the bindings above, reached through fullRepresentationItem:
        // the function masks, or the bounding rectangles once a refusal is seen.
        readonly property QtObject wrapperMask: root.maskFallback ? wrapperBounds : wrapperFn
        readonly property QtObject rootMask: root.maskFallback ? rootBounds : rootFn

        // Is an active line under this point of `frame`'s coordinates? The wrapper and
        // the PlasmoidItem each ask in their own; with NoBackground the two coincide,
        // mapped anyway for a background put back through the dialog.
        function hit(frame, p) {
            if (!frame) return false
            const q = view.mapFromItem(frame, p.x, p.y)
            return view.activeAt(q.x, q.y)
        }
        QtObject {
            id: wrapperFn
            function contains(p: point): bool { return rep.hit(root.parent, p) }
        }
        QtObject {
            id: rootFn
            function contains(p: point): bool { return rep.hit(root, p) }
        }

        // The fallback: the active lines' bounding rectangle, refreshed a moment after the
        // lines change so the column has laid them out.
        Item { id: wrapperBounds; visible: false }
        Item { id: rootBounds; visible: false }
        Timer {
            id: boundsTimer
            interval: 80
            onTriggered: rep.refreshBounds()
        }
        function refreshBounds() {
            const b = view.activeBounds()
            const place = function(item, frame) {
                const r = frame ? view.mapToItem(frame, b.x, b.y, b.width, b.height) : b
                item.x = r.x; item.y = r.y; item.width = r.width; item.height = r.height
            }
            place(wrapperBounds, root.parent)
            place(rootBounds, root)
        }
        Connections {
            target: monitorData
            function onLinesChanged() { if (root.maskFallback) boundsTimer.restart() }
            function onLines2Changed() { if (root.maskFallback) boundsTimer.restart() }
        }
        Connections {
            target: root
            function onMaskFallbackChanged() { if (root.maskFallback) boundsTimer.restart() }
        }

        function showNotice(title, text) {
            menu.notice(title, text, anchor)
        }

        MonitorView {
            id: view
            anchors.fill: parent
            lines: monitorData.lines
            lines2: monitorData.lines2
            secondColumn: root.secondX

            fontFamily: root.cfg.fontFamily
            fontSize: root.cfg.fontSize
            padLeft: root.cfg.padLeft
            padTop: root.cfg.padTop

            colorFg: root.cfg.colorFg
            colorAccent: root.cfg.colorAccent
            colorDim: root.cfg.colorDim
            colorValue: root.cfg.colorValue

            // A left click runs the first item, after a question when it is destructive;
            // the right button, or a line whose first item asks, opens the menu at the line.
            onActivate: (action, button, column, index, area) => {
                anchor.x = area.x
                anchor.y = area.y
                anchor.width = area.width
                anchor.height = area.height
                const items = action.items || []
                const first = items.length > 0 ? items[0] : null
                if (button === Qt.RightButton || first === null) {
                    view.framedColumn = column
                    view.framedIndex = index
                    menu.openMenu(action, anchor)
                } else if (first.confirm === true) {
                    view.framedColumn = column
                    view.framedIndex = index
                    menu.ask(action, first, anchor)
                } else {
                    root.runItem(action.title, first)
                }
            }
        }

        // The menu's visualParent: an invisible item laid over the clicked line.
        Item { id: anchor; visible: false; width: 1; height: 1 }

        ActionMenu {
            id: menu
            fontFamily: root.cfg.fontFamily
            fontSize: root.cfg.fontSize
            colorFg: root.cfg.colorFg
            colorAccent: root.cfg.colorAccent
            colorDim: root.cfg.colorDim
            colorValue: root.cfg.colorValue
            colorPaper: root.cfg.colorPaper
            paperOpacity: root.cfg.paperOpacity
            frame: root.cfg.frame
            onRun: it => root.runItem(menu.action ? menu.action.title : "", it)
            onVisibleChanged: if (!visible) { view.framedColumn = -1; view.framedIndex = -1 }
        }
    }
}
