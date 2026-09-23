import QtQuick

import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18nc("settings page", "Ring")
        icon: "audio-volume-high"
        source: "configGeneral.qml"
    }

    ConfigCategory {
        name: i18nc("settings page", "Player")
        icon: "media-playback-start"
        source: "configPlayer.qml"
    }
}
