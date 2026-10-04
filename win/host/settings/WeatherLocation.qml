pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../weather/Sources.js" as Sources

// Which source, where, in what units, how many days: weather/package/contents/ui/
// configLocation.qml. The place is looked up through Open-Meteo's geocoder from here
// whatever the source, with the page's own XMLHttpRequest as the plasmoid does it, and
// stored as coordinates; two typed numbers skip the lookup.
SettingsPage {
    id: page

    readonly property var sourceIds: Sources.ids
    readonly property string source: str("source", "open-meteo")
    readonly property bool needsKey: Sources.get(source).needsKey
    readonly property string latitude: str("latitude", "")
    readonly property string longitude: str("longitude", "")
    readonly property string placeName: str("placeName", "")

    property var results: []
    property string note: ""
    property var xhr: null
    property alias searchText: searchField.text

    // The two-letter language for the geocoder, so the places are named as the user would.
    function language() {
        const l = Qt.locale().name.split("_")[0].toLowerCase()
        return /^[a-z]{2}$/.test(l) ? l : "en"
    }

    function search() {
        const q = searchField.text.trim()
        if (q.length === 0)
            return
        // Two numbers are coordinates and need no lookup: "52.52, 13.41".
        const m = q.match(/^(-?\d+(?:\.\d+)?)[\s,;]+(-?\d+(?:\.\d+)?)$/)
        if (m) {
            const la = parseFloat(m[1]), lo = parseFloat(m[2])
            if (Math.abs(la) > 90 || Math.abs(lo) > 180) {
                page.results = []
                page.note = page.i18nc("typed coordinates out of range", "latitude is −90…90, longitude −180…180")
                return
            }
            page.choose(m[1], m[2], m[1] + ", " + m[2], "")
            page.results = []
            page.note = ""
            return
        }
        if (page.xhr !== null) {
            const old = page.xhr
            page.xhr = null
            old.abort()
        }
        const req = new XMLHttpRequest()
        page.xhr = req
        page.results = []
        page.note = page.i18nc("geocoding in progress", "searching…")
        req.onreadystatechange = function() {
            // The window may have closed with the request in flight.
            if (!page)
                return
            // ⚠️ Reading status before DONE throws.
            if (req.readyState !== XMLHttpRequest.DONE || page.xhr !== req)
                return
            page.xhr = null
            searchWatchdog.stop()
            let found = []
            if (req.status === 200) {
                try {
                    found = JSON.parse(req.responseText).results || []
                } catch (e) {
                    found = []
                }
                // The largest place of that name first: "Moscow" is Russia before Idaho.
                found.sort((a, b) => (b.population || 0) - (a.population || 0))
                page.note = found.length > 0 ? "" : page.i18nc("geocoding: no match", "nothing found")
            } else {
                page.note = page.i18nc("geocoding: the request failed", "the lookup failed — no network?")
            }
            page.results = found
        }
        req.open("GET", "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(q)
                        + "&count=5&language=" + language())
        req.send()
        searchWatchdog.restart()
    }

    // ⚠️ Qt's XMLHttpRequest ignores its timeout property: the request is aborted by hand,
    // and the handler then sees status 0 — the "no network?" note.
    Timer {
        id: searchWatchdog
        interval: 10000
        onTriggered: { if (page.xhr) page.xhr.abort() }
    }

    function choose(lat, lon, name, tz) {
        save({ latitude: String(lat), longitude: String(lon), placeName: name, timezone: tz })
    }

    // "Name, admin1, Country (lat, lon)", skipping the parts a result does not have.
    function describe(r) {
        const where = [r.name, r.admin1, r.country].filter(x => x !== undefined && String(x).length > 0).join(", ")
        return where + " (" + r.latitude + ", " + r.longitude + ")"
    }

    // What each source's terms say, under the forecast settings.
    function terms() {
        switch (page.source) {
        case "met-no":
            return page.i18n("The data is MET Norway's, under CC BY 4.0;\nits terms ask for the attribution line.")
        case "weatherapi":
            return page.i18n("The data is WeatherAPI.com's; the free plan gives three forecast days\nand asks for the attribution line.")
        case "visual-crossing":
            return page.i18n("The data is Visual Crossing's; the free plan is a thousand records a day,\none per forecast day, and its terms ask for the attribution line.")
        default:
            return page.i18n("The data is Open-Meteo's, free for non-commercial use;\nits terms ask for the attribution line.")
        }
    }

    Section { title: page.i18nc("settings section", "Source") }

    FormRow {
        label: page.i18n("Source:")
        SettingCombo {
            key: "source"
            values: page.sourceIds
            model: [page.i18nc("weather source", "Open-Meteo"), page.i18nc("weather source", "MET Norway"),
                    page.i18nc("weather source", "WeatherAPI.com"), page.i18nc("weather source", "Visual Crossing")]
        }
    }
    FormRow {
        label: page.i18n("API key:")
        visible: page.needsKey
        SettingText {
            key: "apiKey"
            Layout.fillWidth: true
            placeholderText: page.i18nc("API key field placeholder", "paste the key here")
        }
    }
    Hint {
        visible: page.needsKey
        text: page.source === "weatherapi"
            ? page.i18nc("where the key comes from", "A free key: weatherapi.com/signup")
            : page.i18nc("where the key comes from", "A free key: visualcrossing.com/sign-up")
    }

    Section { title: page.i18nc("settings section", "Location") }

    FormRow {
        label: page.i18n("Place:")
        TextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: page.i18nc("search field placeholder", "a city, or latitude, longitude")
            onAccepted: page.search()
        }
        Button {
            text: page.i18nc("look the place up", "Search")
            enabled: searchField.text.trim().length > 0
            onClicked: page.search()
        }
    }
    FormRow {
        label: page.i18n("Current:")
        Label {
            id: currentLabel
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: page.latitude.length > 0
                ? (page.placeName.length > 0
                    ? page.i18nc("stored place: name (latitude, longitude)", "%1 (%2, %3)", page.placeName, page.latitude, page.longitude)
                    : page.latitude + ", " + page.longitude)
                : page.i18nc("no place stored", "not set — guessed from the time zone")
        }
    }
    FormRow {
        Button {
            text: page.i18nc("forget the stored place", "Clear")
            enabled: page.latitude.length > 0 || page.placeName.length > 0
            onClicked: page.choose("", "", "", "")
        }
    }
    Hint {
        visible: page.note.length > 0
        text: page.note
    }

    // The geocoder's answers; a click stores one.
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.results.length > 0
        spacing: 0
        Repeater {
            model: page.results
            ItemDelegate {
                required property var modelData
                Layout.fillWidth: true
                text: page.describe(modelData)
                onClicked: {
                    page.choose(modelData.latitude, modelData.longitude, modelData.name, modelData.timezone || "")
                    page.results = []
                }
            }
        }
    }

    Section { title: page.i18nc("settings section", "Forecast") }

    FormRow {
        label: page.i18n("Units:")
        SettingCombo {
            key: "units"
            model: [page.i18nc("units: follow the locale's measurement system", "by locale"), "°C, km/h", "°C, m/s", "°F, mph"]
        }
    }
    FormRow {
        label: page.i18n("Days:")
        SettingSpin { key: "days"; from: 0; to: 7 }
    }
    FormRow {
        label: page.i18n("Attribution:")
        SettingCheck { key: "attribution"; text: page.i18n("show the source's line") }
    }
    Hint { text: page.terms() }
}
