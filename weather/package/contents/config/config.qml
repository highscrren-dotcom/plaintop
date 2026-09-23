import QtQuick

import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18nc("settings page", "General")
        icon: "preferences-desktop-font"
        source: "configGeneral.qml"
    }

    ConfigCategory {
        name: i18nc("settings page", "Location")
        icon: "find-location"
        source: "configLocation.qml"
    }

    ConfigCategory {
        name: i18nc("settings page", "Mouse")
        icon: "input-mouse"
        source: "configMouse.qml"
    }
}
