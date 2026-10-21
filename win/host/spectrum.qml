import QtQuick
import plaintop

// The visualizer's window host: the shared Spectrum (polls the service's /bands, the
// relay's protocol) and Ring, with the player view in the centre as an option — the
// same arithmetic as the plasmoid's main.qml.
import "spectrum"

WidgetWindow {
    id: root
    widget: "spectrum"

    readonly property int layout: num("layout", 0)
    readonly property real boardWidth: layout === 0
        ? 2 * (num("radius", 360) + num("minLength", 10) + num("maxLength", 170) + num("thickness", 5))
        : Math.max(2, num("bars", 160)) * (num("thickness", 5) + num("spacing", 2))
    readonly property real boardHeight: layout === 0
        ? 2 * (num("radius", 360) + num("minLength", 10) + num("maxLength", 170) + num("thickness", 5))
        : num("minLength", 10) + num("maxLength", 170) + num("thickness", 5)

    width: boardWidth
    readonly property bool relayUp: spectrum.relayUp
    readonly property bool sounding: spectrum.sounding
    height: boardHeight

    readonly property string playerFace: fixedFace("playerFontFamily")
    TextMetrics {
        id: playerCell
        font.family: root.playerFace
        font.pointSize: root.num("playerFontSize", 10)
        text: "0"
    }
    Text {
        id: playerLineProbe
        visible: false
        text: "0"
        font.family: root.playerFace
        font.pointSize: root.num("playerFontSize", 10)
        renderType: Text.NativeRendering
    }
    readonly property real playerWidth: Math.ceil(playerCell.advanceWidth * Math.max(22, num("playerColumns", 44)))
    readonly property real playerHeight: Math.ceil(playerLineProbe.implicitHeight * 5)

    Spectrum {
        id: spectrum
        // The relay's port is the service's unless the setting says otherwise.
        relayPort: root.num("relayPort", 8788) === 8788 ? Service.port : root.num("relayPort", 8788)
        bars: root.num("bars", 160)
        dataRate: root.num("dataRate", 30)
        idleRate: root.num("idleRate", 4)
        hideWhenQuiet: root.flag("hideWhenQuiet", true)
        quietThreshold: root.num("quietThreshold", 2)
        quietDelayMs: root.num("quietDelayMs", 900)
        mirror: root.flag("mirror", false)
        reverse: root.flag("reverse", false)
        mono: root.flag("monoSpectrum", true)
    }

    Ring {
        id: ring
        anchors.centerIn: parent
        source: spectrum

        layoutMode: root.layout
        bars: root.num("bars", 160)
        radius: root.num("radius", 360)
        span: root.num("span", 360)
        startAngle: root.num("startAngle", 0)
        spacing: root.num("spacing", 2)
        thickness: root.num("thickness", 5)
        minLength: root.num("minLength", 10)
        maxLength: root.num("maxLength", 170)
        growth: root.num("growth", 0)
        element: root.num("element", 0)
        blockSize: root.num("blockSize", 6)
        blockGap: root.num("blockGap", 3)
        rounded: root.flag("rounded", false)
        tint: root.str("color", "#C8CCD4")
        tintHigh: root.str("colorHigh", "")
        opacityPercent: root.num("opacityPercent", 100)
        guide: root.flag("guide", false)
        smoothMs: root.num("smoothMs", 70)
        fadeMs: root.num("fadeMs", 500)
        hideWhenQuiet: root.flag("hideWhenQuiet", true)
    }

    Loader {
        id: playerLoader
        active: root.flag("playerShow", false)
        width: root.playerWidth
        height: root.playerHeight
        x: Math.round(ring.x + ring.width / 2 - width / 2)
        y: Math.round(ring.isRing
            ? ring.y + ring.height / 2 - height / 2
            : (root.num("growth", 0) === 1
                ? Math.min(parent.height - height, ring.y + ring.height)
                : Math.max(0, ring.y - height)))

        sourceComponent: PlayerView {
            quietWhenNoPlayer: true
            playerFilter: root.str("playerFilter", "")
            showAlbum: root.flag("playerAlbum", true)
            showControls: root.flag("playerControls", true)
            columns: Math.max(22, root.num("playerColumns", 44))
            fontFamily: root.playerFace
            fontSize: root.num("playerFontSize", 10)
            colorFg: root.str("playerColorFg", "#C8CCD4")
            colorAccent: root.str("playerColorAccent", "#E05561")
            colorDim: root.str("playerColorDim", "#6B7280")
        }
    }

    // Without a capture library the service answers silence for ever, and a silent
    // spectrum is an empty, invisible window — "I do not see the spectrum", the first
    // desk said. /state names the backend; "none" is said here, where the ring would be.
    property string captureBackend: ""
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: Service.getJson("/state", function(d) { root.captureBackend = d ? String(d.backend || "") : "" })
    }
    Text {
        id: captureNotice
        visible: spectrum.relayUp && root.captureBackend === "none"
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((parent.height - height) / 2)
        color: root.str("color", "#C8CCD4")
        opacity: 0.7
        font.family: root.fixedFace("")
        text: root.i18n("no sound capture: the service has no WASAPI loopback\n(the soundcard package is not inside)")
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
    }

    Text {
        id: relayNotice
        visible: !spectrum.relayUp
        anchors.horizontalCenter: parent.horizontalCenter
        y: !playerLoader.active
            ? Math.round((parent.height - height) / 2)
            : (playerLoader.y + playerLoader.height / 2 > parent.height / 2
                ? playerLoader.y - height - 4
                : playerLoader.y + playerLoader.height + 4)
        color: root.str("color", "#C8CCD4")
        opacity: 0.7
        font.family: root.fixedFace("")
        text: root.i18n("no data: the plainspectrum-relay service does not answer\nport %1", spectrum.relayPort)
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
    }
}
