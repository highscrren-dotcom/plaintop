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
    property alias cfg_updateInterval: intervalField.value
    property alias cfg_processInterval: processField.value
    property alias cfg_clickThrough: clickBox.checked
    property string cfg_colorFg: "#C8CCD4"
    property string cfg_colorAccent: "#E05561"
    property string cfg_colorDim: "#6B7280"
    property string cfg_colorValue: "#8FB6E0"
    property alias cfg_widgetWidth: widthField.value
    property alias cfg_padLeft: padLeftField.value
    property alias cfg_padTop: padTopField.value
    property alias cfg_widgetHeight: heightField.value


    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

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
            id: padLeftField
            Kirigami.FormData.label: i18n("Left padding, px:")
            from: 0
            to: 500
            stepSize: 4
        }

        SpinBox {
            id: padTopField
            Kirigami.FormData.label: i18n("Top padding, px:")
            from: 0
            to: 500
            stepSize: 4
        }

        SpinBox {
            id: widthField
            Kirigami.FormData.label: i18n("Width, px:")
            from: 100
            to: 2000
            stepSize: 8
        }

        SpinBox {
            id: heightField
            Kirigami.FormData.label: i18n("Height, px:")
            from: 100
            to: 2000
            stepSize: 8
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Main text:")
            color: page.cfg_colorFg
            onColorChanged: page.cfg_colorFg = color.toString()
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Header:")
            color: page.cfg_colorAccent
            onColorChanged: page.cfg_colorAccent = color.toString()
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Secondary:")
            color: page.cfg_colorDim
            onColorChanged: page.cfg_colorDim = color.toString()
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Values:")
            color: page.cfg_colorValue
            onColorChanged: page.cfg_colorValue = color.toString()
        }

        CheckBox {
            id: clickBox
            Kirigami.FormData.label: i18n("Mouse:")
            text: i18n("let clicks through to the desktop")
        }

        Label {
            text: i18n("While clicks go through, the widget cannot be grabbed with the mouse.\nTo reach the settings: the desktop's edit mode\nor ./install.sh with the clicks off switch")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        SpinBox {
            id: intervalField
            Kirigami.FormData.label: i18n("Interval, ms:")
            from: 200
            to: 10000
            stepSize: 100
        }

        SpinBox {
            id: processField
            Kirigami.FormData.label: i18n("Top processes, every … s:")
            from: 2
            to: 60
        }

        Label {
            text: i18n("The process list is the most expensive thing collected: every 2 s\nabout 3% of a core, every 10 s about 1.3%")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

    }
}
