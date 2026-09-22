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
    // schema/widget.json (plasmoid/generate.py puts it in the package).
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

    fullRepresentation: Item {
        // Input off means the click lands on the containment instead of the widget. That
        // hands over the right button; the left one stays with the applet container no
        // matter what — see docs/GOTCHAS.md.
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
