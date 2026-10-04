import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls
import org.kde.kholidays as KHolidays
import org.kde.kitemmodels as KItemModels
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
                    i18nc("which holidays to mark", "every holiday but name days")]
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

        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: regions.selectedRegions.length > 0
                ? i18np("%1 region chosen. The choice is shared with the calendar of Plasma's clock and saved at once.",
                        "%1 regions chosen. The choice is shared with the calendar of Plasma's clock and saved at once.",
                        regions.selectedRegions.length)
                : i18n("None chosen: your locale's own region. The choice is shared with the calendar of Plasma's clock and saved at once.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        Kirigami.SearchField {
            id: filter
            Layout.fillWidth: true
            enabled: holidaysBox.checked
        }

        ListView {
            id: list
            enabled: holidaysBox.checked
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 16
            clip: true
            model: KItemModels.KSortFilterProxyModel {
                sourceModel: KHolidays.HolidayRegionsModel {}
                filterCaseSensitivity: Qt.CaseInsensitive
                filterString: filter.text
                filterRoleName: "name"
            }
            delegate: CheckDelegate {
                required property string region
                required property string name
                width: ListView.view.width
                text: name
                checked: regions.selectedRegions.includes(region)
                onClicked: {
                    if (checked)
                        regions.addRegion(region)
                    else
                        regions.removeRegion(region)
                    regions.saveConfig()
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }
    }
}
