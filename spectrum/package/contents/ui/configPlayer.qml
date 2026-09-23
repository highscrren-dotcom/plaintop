import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls

// The player inside the ring: the player widget's settings page, with one switch on top.
// Same controls and the same wording as player/.../configGeneral.qml, so the two read
// alike; the keys carry the "player" prefix of this widget's schema.
KCM.SimpleKCM {
    id: page

    property alias cfg_playerShow: showBox.checked
    property alias cfg_playerFontFamily: fontField.text
    property alias cfg_playerFontSize: sizeField.value
    property alias cfg_playerColumns: columnsField.value
    property alias cfg_playerFilter: playerField.text
    property alias cfg_playerAlbum: albumBox.checked
    property alias cfg_playerControls: controlsBox.checked

    // Colours are stored as strings, while ColorButton works with a color: converted in place.
    property string cfg_playerColorFg: "#C8CCD4"
    property string cfg_playerColorAccent: "#E05561"
    property string cfg_playerColorDim: "#6B7280"

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        CheckBox {
            id: showBox
            Kirigami.FormData.label: i18nc("the player drawn inside the visualizer", "In the ring:")
            text: i18n("show the player in the centre of the ring")
        }

        Label {
            text: i18n("The track, the position bar and the controls of the player widget,\ndrawn over the free disc inside the bars. On a line they go along\nthe edge the bars reach last. The ring keeps its size.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Text") }

        TextField {
            id: fontField
            Kirigami.FormData.label: i18n("Font:")
            Layout.fillWidth: true
            enabled: showBox.checked
        }

        SpinBox {
            id: sizeField
            Kirigami.FormData.label: i18nc("font size", "Size:")
            enabled: showBox.checked
            from: 6
            to: 32
        }

        SpinBox {
            id: columnsField
            Kirigami.FormData.label: i18n("Width, characters:")
            enabled: showBox.checked
            from: 22
            to: 200
        }

        Label {
            text: i18n("The player is this many characters wide and five lines tall;\na longer title is cut with an ellipsis.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Palette") }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Main text:")
            enabled: showBox.checked
            color: page.cfg_playerColorFg
            onColorChanged: page.cfg_playerColorFg = color.toString()
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Title:")
            enabled: showBox.checked
            color: page.cfg_playerColorAccent
            onColorChanged: page.cfg_playerColorAccent = color.toString()
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Secondary:")
            enabled: showBox.checked
            color: page.cfg_playerColorDim
            onColorChanged: page.cfg_playerColorDim = color.toString()
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Player") }

        TextField {
            id: playerField
            Kirigami.FormData.label: i18n("Player:")
            Layout.fillWidth: true
            enabled: showBox.checked
            placeholderText: i18nc("player field placeholder", "whoever is playing")
        }

        Label {
            text: i18n("Empty: whoever is playing. Otherwise a part of the player's name\nor desktop entry — vlc, spotify, strawberry; when no player matches,\nback to whoever is playing.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        CheckBox {
            id: albumBox
            Kirigami.FormData.label: i18n("Album:")
            enabled: showBox.checked
            text: i18n("show the album line")
        }

        CheckBox {
            id: controlsBox
            Kirigami.FormData.label: i18n("Controls:")
            enabled: showBox.checked
            text: i18n("show the previous, play/pause and next row")
        }

        Label {
            text: i18n("With no player on the bus the centre of the ring stays empty.\nThe controls take the mouse even while the rest passes clicks through.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }
    }
}
