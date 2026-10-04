import QtQuick

import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18nc("settings page", "General")
        icon: "office-calendar"
        source: "configGeneral.qml"
    }

    ConfigCategory {
        name: i18nc("settings page", "Notes")
        icon: "view-pim-notes"
        source: "configNotes.qml"
    }

    ConfigCategory {
        name: i18nc("settings page", "Holidays")
        icon: "view-calendar-holiday"
        source: "configHolidays.qml"
    }

    ConfigCategory {
        name: i18nc("settings page", "Accounts")
        icon: "preferences-system-users"
        source: "configAccounts.qml"
    }

    ConfigCategory {
        name: i18nc("settings page", "Mouse")
        icon: "input-mouse"
        source: "configMouse.qml"
    }
}
