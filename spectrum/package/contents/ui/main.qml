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
            text: i18n("no data: the plainspectrum-relay service does not answer\nport %1",
                       root.cfg.relayPort)
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
