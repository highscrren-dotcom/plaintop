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
    property alias cfg_columns: columnsField.value
    property alias cfg_player: playerField.text
    property alias cfg_album: albumBox.checked
    property alias cfg_controls: controlsBox.checked

    // Colours are stored as strings, while ColorButton works with a color: converted in place.
    property string cfg_colorFg: "#C8CCD4"
    property string cfg_colorAccent: "#E05561"
    property string cfg_colorDim: "#6B7280"

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

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
            id: columnsField
            Kirigami.FormData.label: i18n("Width, characters:")
            from: 22
            to: 200
        }

        Label {
            text: i18n("The widget is this many characters wide and five lines tall;\na longer title is cut with an ellipsis.")
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
            Kirigami.FormData.label: i18nc("palette: colour of", "Title:")
            color: page.cfg_colorAccent
            onColorChanged: page.cfg_colorAccent = color.toString()
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Secondary:")
            color: page.cfg_colorDim
            onColorChanged: page.cfg_colorDim = color.toString()
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Player") }

        TextField {
            id: playerField
            Kirigami.FormData.label: i18n("Player:")
            Layout.fillWidth: true
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
            text: i18n("show the album line")
        }

        CheckBox {
            id: controlsBox
            Kirigami.FormData.label: i18n("Controls:")
            text: i18n("show the previous, play/pause and next row")
        }
    }
}
