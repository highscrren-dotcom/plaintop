import QtQuick
import plaintop

// The weather's window host: the shared WeatherView (its requests go to the sources
// straight from QML, as on Plasma — decision 10) with the cache and the guess kept in
// the settings through the service.
import "weather"
import "weather/Sources.js" as Sources
import "weather/Icons.js" as Icons

WidgetWindow {
    id: root
    widget: "weather"

    readonly property string face: fixedFace("fontFamily")
    TextMetrics {
        id: cell
        font.family: root.face
        font.pointSize: root.num("fontSize", 10)
        text: "0"
    }
    Text {
        id: lineProbe
        visible: false
        text: "0"
        font.family: root.face
        font.pointSize: root.num("fontSize", 10)
        renderType: Text.NativeRendering
    }
    Text {
        id: iconProbe
        visible: false
        text: Icons.BLANK.join("\n")
        textFormat: Text.PlainText
        font.family: root.face
        font.pixelSize: Math.max(1, root.num("iconSize", 3))
        lineHeightMode: Text.FixedHeight
        lineHeight: Math.max(1, root.num("iconSize", 3))
        renderType: Text.NativeRendering
    }

    readonly property int dayRows: Math.max(0, Math.min(Sources.get(str("source", "open-meteo")).maxDays, num("days", 3)))
    readonly property real lineHeight: lineProbe.implicitHeight
    readonly property real iconWidth: num("icon", 1) === 1 ? iconProbe.implicitWidth + cell.advanceWidth : 0
    readonly property real iconHeight: num("icon", 1) === 1 ? Icons.HEIGHT * Math.max(1, num("iconSize", 3)) : 0

    width: Math.ceil(iconWidth + cell.advanceWidth * Math.max(10, num("columns", 52)))
    height: Math.ceil(lineHeight * (1 + (flag("attribution", true) ? 1 : 0))
                      + Math.max(iconHeight, lineHeight * (1 + dayRows)))

    readonly property var lines: weatherView.lines

    WeatherView {
        id: weatherView
        anchors.fill: parent

        // Through the service: the system proxy and the certificate store are the
        // service's (Python), not the qml tool's. The first desk, on a corporate network,
        // stayed "offline".
        requestPrefix: "http://127.0.0.1:" + Service.port + "/fetch?url="

        latitude: root.str("latitude", "")
        longitude: root.str("longitude", "")
        placeName: root.str("placeName", "")
        timezone: root.str("timezone", "")
        guessedLat: root.str("guessedLat", "")
        guessedLon: root.str("guessedLon", "")
        guessedName: root.str("guessedName", "")
        source: root.str("source", "open-meteo")
        apiKey: root.str("apiKey", "")
        units: root.num("units", 0)
        days: root.num("days", 3)
        attribution: root.flag("attribution", true)
        columns: Math.max(10, root.num("columns", 52))
        icon: root.num("icon", 1)
        iconSize: root.num("iconSize", 3)
        cachedJson: root.str("lastWeather", "")
        cachedTime: root.str("lastFetched", "")

        fontFamily: root.face
        fontSize: root.num("fontSize", 10)
        colorFg: root.str("colorFg", "#C8CCD4")
        colorAccent: root.str("colorAccent", "#E05561")
        colorDim: root.str("colorDim", "#6B7280")

        onFetched: (json, iso) => root.save({ lastWeather: json, lastFetched: iso })
        onGuessed: (lat, lon, name) => root.save({ guessedLat: lat, guessedLon: lon, guessedName: name })
    }
}
