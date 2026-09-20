import QtQuick

import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Общее")
        icon: "preferences-desktop-font"
        source: "configGeneral.qml"
    }

    ConfigCategory {
        name: i18n("Блоки")
        icon: "view-list-details"
        source: "configBlocks.qml"
    }
}
