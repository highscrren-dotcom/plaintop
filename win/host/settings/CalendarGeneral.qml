import QtQuick
import QtQuick.Layouts

// The calendar's General page: calendar/package/contents/ui/configGeneral.qml, row for
// row. The months and the first day are stored as counts and Qt days and shown as combo
// entries (SettingCombo's `values`). The locale hint names Windows' settings instead of
// Plasma's.
SettingsPage {
    id: page

    Section { title: page.i18nc("settings section", "Calendar") }

    FormRow {
        label: page.i18n("Months:")
        SettingCombo {
            key: "months"
            values: [1, 3]
            model: [page.i18nc("how many months are shown", "one — the current"),
                    page.i18nc("how many months are shown", "three — the previous, the current and the next")]
        }
    }
    FormRow {
        label: page.i18n("Week numbers:")
        SettingCheck { key: "weekNumbers"; text: page.i18n("ISO week numbers in front of the rows") }
    }
    FormRow {
        label: page.i18n("Week starts on:")
        SettingCombo {
            key: "firstDay"
            values: [0, 1, 7]
            model: [page.i18nc("first day of the week", "as the locale says"),
                    page.i18nc("first day of the week", "Monday"),
                    page.i18nc("first day of the week", "Sunday")]
        }
    }
    FormRow {
        label: page.i18n("Weekends:")
        SettingCheck { key: "weekendAccent"; text: page.i18n("in their own colour, as on a wall calendar") }
    }
    FormRow {
        label: page.i18n("Other months:")
        SettingCheck { key: "fillDays"; text: page.i18n("fill the empty cells with the neighbouring months' days") }
    }
    Hint {
        text: page.i18nc("Windows: where the calendar's locale is set", "Today is in brackets. The names of the days and months, the first day\nof the week and the weekend come from the locale\n(Settings → Time & language → Language & region).")
    }

    Section { title: page.i18nc("settings section", "Text") }

    FormRow {
        label: page.i18n("Font:")
        SettingText { key: "fontFamily"; Layout.fillWidth: true }
    }
    FormRow {
        label: page.i18nc("font size", "Size:")
        SettingSpin { key: "fontSize"; from: 6; to: 32 }
    }
    FormRow {
        label: page.i18n("Day cell, characters:")
        SettingSpin { key: "cellWidth"; from: 4; to: 8 }
    }
    Hint {
        text: page.i18n("The widget is as wide as seven cells and the week numbers, and as tall as\nthe months shown: eight lines each, with a blank line between them.")
    }

    Section { title: page.i18nc("settings section", "Palette") }

    FormRow {
        label: page.i18nc("palette: colour of", "Main text:")
        SettingColor { key: "colorFg"; fallback: "#C8CCD4" }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Weekends:")
        SettingColor { key: "colorAccent"; fallback: "#E05561" }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Secondary:")
        SettingColor { key: "colorDim"; fallback: "#6B7280" }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Today:")
        SettingColor { key: "colorToday"; fallback: "#8FB6E0" }
    }
}
