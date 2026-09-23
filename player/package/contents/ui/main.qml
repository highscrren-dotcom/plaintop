import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

// Plasmoid host for the player. The model, the lines and the controls live in
// PlayerView.qml next to this file; this one is the shell-facing part — size, settings,
// click-through — and has the same shape as the monitor's and the visualizer's hosts.
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

    // One character and one line of the widget's font. The applet is `columns` characters
    // wide and five lines tall — header, title, album, position, controls — whether or
    // not every line has something to say.
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
    // must be constant for the given settings: a hint that followed the lines shown would
    // make the containment relayout on every change and drop the widget into the 0,0
    // corner. See docs/GOTCHAS.md.
    readonly property real boardWidth: Math.ceil(cell.advanceWidth * Math.max(22, cfg.columns))
    readonly property real boardHeight: Math.ceil(lineProbe.implicitHeight * 5)

    Layout.minimumWidth: boardWidth
    Layout.minimumHeight: boardHeight
    Layout.preferredWidth: boardWidth
    Layout.preferredHeight: boardHeight

    // The shell's edit mode: the one moment a click-through widget must take the mouse.
    readonly property bool shellEditMode: (Plasmoid.containment && Plasmoid.containment.corona)
        ? Plasmoid.containment.corona.editMode : false

    // Click-through, everywhere but the controls row. The wrapper plasmashell puts around
    // every desktop applet (AppletContainer, our parent item) accepts the left button
    // unconditionally, waiting for press-and-hold, so the applet cannot let clicks through
    // from the inside. It is left enabled and given a containmentMask instead: an Item
    // whose x/y/width/height is the controls row's rectangle in the wrapper's own
    // coordinates. Qt's target search then skips the wrapper wherever its contains() says
    // no but still visits its children — a click inside the rectangle reaches the glyph's
    // MouseArea, one outside lands on the desktop or the widget beneath, and so does the
    // hover; press-and-hold inside the rectangle enters edit mode as for any applet.
    // Only the mask's x/y and size matter, not its parent or visibility. Off in edit mode,
    // so the shell's own move, resize and configure handles apply to the whole widget.
    // Proven on the stand, tests/passthrough.qml, tests 10–17 — docs/GOTCHAS.md.
    // ⚠️ The one trap (test_10): any child that accepts the left button outside the
    // rectangle arms the wrapper's press-and-hold timer, and a plain click on it would
    // enter edit mode 800 ms later. A Text with the default textFormat is such a child, so
    // every Text in PlayerView.qml is textFormat: PlainText, and nothing else in the
    // widget takes the mouse but the three control MouseAreas.
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

        // The controls row mapped into the wrapper's and into the PlasmoidItem's
        // coordinates. With NoBackground the wrapper's padding is 0 and the two are the
        // same rectangle; mapped anyway, so a background put back through the dialog does
        // not shift the mask off the glyphs. mapToItem() is a function, so the positions
        // along the chain are read first: a binding follows what it reads, and this one
        // then follows a move of any link as well as the row itself.
        function maskRect(into) {
            const chain = [root.x, root.y, rep.x, rep.y, view.x, view.y]
            const c = view.controlsRect
            return (into && chain) ? view.mapToItem(into, c.x, c.y, c.width, c.height) : Qt.rect(0, 0, 0, 0)
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

        PlayerView {
            id: view
            anchors.fill: parent

            playerFilter: root.cfg.player
            showAlbum: root.cfg.album
            showControls: root.cfg.controls
            columns: Math.max(22, root.cfg.columns)

            fontFamily: root.face
            fontSize: root.cfg.fontSize
            colorFg: root.cfg.colorFg
            colorAccent: root.cfg.colorAccent
            colorDim: root.cfg.colorDim
        }
    }
}
