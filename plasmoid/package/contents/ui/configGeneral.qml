import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls

KCM.SimpleKCM {
    id: page

    property alias cfg_header: headerField.text
    property alias cfg_fontFamily: fontField.text
    property alias cfg_fontSize: sizeField.value
    property alias cfg_updateInterval: intervalField.value
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
            id: headerField
            Kirigami.FormData.label: i18n("Заголовок:")
            Layout.fillWidth: true
        }

        TextField {
            id: fontField
            Kirigami.FormData.label: i18n("Шрифт:")
            Layout.fillWidth: true
        }

        SpinBox {
            id: sizeField
            Kirigami.FormData.label: i18n("Кегль:")
            from: 6
            to: 32
        }

        SpinBox {
            id: padLeftField
            Kirigami.FormData.label: i18n("Отступ слева, px:")
            from: 0
            to: 500
            stepSize: 4
        }

        SpinBox {
            id: padTopField
            Kirigami.FormData.label: i18n("Отступ сверху, px:")
            from: 0
            to: 500
            stepSize: 4
        }

        SpinBox {
            id: widthField
            Kirigami.FormData.label: i18n("Ширина, px:")
            from: 100
            to: 2000
            stepSize: 8
        }

        SpinBox {
            id: heightField
            Kirigami.FormData.label: i18n("Высота, px:")
            from: 100
            to: 2000
            stepSize: 8
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18n("Основной текст:")
            color: page.cfg_colorFg
            onColorChanged: page.cfg_colorFg = color.toString()
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18n("Заголовок:")
            color: page.cfg_colorAccent
            onColorChanged: page.cfg_colorAccent = color.toString()
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18n("Второстепенное:")
            color: page.cfg_colorDim
            onColorChanged: page.cfg_colorDim = color.toString()
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18n("Значения:")
            color: page.cfg_colorValue
            onColorChanged: page.cfg_colorValue = color.toString()
        }

        CheckBox {
            id: clickBox
            Kirigami.FormData.label: i18n("Мышь:")
            text: i18n("пропускать клики на рабочий стол")
        }

        Label {
            text: i18n("Когда клики пропускаются, виджет мышью не берётся.\nПопасть в настройки: режим правки рабочего стола\nили ./install.sh с ключом clicks off")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        SpinBox {
            id: intervalField
            Kirigami.FormData.label: i18n("Интервал, мс:")
            from: 200
            to: 10000
            stepSize: 100
        }

    }
}
