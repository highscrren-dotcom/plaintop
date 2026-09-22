import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls

KCM.SimpleKCM {
    id: page

    property alias cfg_layout: layoutBox.currentIndex
    property alias cfg_bars: barsField.value
    property alias cfg_radius: radiusField.value
    property alias cfg_span: spanField.value
    property alias cfg_startAngle: startField.value
    property alias cfg_spacing: spacingField.value
    property alias cfg_thickness: thicknessField.value
    property alias cfg_minLength: minLenField.value
    property alias cfg_maxLength: maxLenField.value
    property alias cfg_growth: growthBox.currentIndex
    property alias cfg_mirror: mirrorBox.checked
    property alias cfg_reverse: reverseBox.checked
    property alias cfg_element: elementBox.currentIndex
    property alias cfg_blockSize: blockSizeField.value
    property alias cfg_blockGap: blockGapField.value
    property alias cfg_rounded: roundedBox.checked
    property alias cfg_opacityPercent: opacityField.value
    property alias cfg_guide: guideBox.checked
    property alias cfg_dataRate: rateField.value
    property alias cfg_smoothMs: smoothField.value
    property alias cfg_hideWhenQuiet: quietBox.checked
    property alias cfg_quietThreshold: quietLevelField.value
    property alias cfg_quietDelayMs: quietDelayField.value
    property alias cfg_fadeMs: fadeField.value
    property alias cfg_idleRate: idleRateField.value
    property alias cfg_relayPort: portField.value
    property alias cfg_clickThrough: clickBox.checked

    // Colours are stored as strings, while ColorButton works with a color: converted in place.
    property string cfg_color: "#C8CCD4"
    property string cfg_colorHigh: ""

    readonly property bool ring: layoutBox.currentIndex === 0

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Shape") }

        ComboBox {
            id: layoutBox
            Kirigami.FormData.label: i18n("Layout:")
            model: [i18nc("layout", "Ring"), i18nc("layout", "Line")]
        }

        SpinBox {
            id: barsField
            Kirigami.FormData.label: i18n("Bars:")
            from: 8
            to: 512
            stepSize: 8
        }

        SpinBox {
            id: radiusField
            Kirigami.FormData.label: i18n("Radius, px:")
            visible: page.ring
            from: 20
            to: 2000
            stepSize: 10
        }

        SpinBox {
            id: spanField
            Kirigami.FormData.label: i18n("Span, °:")
            visible: page.ring
            from: 30
            to: 360
            stepSize: 5
        }

        SpinBox {
            id: startField
            Kirigami.FormData.label: i18n("Start angle, °:")
            visible: page.ring
            from: 0
            to: 359
            stepSize: 5
        }

        SpinBox {
            id: spacingField
            Kirigami.FormData.label: i18n("Gap between bars, px:")
            visible: !page.ring
            from: 0
            to: 60
        }

        SpinBox {
            id: thicknessField
            Kirigami.FormData.label: i18n("Bar thickness, px:")
            from: 1
            to: 60
        }

        SpinBox {
            id: minLenField
            Kirigami.FormData.label: i18n("Length at silence, px:")
            from: 0
            to: 400
            stepSize: 2
        }

        SpinBox {
            id: maxLenField
            Kirigami.FormData.label: i18n("Extra length at maximum, px:")
            from: 10
            to: 1000
            stepSize: 10
        }

        ComboBox {
            id: growthBox
            Kirigami.FormData.label: i18n("Growth:")
            model: page.ring
                ? [i18nc("growth", "outward"), i18nc("growth", "inward"), i18nc("growth", "both ways")]
                : [i18nc("growth", "up"), i18nc("growth", "down"), i18nc("growth", "both ways")]
        }

        CheckBox {
            id: mirrorBox
            Kirigami.FormData.label: i18n("Order:")
            text: i18n("mirrored (low frequencies at the edges)")
        }

        CheckBox {
            id: reverseBox
            text: i18n("reverse band order")
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Appearance") }

        ComboBox {
            id: elementBox
            Kirigami.FormData.label: i18n("Element:")
            model: [i18nc("element shape", "Bar"), i18nc("element shape", "Blocks")]
        }

        SpinBox {
            id: blockSizeField
            Kirigami.FormData.label: i18n("Block, px:")
            visible: elementBox.currentIndex === 1
            from: 2
            to: 40
        }

        SpinBox {
            id: blockGapField
            Kirigami.FormData.label: i18n("Block gap, px:")
            visible: elementBox.currentIndex === 1
            from: 0
            to: 40
        }

        CheckBox {
            id: roundedBox
            Kirigami.FormData.label: i18n("Ends:")
            text: i18nc("bar ends", "rounded")
        }

        KQuickControls.ColorButton {
            id: colorButton
            Kirigami.FormData.label: i18n("Colour:")
            color: page.cfg_color
            onColorChanged: page.cfg_color = color.toString()
        }

        RowLayout {
            Kirigami.FormData.label: i18n("High-frequency colour:")

            KQuickControls.ColorButton {
                id: colorHighButton
                enabled: highEnabled.checked
                color: page.cfg_colorHigh.length > 0 ? page.cfg_colorHigh : page.cfg_color
                onColorChanged: if (highEnabled.checked) page.cfg_colorHigh = color.toString()
            }

            CheckBox {
                id: highEnabled
                text: i18nc("high-frequency colour", "custom")
                checked: page.cfg_colorHigh.length > 0
                onToggled: page.cfg_colorHigh = checked ? colorHighButton.color.toString() : ""
            }
        }

        SpinBox {
            id: opacityField
            Kirigami.FormData.label: i18n("Opacity, %:")
            from: 10
            to: 100
            stepSize: 5
        }

        CheckBox {
            id: guideBox
            Kirigami.FormData.label: i18n("Circle:")
            visible: page.ring
            text: i18n("a thin guide under the bars")
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Behaviour") }

        SpinBox {
            id: rateField
            Kirigami.FormData.label: i18n("Data frames per second:")
            from: 5
            to: 60
            stepSize: 5
        }

        SpinBox {
            id: smoothField
            Kirigami.FormData.label: i18n("Smoothing, ms:")
            from: 0
            to: 400
            stepSize: 10
        }

        CheckBox {
            id: clickBox
            Kirigami.FormData.label: i18n("Mouse:")
            text: i18n("let clicks through to the desktop")
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Silence") }

        CheckBox {
            id: quietBox
            Kirigami.FormData.label: i18n("In silence:")
            text: i18n("dissolve the ring")
        }

        SpinBox {
            id: quietLevelField
            Kirigami.FormData.label: i18n("Silence threshold, %:")
            enabled: quietBox.checked
            from: 0
            to: 50
        }

        SpinBox {
            id: quietDelayField
            Kirigami.FormData.label: i18n("Wait before vanishing, ms:")
            enabled: quietBox.checked
            from: 100
            to: 10000
            stepSize: 100
        }

        SpinBox {
            id: fadeField
            Kirigami.FormData.label: i18n("Fade in and out, ms:")
            enabled: quietBox.checked
            from: 0
            to: 3000
            stepSize: 50
        }

        SpinBox {
            id: idleRateField
            Kirigami.FormData.label: i18n("Polls per second in silence:")
            enabled: quietBox.checked
            from: 1
            to: 30
        }

        Label {
            text: i18n("The bars grow out of the ring itself, so a “length at silence” of 0\nmakes them appear out of literally nothing.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        SpinBox {
            id: portField
            Kirigami.FormData.label: i18n("Relay port:")
            from: 1024
            to: 65535
            editable: true
        }

        Label {
            Kirigami.FormData.label: i18n("Source:")
            text: i18n("the spectrum is computed by cava in the plainspectrum-relay service;\nthe frequencies and the device are set in ~/.config/plainspectrum/relay.env")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }
    }
}
