import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls

KCM.SimpleKCM {
    id: page

    property alias cfg_fontFamily: fontField.text
    property alias cfg_fontSize: sizeField.value
    property alias cfg_cellWidth: cellField.value
    property alias cfg_weekNumbers: weekBox.checked
    property alias cfg_fillDays: fillBox.checked
    property alias cfg_weekendAccent: weekendBox.checked

    // Stored as counts and Qt days, shown as combo indexes: converted in place, as the
    // colours are.
    property int cfg_months: 3
    property int cfg_firstDay: 0

    // Colours are stored as strings, while ColorButton works with a color: converted in place.
    property string cfg_colorFg: "#C8CCD4"
    property string cfg_colorAccent: "#E05561"
    property string cfg_colorDim: "#6B7280"
    property string cfg_colorToday: "#8FB6E0"

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Calendar") }

        ComboBox {
            id: monthsBox
            Kirigami.FormData.label: i18n("Months:")
            model: [i18nc("how many months are shown", "one — the current"),
                    i18nc("how many months are shown", "three — the previous, the current and the next")]
            currentIndex: page.cfg_months >= 3 ? 1 : 0
            onActivated: page.cfg_months = currentIndex === 1 ? 3 : 1
        }

        CheckBox {
            id: weekBox
            Kirigami.FormData.label: i18n("Week numbers:")
            text: i18n("ISO week numbers in front of the rows")
        }

        ComboBox {
            id: firstDayBox
            Kirigami.FormData.label: i18n("Week starts on:")
            model: [i18nc("first day of the week", "as the locale says"),
                    i18nc("first day of the week", "Monday"),
                    i18nc("first day of the week", "Sunday")]
            currentIndex: page.cfg_firstDay === 1 ? 1 : (page.cfg_firstDay === 7 ? 2 : 0)
            onActivated: page.cfg_firstDay = [0, 1, 7][currentIndex]
        }

        CheckBox {
            id: weekendBox
            Kirigami.FormData.label: i18n("Weekends:")
            text: i18n("in their own colour, as on a wall calendar")
        }

        CheckBox {
            id: fillBox
            Kirigami.FormData.label: i18n("Other months:")
            text: i18n("fill the empty cells with the neighbouring months' days")
        }

        Label {
            text: i18n("Today is in brackets. The names of the days and months, the first day\nof the week and the weekend come from the locale\n(System Settings → Language and Region → Formats).")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Text") }

        TextField {
            id: fontField
            Kirigami.FormData.label: i18n("Font:")
            Layout.fillWidth: true
        }

        SpinBox {
            id: sizeField
            Kirigami.FormData.label: i18nc("font size", "Size:")
            from: 6
            to: 32
        }

        SpinBox {
            id: cellField
            Kirigami.FormData.label: i18n("Day cell, characters:")
            from: 4
            to: 8
        }

        Label {
            text: i18n("The widget is as wide as seven cells and the week numbers, and as tall as\nthe months shown: eight lines each, with a blank line between them.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Palette") }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Main text:")
            color: page.cfg_colorFg
            onColorChanged: page.cfg_colorFg = color.toString()
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Weekends:")
            color: page.cfg_colorAccent
            onColorChanged: page.cfg_colorAccent = color.toString()
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Secondary:")
            color: page.cfg_colorDim
            onColorChanged: page.cfg_colorDim = color.toString()
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Today:")
            color: page.cfg_colorToday
            onColorChanged: page.cfg_colorToday = color.toString()
        }
    }
}
