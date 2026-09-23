import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_clickThrough: clickBox.checked

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        CheckBox {
            id: clickBox
            Kirigami.FormData.label: i18n("Mouse:")
            text: i18n("let clicks through to the desktop")
        }

        Label {
            text: i18n("While clicks go through, both mouse buttons land on the desktop.\nThe widget takes the mouse only in the desktop's edit mode:\nthat is where its settings are, or ./install.sh with the clicks off switch.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }
    }
}
