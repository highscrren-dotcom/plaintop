import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_header: headerField.text
    property alias cfg_fontFamily: fontField.text
    property alias cfg_fontSize: sizeField.value
    property alias cfg_updateInterval: intervalField.value
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

        SpinBox {
            id: intervalField
            Kirigami.FormData.label: i18n("Интервал, мс:")
            from: 200
            to: 10000
            stepSize: 100
        }

    }
}
