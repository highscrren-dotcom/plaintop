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
    property alias cfg_topCount: topField.value
    property alias cfg_netInterface: netField.text
    // ⚠️ StringList в QML — массив; текстовое поле хранит его через запятую.
    property var cfg_mounts: []

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
            id: intervalField
            Kirigami.FormData.label: i18n("Интервал, мс:")
            from: 200
            to: 10000
            stepSize: 100
        }

        SpinBox {
            id: topField
            Kirigami.FormData.label: i18n("Процессов в топе:")
            from: 0
            to: 15
        }

        TextField {
            id: netField
            Kirigami.FormData.label: i18n("Сетевой интерфейс:")
            Layout.fillWidth: true
        }

        TextField {
            id: mountsField
            Kirigami.FormData.label: i18n("Точки монтирования:")
            Layout.fillWidth: true
            text: page.cfg_mounts.join(", ")
            onTextChanged: page.cfg_mounts = text.split(",").map(s => s.trim()).filter(s => s.length > 0)
        }
    }
}
