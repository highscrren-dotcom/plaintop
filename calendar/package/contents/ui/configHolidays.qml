import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls
import org.kde.kholidays as KHolidays
import org.kde.i18n.localeData as LocaleData
import org.kde.plasma.private.holidayevents as HolidayEvents

// Holidays: what to mark, and the regions. The regions are Plasma's own list (KHolidays,
// 170 of them) and live in the file the digital clock's calendar uses too — one choice for
// both, saved the moment a box is ticked. None chosen: the locale's own region.
KCM.SimpleKCM {
    id: page

    property alias cfg_holidays: holidaysBox.checked
    property alias cfg_holidayKind: kindBox.currentIndex
    property alias cfg_worldDays: worldBox.checked
    property string cfg_colorHoliday: "#C8A35A"

    HolidayEvents.HolidayRegionsConfig {
        id: regions
    }

    // Every region KHolidays knows, as {code, title, language, search}: the title in the
    // interface's language (the country and its part by ISO 3166, KHolidays' English where
    // ISO has no name), the language the plan names its days in, what a search looks at.
    property var all: []
    readonly property var byCode: {
        const out = {}
        for (const r of all)
            out[r.code] = r
        return out
    }
    readonly property var shown: {
        const q = filter.text.trim().toLowerCase()
        return q ? all.filter(r => r.search.includes(q)) : all
    }

    Instantiator {
        id: source
        model: KHolidays.HolidayRegionsModel {}
        delegate: QtObject {
            required property string region
            required property string name
        }
        onObjectAdded: Qt.callLater(page.collect)
    }

    function collect() {
        const out = []
        for (let i = 0; i < source.count; i++) {
            const o = source.objectAt(i)
            if (!o)
                continue
            const title = titleOf(o.region, o.name)
            const language = languageOf(o.region)
            // Found by any name: ISO's in the interface's language ("Российская Федерация"),
            // KHolidays' English, the country's own ("Россия"), the language, the code.
            // Qt answers a locale it lacks (ru_UZ) with a neighbour (ru_RU) — only its own counts.
            const cc = o.region.slice(0, 2).toUpperCase()
            const own = Qt.locale((o.region.split("_")[1] || "").split(/[@-]/)[0] + "_" + cc)
            out.push({ code: o.region, title: title, language: language,
                       search: [title, o.name, own.name.endsWith("_" + cc) ? own.nativeTerritoryName : "",
                                language, o.region].join(" ").toLowerCase() })
        }
        out.sort((a, b) => a.title.localeCompare(b.title))
        all = out
    }

    // "de-by_de" → "Germany, Bavaria" in the interface's language; "gr_el_nameday" → "Greece —
    // name days".
    function titleOf(code, english) {
        const m = /^([a-z]{2})(?:-([a-z0-9]+))?_/.exec(code)
        const country = m ? LocaleData.Country.fromAlpha2(m[1].toUpperCase()) : null
        let title = english.split(" - ")[0]
        if (country && country.name) {
            title = country.name
            if (m[2]) {
                const part = LocaleData.CountrySubdivision.fromCode((m[1] + "-" + m[2]).toUpperCase())
                title += ", " + (part && part.name ? part.name
                                 : english.split(" - ")[0].split(", ").slice(1).join(", ") || m[2].toUpperCase())
            }
        }
        const kind = code.split("_")[2]
        const kinds = {
            nameday: i18nc("a region's plan of", "name days"),
            islamic: i18nc("a region's plan of", "Islamic holidays"),
            catholic: i18nc("a region's plan of", "Catholic holidays")
        }
        if (kind)
            title += " — " + (kinds[kind] || english.split(" - ").slice(1).join(" - ") || kind)
        return title
    }

    // "sr@latin" → "Српски · latin": the plan's language by its own name.
    function languageOf(code) {
        const tag = code.split("_")[1] || ""
        const base = tag.split("@")[0]
        const variant = tag.split("@")[1]
        const locale = Qt.locale(base.replace("-", "_"))
        let name = locale.name !== "C" ? locale.nativeLanguageName : ""
        name = name ? name.charAt(0).toUpperCase() + name.slice(1) : base
        return variant ? name + " · " + variant : name
    }

    function choose(code, on) {
        if (on)
            regions.addRegion(code)
        else
            regions.removeRegion(code)
        regions.saveConfig()
    }

    Kirigami.FormLayout {
        CheckBox {
            id: holidaysBox
            Kirigami.FormData.label: i18n("Holidays:")
            text: i18n("mark them in the grid and name them in the sticker")
        }

        ComboBox {
            id: kindBox
            Kirigami.FormData.label: i18n("Which:")
            enabled: holidaysBox.checked
            model: [i18nc("which holidays to mark", "days off only"),
                    i18nc("which holidays to mark", "every holiday but name days"),
                    i18nc("which holidays to mark", "every holiday, name days too")]
        }

        CheckBox {
            id: worldBox
            Kirigami.FormData.label: i18n("World days:")
            enabled: holidaysBox.checked
            text: i18n("the UN's and UNESCO's best known international days")
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Other holidays:")
            enabled: holidaysBox.checked
            color: page.cfg_colorHoliday
            onColorChanged: page.cfg_colorHoliday = color.toString()
        }

        Label {
            text: i18n("A day off takes the weekends' colour; other holidays and world days this one.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Regions") }

        // The chosen regions, each with a button to drop it.
        ColumnLayout {
            Kirigami.FormData.label: i18n("Chosen:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            Layout.fillWidth: true
            enabled: holidaysBox.checked
            spacing: 0

            Repeater {
                model: regions.selectedRegions
                delegate: RowLayout {
                    required property string modelData
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: page.byCode[modelData] ? page.byCode[modelData].title : modelData
                    }
                    Label {
                        text: page.byCode[modelData] ? page.byCode[modelData].language : ""
                        opacity: 0.6
                    }
                    ToolButton {
                        icon.name: "edit-delete-remove"
                        display: AbstractButton.IconOnly
                        text: i18nc("@action:button drop a holiday region", "Remove")
                        ToolTip.text: text
                        ToolTip.visible: hovered
                        ToolTip.delay: Kirigami.Units.toolTipDelay
                        onClicked: page.choose(modelData, false)
                    }
                }
            }

            Label {
                visible: regions.selectedRegions.length === 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: i18n("none — your locale's own region. Once you tick one, only the ticked ones count: tick yours too.")
                opacity: 0.7
            }
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18n("Tick as many as you like. The choice is shared with the calendar of Plasma's clock and saved at once.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        Kirigami.SearchField {
            id: filter
            Layout.fillWidth: true
            enabled: holidaysBox.checked
            KeyNavigation.down: list
        }

        // A FormLayout leaves an item its implicit height (Layout.preferredHeight is not
        // asked), and a ListView has none of its own — hence the frame's.
        Frame {
            Layout.fillWidth: true
            implicitHeight: Kirigami.Units.gridUnit * 18
            padding: 1
            enabled: holidaysBox.checked

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                activeFocusOnTab: true
                model: page.shown
                delegate: CheckDelegate {
                    id: row
                    required property var modelData
                    width: ListView.view.width
                    text: modelData.title
                    checked: regions.selectedRegions.includes(modelData.code)
                    // One line a region: the name, then the plan's language in grey.
                    contentItem: RowLayout {
                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: row.text
                        }
                        Label {
                            text: row.modelData.language
                            opacity: 0.6
                            rightPadding: row.indicator.width + row.spacing
                        }
                    }
                    onToggled: {
                        page.choose(modelData.code, checked)
                        checked = Qt.binding(() => regions.selectedRegions.includes(modelData.code))
                    }
                }
                ScrollBar.vertical: ScrollBar {}

                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 4
                    visible: list.count === 0 && page.all.length > 0
                    text: i18n("Nothing found")
                }
            }
        }
    }
}
