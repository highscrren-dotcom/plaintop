import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

// Plasmoid host. The data and the drawing live in shared/Spectrum.qml and shared/Ring.qml,
// which install.sh copies in next to this file — the standalone window host uses the same
// two files, so the logic has one home. The player in the centre of the ring is the
// player widget's own view, player/shared/PlayerView.qml, copied in the same way.
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

    // The player's board, measured as the player widget measures its own: `playerColumns`
    // characters wide and five lines tall — header, title, album, position, controls.
    // Not part of the size hint above: the board lives inside the ring, whatever its size.
    readonly property string playerFace: Qt.fontFamilies().includes(cfg.playerFontFamily)
        ? cfg.playerFontFamily : "monospace"
    TextMetrics {
        id: playerCell
        font.family: root.playerFace
        font.pointSize: root.cfg.playerFontSize
        text: "0"
    }
    // ⚠️ A real Text, not FontMetrics: with NativeRendering a line comes out at the
    // hinted height, and FontMetrics.height is short by a few pixels (docs/GOTCHAS.md).
    Text {
        id: playerLineProbe
        visible: false
        text: "0"
        font.family: root.playerFace
        font.pointSize: root.cfg.playerFontSize
        renderType: Text.NativeRendering
    }
    readonly property real playerWidth: Math.ceil(playerCell.advanceWidth * Math.max(22, cfg.playerColumns))
    readonly property real playerHeight: Math.ceil(playerLineProbe.implicitHeight * 5)

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

    // Click-through, everywhere but the player's controls row. The wrapper plasmashell
    // puts around every desktop applet (AppletContainer, our parent item) accepts the left
    // button unconditionally, waiting for press-and-hold, so the applet cannot let clicks
    // through from the inside. It is left enabled and given a containmentMask instead: an
    // Item whose x/y/width/height is the controls row's rectangle in the wrapper's own
    // coordinates — or 0×0, and nothing takes the mouse, while the player is off, has no
    // player on the bus or hides its controls. Qt's target search then skips the wrapper
    // wherever its contains() says no but still visits its children — a click inside the
    // rectangle reaches the glyph's MouseArea, one outside lands on the desktop or the
    // widget beneath, and so does the hover; press-and-hold inside the rectangle enters
    // edit mode as for any applet. Only the mask's x/y and size matter, not its parent or
    // visibility. Off in edit mode, so the shell's own move, resize and configure handles
    // apply to the whole widget. Proven on the stand, tests/passthrough.qml, tests 10–17
    // — docs/GOTCHAS.md.
    // ⚠️ The one trap (test_10): any child that accepts the left button outside the
    // rectangle arms the wrapper's press-and-hold timer, and a plain click on it would
    // enter edit mode 800 ms later. A Text with the default textFormat is such a child, so
    // every Text here and in PlayerView.qml is textFormat: PlainText; the ring's bars are
    // Rectangles and take no input, and nothing else in the widget takes the mouse but the
    // player's three control MouseAreas.
    readonly property bool passing: cfg.clickThrough && !shellEditMode
    Binding {
        target: root.parent
        property: "containmentMask"
        value: root.passing ? root.fullRepresentationItem?.wrapperMask ?? null : null
        when: root.parent !== null && ("editModeCondition" in root.parent)
    }

    // The right button needs the same rectangle once more, on the PlasmoidItem: the
    // desktop looks for the applet under a right-click geometrically
    // (ContainmentItem::mousePressEvent asks every PlasmoidItem contains(pos)), so the
    // widget's own menu opens over the controls only, and the desktop's elsewhere.
    // ⚠️ Declared with revision 2.11 in QtQuick, and org.kde.plasma.plasmoid does not
    // pull that revision in, so "containmentMask:" on a PlasmoidItem is a compile error
    // ("not available in org.kde.plasma.plasmoid 255.255"). Binding by name goes through
    // QQmlProperty, which does not check revisions.
    Binding {
        target: root
        property: "containmentMask"
        value: root.passing ? root.fullRepresentationItem?.rootMask ?? null : null
    }

    fullRepresentation: Item {
        id: rep

        implicitWidth: root.boardWidth
        implicitHeight: root.boardHeight

        // The two masks for the bindings above, reached through fullRepresentationItem.
        readonly property Item wrapperMask: wrapperMaskItem
        readonly property Item rootMask: rootMaskItem

        // The embedded player's controls row mapped through the loader's item into the
        // wrapper's and into the PlasmoidItem's coordinates; an empty rectangle without
        // the player. With NoBackground the wrapper's padding is 0 and the two are the same
        // rectangle; mapped anyway, so a background put back through the dialog does not
        // shift the mask off the glyphs. mapToItem() is a function, so the positions along
        // the chain are read first: a binding follows what it reads, and this one then
        // follows a move of any link — the board moves with the ring's geometry.
        function maskRect(into) {
            const view = playerLoader.item
            const chain = [root.x, root.y, rep.x, rep.y, playerLoader.x, playerLoader.y]
            if (!into || !view || !chain)
                return Qt.rect(0, 0, 0, 0)
            const c = view.controlsRect
            return view.mapToItem(into, c.x, c.y, c.width, c.height)
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

        Ring {
            id: ring
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

        // The player, in the centre of the ring. A Loader, so nothing — not even the MPRIS
        // model — exists while it is off. The bars grow outward from the ring's radius, so
        // the disc inside is free; on a line every pixel belongs to the bars at full
        // level, and the board goes along the edge they reach last — above bars that grow
        // up, below bars that hang down — or, if the applet was made taller than the
        // board, entirely outside their reach. Its controls row is the one place the
        // widget takes the mouse while clicks pass through — the masks above.
        Loader {
            id: playerLoader
            active: root.cfg.playerShow
            width: root.playerWidth
            height: root.playerHeight
            x: Math.round(ring.x + ring.width / 2 - width / 2)
            y: Math.round(ring.isRing
                ? ring.y + ring.height / 2 - height / 2
                : (root.cfg.growth === 1
                    ? Math.min(parent.height - height, ring.y + ring.height)
                    : Math.max(0, ring.y - height)))

            sourceComponent: PlayerView {
                quietWhenNoPlayer: true

                playerFilter: root.cfg.playerFilter
                showAlbum: root.cfg.playerAlbum
                showControls: root.cfg.playerControls
                columns: Math.max(22, root.cfg.playerColumns)

                fontFamily: root.playerFace
                fontSize: root.cfg.playerFontSize
                colorFg: root.cfg.playerColorFg
                colorAccent: root.cfg.playerColorAccent
                colorDim: root.cfg.playerColorDim
            }
        }

        // Without the relay there is nothing to draw, and silence would look the same as
        // a missing service — so say which it is. With the player on, the notice steps
        // aside — below the board, or above it when the board sits in the lower half —
        // rather than print itself over the track.
        Text {
            id: relayNotice
            visible: !spectrum.relayUp
            anchors.horizontalCenter: parent.horizontalCenter
            y: !playerLoader.active
                ? Math.round((parent.height - height) / 2)
                : (playerLoader.y + playerLoader.height / 2 > parent.height / 2
                    ? playerLoader.y - height - 4
                    : playerLoader.y + playerLoader.height + 4)
            color: root.cfg.color
            opacity: 0.7
            font.family: "monospace"
            text: i18n("no data: the plainspectrum-relay service does not answer\nport %1",
                       root.cfg.relayPort)
            horizontalAlignment: Text.AlignHCenter
            // Not a mouse target under the partial mask (the trap above, test_10).
            textFormat: Text.PlainText
        }
    }
}
