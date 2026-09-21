import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

// Plasmoid host. The data and the drawing live in shared/Spectrum.qml and shared/Ring.qml,
// which install.sh copies in next to this file — the standalone window host uses the same
// two files, so the logic has one home.
PlasmoidItem {
    id: root

    // The visualizer lives on the wallpaper: no plate, no frame. The user can put one
    // back through the standard dialog.
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    preferredRepresentation: fullRepresentation

    readonly property var cfg: Plasmoid.configuration

    // ⚠️ The size hint on the root must be constant for the given settings: a hint that
    // follows live data makes the containment relayout every frame and drop the widget
    // into the 0,0 corner. See docs/GOTCHAS.md.
    readonly property real boardWidth: cfg.layout === 0
        ? 2 * (cfg.radius + cfg.minLength + cfg.maxLength + cfg.thickness)
        : Math.max(2, cfg.bars) * (cfg.thickness + cfg.spacing)
    readonly property real boardHeight: cfg.layout === 0
        ? 2 * (cfg.radius + cfg.minLength + cfg.maxLength + cfg.thickness)
        : cfg.minLength + cfg.maxLength + cfg.thickness

    Layout.minimumWidth: boardWidth
    Layout.minimumHeight: boardHeight
    Layout.preferredWidth: boardWidth
    Layout.preferredHeight: boardHeight

    Spectrum {
        id: spectrum
        relayPort: root.cfg.relayPort
        bars: root.cfg.bars
        dataRate: root.cfg.dataRate
        idleRate: root.cfg.idleRate
        hideWhenQuiet: root.cfg.hideWhenQuiet
        quietThreshold: root.cfg.quietThreshold
        quietDelayMs: root.cfg.quietDelayMs
        mirror: root.cfg.mirror
        reverse: root.cfg.reverse
    }

    fullRepresentation: Item {
        // Input off means the click lands on the containment instead of the widget. That
        // hands over the right button; the left one stays with the applet container no
        // matter what — see docs/GOTCHAS.md.
        enabled: !root.cfg.clickThrough

        implicitWidth: root.boardWidth
        implicitHeight: root.boardHeight

        Ring {
            anchors.centerIn: parent
            source: spectrum

            layoutMode: root.cfg.layout
            bars: root.cfg.bars
            radius: root.cfg.radius
            span: root.cfg.span
            startAngle: root.cfg.startAngle
            spacing: root.cfg.spacing
            thickness: root.cfg.thickness
            minLength: root.cfg.minLength
            maxLength: root.cfg.maxLength
            growth: root.cfg.growth
            element: root.cfg.element
            blockSize: root.cfg.blockSize
            blockGap: root.cfg.blockGap
            rounded: root.cfg.rounded
            tint: root.cfg.color
            tintHigh: root.cfg.colorHigh
            opacityPercent: root.cfg.opacityPercent
            guide: root.cfg.guide
            smoothMs: root.cfg.smoothMs
            fadeMs: root.cfg.fadeMs
            hideWhenQuiet: root.cfg.hideWhenQuiet
        }

        // Without the relay there is nothing to draw, and silence would look the same as
        // a missing service — so say which it is.
        Text {
            visible: !spectrum.relayUp
            anchors.centerIn: parent
            color: root.cfg.color
            opacity: 0.7
            font.family: "monospace"
            text: "нет данных: служба plainspectrum-relay не отвечает\nпорт " + root.cfg.relayPort
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
