import QtQuick

import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18nc("settings page", "General")
        icon: "preferences-desktop-font"
        source: "configGeneral.qml"
    }

    ConfigCategory {
        name: i18nc("settings page", "Blocks")
        icon: "view-list-details"
        source: "configBlocks.qml"
    }
}
