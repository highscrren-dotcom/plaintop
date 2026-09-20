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
    }
}
