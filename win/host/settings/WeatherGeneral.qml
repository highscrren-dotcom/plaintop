import QtQuick
import QtQuick.Layouts

// The weather's General page: weather/package/contents/ui/configGeneral.qml, row for row.
SettingsPage {
    id: page

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
        label: page.i18n("Width, characters:")
        SettingSpin { key: "columns"; from: 10; to: 200 }
    }
    Hint {
        text: page.i18n("The widget is this many characters wide; its height follows the number of\nforecast days and the attribution line. A longer line is cut with an ellipsis.")
    }

    Section { title: page.i18nc("settings section", "Icon") }

    FormRow {
        label: page.i18n("Icon:")
        SettingCombo { key: "icon"; model: [page.i18nc("icon placement", "none"), page.i18nc("icon placement", "on the left")] }
    }
    FormRow {
        label: page.i18n("Icon size, px:")
        SettingSpin { key: "iconSize"; from: 3; to: 5 }
    }
    Hint { text: page.i18n("A picture made of characters in the widget's font, left of the current conditions.") }

    Section { title: page.i18nc("settings section", "Palette") }

    FormRow {
        label: page.i18nc("palette: colour of", "Main text:")
        SettingColor { key: "colorFg"; fallback: "#C8CCD4" }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Temperature:")
        SettingColor { key: "colorAccent"; fallback: "#E05561" }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Secondary:")
        SettingColor { key: "colorDim"; fallback: "#6B7280" }
    }
}
