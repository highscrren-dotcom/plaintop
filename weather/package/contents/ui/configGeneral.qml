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
    // The combo's index is the stored value: 0 none, 1 on the left.
    property alias cfg_icon: iconBox.currentIndex
    property alias cfg_iconSize: iconSizeField.value

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
            from: 10
            to: 200
        }

        Label {
            text: i18n("The widget is this many characters wide; its height follows the number of\nforecast days and the attribution line. A longer line is cut with an ellipsis.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Icon") }

        ComboBox {
            id: iconBox
            Kirigami.FormData.label: i18n("Icon:")
            model: [i18nc("icon placement", "none"), i18nc("icon placement", "on the left")]
        }

        SpinBox {
            id: iconSizeField
            Kirigami.FormData.label: i18n("Icon size, px:")
            from: 3
            to: 5
        }

        Label {
            text: i18n("A picture made of characters in the widget's font, left of the current conditions.")
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
            Kirigami.FormData.label: i18nc("palette: colour of", "Temperature:")
            color: page.cfg_colorAccent
            onColorChanged: page.cfg_colorAccent = color.toString()
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Secondary:")
            color: page.cfg_colorDim
            onColorChanged: page.cfg_colorDim = color.toString()
        }
    }
}
