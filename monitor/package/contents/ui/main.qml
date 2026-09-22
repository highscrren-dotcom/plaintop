import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

import "../code/description.js" as Description

// Plasmoid host for the text monitor. The data and the drawing live in
// shared/MonitorData.qml and shared/MonitorView.qml, which install.sh copies in next to
// this file — the standalone click-through window uses the same two files.
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

    MonitorData {
        id: monitorData
        blocks: root.blocks
        rate: root.cfg.updateInterval
        processInterval: root.cfg.processInterval
        servicesScript: Qt.resolvedUrl("../code/services.sh").toString().replace("file://", "")
    }

    // The shell's edit mode: the one moment a click-through widget must take the mouse.
    readonly property bool shellEditMode: (Plasmoid.containment && Plasmoid.containment.corona)
        ? Plasmoid.containment.corona.editMode : false

    // Click-through. Input off on the representation alone hands over only the right
    // button: the wrapper plasmashell puts around every desktop applet (AppletContainer,
    // our parent item) accepts the left button unconditionally, waiting for press-and-hold.
    // Disabled, that wrapper and everything inside it drop out of Qt's mouse delivery and
    // both buttons land on the desktop below. Re-enabled in edit mode, so the widget can
    // still be moved, resized and configured. Verified on Plasma 6.7.5 — docs/GOTCHAS.md.
    Binding {
        target: root.parent
        property: "enabled"
        value: !root.cfg.clickThrough || root.shellEditMode
        when: root.parent !== null && ("editModeCondition" in root.parent)
    }

    // The right button needs one thing more: the desktop looks for the applet under a
    // right-click geometrically (ContainmentItem::mousePressEvent asks every PlasmoidItem
    // contains(pos) and never looks at enabled), so with only the wrapper disabled the
    // widget's own menu would still open. An empty containment mask makes contains()
    // answer "no", and the desktop shows its own menu, as if the widget were not there.
    // ⚠️ Declared with revision 2.11 in QtQuick, and org.kde.plasma.plasmoid does not
    // pull that revision in, so "containmentMask:" on a PlasmoidItem is a compile error
    // ("not available in org.kde.plasma.plasmoid 255.255"). Binding by name goes through
    // QQmlProperty, which does not check revisions.
    Binding {
        target: root
        property: "containmentMask"
        value: (root.cfg.clickThrough && !root.shellEditMode) ? noHitMask : null
    }
    Item { id: noHitMask; width: 0; height: 0; visible: false }

    fullRepresentation: Item {
        // Input off on the widget itself: in edit mode the wrapper takes the mouse, not us.
        enabled: !root.cfg.clickThrough

        implicitWidth: root.cfg.widgetWidth
        implicitHeight: root.cfg.widgetHeight

        MonitorView {
            anchors.fill: parent
            lines: monitorData.lines

            fontFamily: root.cfg.fontFamily
            fontSize: root.cfg.fontSize
            padLeft: root.cfg.padLeft
            padTop: root.cfg.padTop

            colorFg: root.cfg.colorFg
            colorAccent: root.cfg.colorAccent
            colorDim: root.cfg.colorDim
            colorValue: root.cfg.colorValue
        }
    }
}
