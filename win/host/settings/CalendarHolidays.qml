pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import plaintop

// Holidays: what to mark, and the regions — calendar/package/contents/ui/configHolidays.qml
// with the `holidays` package's regions in place of KHolidays' plans. The list comes from
// the service (/holidays/regions: ISO codes, a country's subdivisions beside it), and the
// choice is the setting `holidayRegions`, "DE,DE-BY" — the host's Holidays.qml reads the
// same string. None chosen: the locale's own region. The "Which" combo keeps its three
// entries though the package has no name days: the third means the second here.
SettingsPage {
    id: page

    readonly property bool on: flag("holidays", true)
    readonly property var chosen: str("holidayRegions", "").split(",").map(s => s.trim()).filter(s => s.length > 0)

    // Every region the service knows, as {code, title, search}: the country, then each of
    // its subdivisions as "Country, XX".
    property var all: []
    property bool loaded: false
    readonly property var byCode: {
        const out = {}
        for (const r of all)
            out[r.code] = r
        return out
    }
    readonly property var shown: {
        const q = filter.text.trim().toLowerCase()
        return q ? all.filter(r => r.search.indexOf(q) >= 0) : all
    }

    function language() {
        const l = Qt.locale().name.split("_")[0].toLowerCase()
        return /^[a-z]{2}$/.test(l) ? l : "en"
    }

    function load() {
        Service.getJson("/holidays/regions?lang=" + language(), function(d) {
            const out = []
            if (Array.isArray(d)) {
                for (let i = 0; i < d.length; i++) {
                    const c = d[i]
                    const code = String(c.code || "")
                    if (code.length === 0)
                        continue
                    const name = String(c.name || code)
                    out.push({ code: code, title: name, search: (name + " " + code).toLowerCase() })
                    const subs = c.subdivisions || []
                    for (let j = 0; j < subs.length; j++) {
                        const sub = code + "-" + String(subs[j])
                        out.push({ code: sub, title: name + ", " + String(subs[j]),
                                   search: (name + " " + sub).toLowerCase() })
                    }
                }
            }
            out.sort((a, b) => a.title.localeCompare(b.title))
            page.all = out
            page.loaded = true
        })
    }
    Component.onCompleted: load()

    function choose(code, on) {
        const list = chosen.slice()
        const i = list.indexOf(code)
        if (on && i < 0)
            list.push(code)
        if (!on && i >= 0)
            list.splice(i, 1)
        set("holidayRegions", list.join(","))
    }

    FormRow {
        label: page.i18n("Holidays:")
        SettingCheck { key: "holidays"; text: page.i18n("mark them in the grid and name them in the sticker") }
    }
    FormRow {
        label: page.i18n("Which:")
        enabled: page.on
        SettingCombo {
            key: "holidayKind"
            model: [page.i18nc("which holidays to mark", "days off only"),
                    page.i18nc("which holidays to mark", "every holiday but name days"),
                    page.i18nc("which holidays to mark", "every holiday, name days too")]
        }
    }
    FormRow {
        label: page.i18n("World days:")
        enabled: page.on
        SettingCheck { key: "worldDays"; text: page.i18n("the UN's and UNESCO's best known international days") }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Other holidays:")
        enabled: page.on
        SettingColor { key: "colorHoliday"; fallback: "#C8A35A" }
    }
    Hint { text: page.i18n("A day off takes the weekends' colour; other holidays and world days this one.") }

    Section { title: page.i18nc("settings section", "Regions") }

    // The chosen regions, each with a button to drop it.
    FormRow {
        label: page.i18n("Chosen:")
        enabled: page.on
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: page.chosen
                RowLayout {
                    required property string modelData
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: page.byCode[modelData] ? page.byCode[modelData].title : modelData
                    }
                    Label {
                        text: modelData
                        opacity: 0.6
                    }
                    ToolButton {
                        text: page.i18nc("@action:button drop a holiday region", "Remove")
                        onClicked: page.choose(modelData, false)
                    }
                }
            }
            Label {
                visible: page.chosen.length === 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: page.i18n("none — your locale's own region. Once you tick one, only the ticked ones count: tick yours too.")
                opacity: 0.7
            }
        }
    }
    Hint {
        text: page.i18nc("Windows: the holiday regions", "Tick as many as you like: a country, or one of its parts for its own days off.\nSaved at once.")
    }
    Hint {
        visible: page.loaded && page.all.length === 0
        text: page.i18nc("Windows: the holiday regions list is empty", "The service lists no regions: the holidays package is not installed where it runs.")
    }

    FormRow {
        label: page.i18nc("the holiday regions' search field", "Search:")
        enabled: page.on
        TextField {
            id: filter
            Layout.fillWidth: true
            placeholderText: page.i18nc("placeholder of the holiday regions' search field", "a country or a code")
        }
    }

    Frame {
        Layout.fillWidth: true
        implicitHeight: 320
        padding: 1
        enabled: page.on

        ListView {
            id: list
            anchors.fill: parent
            clip: true
            model: page.shown
            delegate: CheckDelegate {
                id: row
                required property var modelData
                width: ListView.view.width
                text: modelData.title
                checked: page.chosen.indexOf(modelData.code) >= 0
                // One line a region: the name, then the code in grey.
                contentItem: RowLayout {
                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: row.text
                    }
                    Label {
                        text: row.modelData.code
                        opacity: 0.6
                        rightPadding: row.indicator.width + row.spacing
                    }
                }
                onToggled: page.choose(modelData.code, checked)
            }
            ScrollBar.vertical: ScrollBar {}

            Label {
                anchors.centerIn: parent
                visible: list.count === 0 && page.all.length > 0
                text: page.i18n("Nothing found")
                opacity: 0.7
            }
        }
    }
}
