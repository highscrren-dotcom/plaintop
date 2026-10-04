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
    property alias cfg_barWidth: barWidthField.value
    property alias cfg_barFill: barFillField.text
    property alias cfg_barEmpty: barEmptyField.text
    property alias cfg_separatorChar: sepCharField.text
    property alias cfg_separatorWidth: sepWidthField.value
    property alias cfg_sparkGlyphs: sparkField.text
    property alias cfg_secondColumn: columnField.value


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
            Kirigami.FormData.label: i18nc("palette: colour of", "Header and clock:")
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
            text: i18n("While clicks go through, both mouse buttons land on the desktop.\nThe widget takes the mouse only in the desktop's edit mode:\nthat is where its settings are, or ./install.sh with the clicks off switch")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Lines") }

        SpinBox {
            id: barWidthField
            Kirigami.FormData.label: i18n("Bar width, characters:")
            from: 4
            to: 60
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Bar characters:")

            TextField {
                id: barFillField
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                maximumLength: 2
                placeholderText: "/"
            }

            TextField {
                id: barEmptyField
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                maximumLength: 2
                placeholderText: i18nc("placeholder: the empty part of a bar is a space", "space")
            }
        }

        Label {
            text: i18n("The filled and the empty part of a bar. Empty fields mean the slash and a space.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Separator:")

            TextField {
                id: sepCharField
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                maximumLength: 2
                placeholderText: "-"
            }

            SpinBox {
                id: sepWidthField
                from: 1
                to: 200
            }
        }

        TextField {
            id: sparkField
            Kirigami.FormData.label: i18n("Sparkline glyphs:")
            Layout.fillWidth: true
            placeholderText: "▁▂▃▄▅▆▇█"
        }

        Label {
            text: i18n("From lowest to highest, for the “History” parameter of the bar blocks.
Any run of characters works, say “ .:-=+*#”.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        SpinBox {
            id: columnField
            Kirigami.FormData.label: i18n("Second column at, px:")
            from: 0
            to: 2000
            stepSize: 8
        }

        Label {
            text: i18n("Where the second column starts; 0 is half the width. A block goes
there by its “Column” field on the Blocks page.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Updates") }

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
