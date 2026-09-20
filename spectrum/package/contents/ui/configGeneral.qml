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
    property alias cfg_relayPort: portField.value

    // Цвета хранятся строкой, а ColorButton работает с color — переводим на месте.
    property string cfg_color: "#C8CCD4"
    property string cfg_colorHigh: ""

    readonly property bool ring: layoutBox.currentIndex === 0

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Форма") }

        ComboBox {
            id: layoutBox
            Kirigami.FormData.label: i18n("Раскладка:")
            model: [i18n("Кольцо"), i18n("Линия")]
        }

        SpinBox {
            id: barsField
            Kirigami.FormData.label: i18n("Штрихов:")
            from: 8
            to: 512
            stepSize: 8
        }

        SpinBox {
            id: radiusField
            Kirigami.FormData.label: i18n("Радиус, px:")
            visible: page.ring
            from: 20
            to: 2000
            stepSize: 10
        }

        SpinBox {
            id: spanField
            Kirigami.FormData.label: i18n("Охват, °:")
            visible: page.ring
            from: 30
            to: 360
            stepSize: 5
        }

        SpinBox {
            id: startField
            Kirigami.FormData.label: i18n("Начальный угол, °:")
            visible: page.ring
            from: 0
            to: 359
            stepSize: 5
        }

        SpinBox {
            id: spacingField
            Kirigami.FormData.label: i18n("Зазор между штрихами, px:")
            visible: !page.ring
            from: 0
            to: 60
        }

        SpinBox {
            id: thicknessField
            Kirigami.FormData.label: i18n("Толщина штриха, px:")
            from: 1
            to: 60
        }

        SpinBox {
            id: minLenField
            Kirigami.FormData.label: i18n("Длина в тишине, px:")
            from: 0
            to: 400
            stepSize: 2
        }

        SpinBox {
            id: maxLenField
            Kirigami.FormData.label: i18n("Добавка на максимуме, px:")
            from: 10
            to: 1000
            stepSize: 10
        }

        ComboBox {
            id: growthBox
            Kirigami.FormData.label: i18n("Рост:")
            model: page.ring
                ? [i18n("наружу"), i18n("внутрь"), i18n("в обе стороны")]
                : [i18n("вверх"), i18n("вниз"), i18n("в обе стороны")]
        }

        CheckBox {
            id: mirrorBox
            Kirigami.FormData.label: i18n("Порядок:")
            text: i18n("зеркально (низкие частоты по краям)")
        }

        CheckBox {
            id: reverseBox
            text: i18n("обратный порядок полос")
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Вид") }

        ComboBox {
            id: elementBox
            Kirigami.FormData.label: i18n("Элемент:")
            model: [i18n("Полоска"), i18n("Блоки")]
        }

        SpinBox {
            id: blockSizeField
            Kirigami.FormData.label: i18n("Блок, px:")
            visible: elementBox.currentIndex === 1
            from: 2
            to: 40
        }

        SpinBox {
            id: blockGapField
            Kirigami.FormData.label: i18n("Зазор блоков, px:")
            visible: elementBox.currentIndex === 1
            from: 0
            to: 40
        }

        CheckBox {
            id: roundedBox
            Kirigami.FormData.label: i18n("Концы:")
            text: i18n("скруглять")
        }

        KQuickControls.ColorButton {
            id: colorButton
            Kirigami.FormData.label: i18n("Цвет:")
            color: page.cfg_color
            onColorChanged: page.cfg_color = color.toString()
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Цвет высоких частот:")

            KQuickControls.ColorButton {
                id: colorHighButton
                enabled: highEnabled.checked
                color: page.cfg_colorHigh.length > 0 ? page.cfg_colorHigh : page.cfg_color
                onColorChanged: if (highEnabled.checked) page.cfg_colorHigh = color.toString()
            }

            CheckBox {
                id: highEnabled
                text: i18n("свой")
                checked: page.cfg_colorHigh.length > 0
                onToggled: page.cfg_colorHigh = checked ? colorHighButton.color.toString() : ""
            }
        }

        SpinBox {
            id: opacityField
            Kirigami.FormData.label: i18n("Прозрачность, %:")
            from: 10
            to: 100
            stepSize: 5
        }

        CheckBox {
            id: guideBox
            Kirigami.FormData.label: i18n("Окружность:")
            visible: page.ring
            text: i18n("тонкая направляющая под штрихами")
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Поведение") }

        SpinBox {
            id: rateField
            Kirigami.FormData.label: i18n("Кадров данных в секунду:")
            from: 5
            to: 60
            stepSize: 5
        }

        SpinBox {
            id: smoothField
            Kirigami.FormData.label: i18n("Сглаживание, мс:")
            from: 0
            to: 400
            stepSize: 10
        }

        SpinBox {
            id: portField
            Kirigami.FormData.label: i18n("Порт реле:")
            from: 1024
            to: 65535
            editable: true
        }

        Label {
            Kirigami.FormData.label: i18n("Источник:")
            text: i18n("спектр считает cava в службе plainspectrum-relay;\nчастоты и устройство задаются в ~/.config/plainspectrum/relay.env")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }
    }
}
