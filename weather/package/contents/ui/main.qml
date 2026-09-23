import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

// Plasmoid host for the weather. The requests, the lines and the drawing live in
// WeatherView.qml next to this file; this one is the shell-facing part — size, settings,
// click-through, the cache — and has the same shape as the player's host.
PlasmoidItem {
    id: root

    // The widget lives on the wallpaper: no plate, no frame. The user can put one back
    // through the standard dialog.
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    preferredRepresentation: fullRepresentation

    readonly property var cfg: Plasmoid.configuration

    // One character and one line of the widget's font. The applet is `columns` characters
    // wide and as many lines tall as the settings say — header, now, one per forecast
    // day, the attribution — whether or not every line has something to say.
    TextMetrics {
        id: cell
        font.family: root.cfg.fontFamily
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
        font.family: root.cfg.fontFamily
        font.pointSize: root.cfg.fontSize
        renderType: Text.NativeRendering
    }

    // ⚠️ The containment takes the applet size from Layout.* ON THE ROOT, and the hint
    // must be constant for the given settings: a hint that followed the lines shown would
    // make the containment relayout on every change and drop the widget into the 0,0
    // corner. See docs/GOTCHAS.md.
    readonly property int rows: 2 + Math.max(0, Math.min(7, cfg.days)) + (cfg.attribution ? 1 : 0)
    readonly property real boardWidth: Math.ceil(cell.advanceWidth * Math.max(10, cfg.columns))
    readonly property real boardHeight: Math.ceil(lineProbe.implicitHeight * rows)

    Layout.minimumWidth: boardWidth
    Layout.minimumHeight: boardHeight
    Layout.preferredWidth: boardWidth
    Layout.preferredHeight: boardHeight

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

        WeatherView {
            anchors.fill: parent

            latitude: root.cfg.latitude
            longitude: root.cfg.longitude
            placeName: root.cfg.placeName
            guessedLat: root.cfg.guessedLat
            guessedLon: root.cfg.guessedLon
            guessedName: root.cfg.guessedName
            units: root.cfg.units
            days: root.cfg.days
            attribution: root.cfg.attribution
            columns: Math.max(10, root.cfg.columns)
            cachedJson: root.cfg.lastWeather
            cachedTime: root.cfg.lastFetched

            fontFamily: root.cfg.fontFamily
            fontSize: root.cfg.fontSize
            colorFg: root.cfg.colorFg
            colorAccent: root.cfg.colorAccent
            colorDim: root.cfg.colorDim

            // The cache and the guess live in the config, so they survive a shell restart
            // (verified in the offscreen host, 2026-09-23) and the widget has something to
            // draw before its first request completes.
            onFetched: (json, iso) => {
                root.cfg.lastWeather = json
                root.cfg.lastFetched = iso
            }
            onGuessed: (lat, lon, name) => {
                root.cfg.guessedLat = lat
                root.cfg.guessedLon = lon
                root.cfg.guessedName = name
            }
        }
    }
}
