import QtQuick
import QtQuick.Layouts

// The player inside the ring: spectrum/package/contents/ui/configPlayer.qml — the player
// widget's page with one switch on top, the keys under this widget's "player" prefix.
SettingsPage {
    id: page

    readonly property bool shown: flag("playerShow", false)

    FormRow {
        label: page.i18nc("the player drawn inside the visualizer", "In the ring:")
        SettingCheck { key: "playerShow"; text: page.i18n("show the player in the centre of the ring") }
    }
    Hint {
        text: page.i18n("The track, the position bar and the controls of the player widget,\ndrawn over the free disc inside the bars. On a line they go along\nthe edge the bars reach last. The ring keeps its size.")
    }

    Section { title: page.i18nc("settings section", "Text") }

    FormRow {
        label: page.i18n("Font:")
        enabled: page.shown
        SettingText { key: "playerFontFamily"; Layout.fillWidth: true }
    }
    FormRow {
        label: page.i18nc("font size", "Size:")
        enabled: page.shown
        SettingSpin { key: "playerFontSize"; from: 6; to: 32 }
    }
    FormRow {
        label: page.i18n("Width, characters:")
        enabled: page.shown
        SettingSpin { key: "playerColumns"; from: 22; to: 200 }
    }
    Hint {
        text: page.i18n("The player is this many characters wide and five lines tall;\na longer title is cut with an ellipsis.")
    }

    Section { title: page.i18nc("settings section", "Palette") }

    FormRow {
        label: page.i18nc("palette: colour of", "Main text:")
        enabled: page.shown
        SettingColor { key: "playerColorFg"; fallback: "#C8CCD4" }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Title:")
        enabled: page.shown
        SettingColor { key: "playerColorAccent"; fallback: "#E05561" }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Secondary:")
        enabled: page.shown
        SettingColor { key: "playerColorDim"; fallback: "#6B7280" }
    }

    Section { title: page.i18nc("settings section", "Player") }

    FormRow {
        label: page.i18n("Player:")
        enabled: page.shown
        SettingText {
            key: "playerFilter"
            Layout.fillWidth: true
            placeholderText: page.i18nc("player field placeholder", "whoever is playing")
        }
    }
    Hint {
        text: page.i18n("Empty: whoever is playing. Otherwise a part of the player's name\nor desktop entry — vlc, spotify, strawberry; when no player matches,\nback to whoever is playing.")
    }
    FormRow {
        label: page.i18n("Album:")
        enabled: page.shown
        SettingCheck { key: "playerAlbum"; text: page.i18n("show the album line") }
    }
    FormRow {
        label: page.i18n("Controls:")
        enabled: page.shown
        SettingCheck { key: "playerControls"; text: page.i18n("show the previous, play/pause and next row") }
    }
    Hint {
        text: page.i18n("With no player on the bus the centre of the ring stays empty.\nThe controls take the mouse even while the rest passes clicks through.")
    }
}
