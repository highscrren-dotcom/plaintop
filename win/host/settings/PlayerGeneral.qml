import QtQuick
import QtQuick.Layouts

// The player's General page: player/package/contents/ui/configGeneral.qml, row for row.
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
        SettingSpin { key: "columns"; from: 22; to: 200 }
    }
    Hint {
        text: page.i18n("The widget is this many characters wide and five lines tall;\na longer title is cut with an ellipsis.")
    }

    Section { title: page.i18nc("settings section", "Palette") }

    FormRow {
        label: page.i18nc("palette: colour of", "Main text:")
        SettingColor { key: "colorFg"; fallback: "#C8CCD4" }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Title:")
        SettingColor { key: "colorAccent"; fallback: "#E05561" }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Secondary:")
        SettingColor { key: "colorDim"; fallback: "#6B7280" }
    }

    Section { title: page.i18nc("settings section", "Player") }

    FormRow {
        label: page.i18n("Player:")
        SettingText {
            key: "player"
            Layout.fillWidth: true
            placeholderText: page.i18nc("player field placeholder", "whoever is playing")
        }
    }
    Hint {
        text: page.i18n("Empty: whoever is playing. Otherwise a part of the player's name\nor desktop entry — vlc, spotify, strawberry; when no player matches,\nback to whoever is playing.")
    }
    FormRow {
        label: page.i18n("Album:")
        SettingCheck { key: "album"; text: page.i18n("show the album line") }
    }
    FormRow {
        label: page.i18n("Controls:")
        SettingCheck { key: "controls"; text: page.i18n("show the previous, play/pause and next row") }
    }
}
