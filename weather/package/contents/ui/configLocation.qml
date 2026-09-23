import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "Sources.js" as Sources

// Which source, where, in what units, how many days. The place is looked up through
// Open-Meteo's geocoder from here whatever the source — the same permission the widget
// itself relies on — and stored as coordinates; two typed numbers skip the lookup.
KCM.SimpleKCM {
    id: page

    // The source's id (Sources.js) and, for the two that need one, the key.
    property string cfg_source: "open-meteo"
    property alias cfg_apiKey: keyField.text
    // Text, not numbers, so "not set" is an empty string rather than 0,0 — the widget
    // then falls back to the place it guessed from the time zone.
    property string cfg_latitude: ""
    property string cfg_longitude: ""
    property string cfg_placeName: ""
    property string cfg_timezone: ""
    property alias cfg_units: unitsBox.currentIndex
    property alias cfg_days: daysField.value
    property alias cfg_attribution: attributionBox.checked

    // The combo's rows, in Sources.js order; the names are shown, the ids stored.
    readonly property var sourceIds: Sources.ids
    readonly property bool needsKey: Sources.get(cfg_source).needsKey

    // The dialog writes cfg_source after the page is built: the combo follows it.
    onCfg_sourceChanged: sourceBox.currentIndex = Math.max(0, sourceIds.indexOf(cfg_source))
    Component.onCompleted: sourceBox.currentIndex = Math.max(0, sourceIds.indexOf(cfg_source))

    property var results: []
    property string note: ""
    property var xhr: null

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
                page.note = i18nc("typed coordinates out of range", "latitude is −90…90, longitude −180…180")
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
        page.note = i18nc("geocoding in progress", "searching…")
        req.onreadystatechange = function() {
            // The dialog may have closed with the request in flight.
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
                page.note = found.length > 0 ? "" : i18nc("geocoding: no match", "nothing found")
            } else {
                page.note = i18nc("geocoding: the request failed", "the lookup failed — no network?")
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
        page.cfg_latitude = String(lat)
        page.cfg_longitude = String(lon)
        page.cfg_placeName = name
        page.cfg_timezone = tz
    }

    // "Name, admin1, Country (lat, lon)", skipping the parts a result does not have.
    function describe(r) {
        const where = [r.name, r.admin1, r.country].filter(x => x !== undefined && String(x).length > 0).join(", ")
        return where + " (" + r.latitude + ", " + r.longitude + ")"
    }

    // What each source's terms say, under the forecast settings.
    function terms() {
        switch (page.cfg_source) {
        case "met-no":
            return i18n("The data is MET Norway's, under CC BY 4.0;\nits terms ask for the attribution line.")
        case "weatherapi":
            return i18n("The data is WeatherAPI.com's; the free plan gives three forecast days\nand asks for the attribution line.")
        case "visual-crossing":
            return i18n("The data is Visual Crossing's; the free plan is a thousand records a day,\none per forecast day, and its terms ask for the attribution line.")
        default:
            return i18n("The data is Open-Meteo's, free for non-commercial use;\nits terms ask for the attribution line.")
        }
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Kirigami.Units.smallSpacing

        Kirigami.FormLayout {
            id: sourceForm
            Layout.fillWidth: true
            twinFormLayouts: [placeForm, forecastForm]

            Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Source") }

            ComboBox {
                id: sourceBox
                Kirigami.FormData.label: i18n("Source:")
                model: [i18nc("weather source", "Open-Meteo"), i18nc("weather source", "MET Norway"),
                        i18nc("weather source", "WeatherAPI.com"), i18nc("weather source", "Visual Crossing")]
                // On a click, not on every index change: the index also follows cfg_source.
                onActivated: function(index) { page.cfg_source = page.sourceIds[index] }
            }

            TextField {
                id: keyField
                Kirigami.FormData.label: i18n("API key:")
                Layout.fillWidth: true
                visible: page.needsKey
                placeholderText: i18nc("API key field placeholder", "paste the key here")
            }

            Label {
                visible: page.needsKey
                text: page.cfg_source === "weatherapi"
                    ? i18nc("where the key comes from", "A free key: weatherapi.com/signup")
                    : i18nc("where the key comes from", "A free key: visualcrossing.com/sign-up")
                opacity: 0.7
                font: Kirigami.Theme.smallFont
            }
        }

        Kirigami.FormLayout {
            id: placeForm
            Layout.fillWidth: true
            twinFormLayouts: [sourceForm, forecastForm]

            Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Location") }

            RowLayout {
                Kirigami.FormData.label: i18n("Place:")
                Layout.fillWidth: true

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: i18nc("search field placeholder", "a city, or latitude, longitude")
                    onAccepted: page.search()
                }

                Button {
                    icon.name: "search"
                    text: i18nc("look the place up", "Search")
                    enabled: searchField.text.trim().length > 0
                    onClicked: page.search()
                }
            }

            Label {
                Kirigami.FormData.label: i18n("Current:")
                text: page.cfg_latitude.length > 0
                    ? (page.cfg_placeName.length > 0
                        ? i18nc("stored place: name (latitude, longitude)", "%1 (%2, %3)", page.cfg_placeName, page.cfg_latitude, page.cfg_longitude)
                        : page.cfg_latitude + ", " + page.cfg_longitude)
                    : i18nc("no place stored", "not set — guessed from the time zone")
            }

            Button {
                icon.name: "edit-clear"
                text: i18nc("forget the stored place", "Clear")
                enabled: page.cfg_latitude.length > 0 || page.cfg_placeName.length > 0
                onClicked: page.choose("", "", "", "")
            }
        }

        Label {
            visible: page.note.length > 0
            text: page.note
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            Layout.leftMargin: Kirigami.Units.largeSpacing
        }

        // The geocoder's answers; a click stores one. Sized by its rows: the page scrolls,
        // the list does not.
        ListView {
            id: list
            visible: page.results.length > 0
            model: page.results
            interactive: false
            Layout.fillWidth: true
            implicitHeight: contentHeight

            delegate: ItemDelegate {
                required property var modelData
                width: list.width
                icon.name: "mark-location"
                text: page.describe(modelData)
                onClicked: {
                    page.choose(modelData.latitude, modelData.longitude, modelData.name, modelData.timezone || "")
                    page.results = []
                }
            }
        }

        Kirigami.FormLayout {
            id: forecastForm
            Layout.fillWidth: true
            twinFormLayouts: [sourceForm, placeForm]

            Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Forecast") }

            ComboBox {
                id: unitsBox
                Kirigami.FormData.label: i18n("Units:")
                model: [i18nc("units: follow the locale's measurement system", "by locale"), "°C, km/h", "°C, m/s", "°F, mph"]
            }

            SpinBox {
                id: daysField
                Kirigami.FormData.label: i18n("Days:")
                from: 0
                to: 7
            }

            CheckBox {
                id: attributionBox
                Kirigami.FormData.label: i18n("Attribution:")
                text: i18n("show the source's line")
            }

            Label {
                text: page.terms()
                opacity: 0.7
                font: Kirigami.Theme.smallFont
            }
        }
    }
}
