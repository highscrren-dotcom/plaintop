import QtQuick

// The Mouse page of the player, the weather and the calendar: the plasmoids' one switch,
// with a hint written for Windows. On Plasma the way back from click-through is the
// desktop's edit mode or ./install.sh; here it is the tray icon and the widget's own menu
// (WidgetWindow.qml), and a window that passes clicks passes all of them — the player's
// controls included, which the plasmoid keeps clickable with a containmentMask.
SettingsPage {
    id: page

    // The player's page says what becomes of its controls.
    property bool controls: false

    FormRow {
        label: page.i18n("Mouse:")
        SettingCheck { key: "clickThrough"; text: page.i18n("let clicks through to the desktop") }
    }

    Hint {
        text: page.controls
            ? page.i18nc("Windows: the player's mouse hint", "While clicks go through, both mouse buttons land on the desktop, the controls' too.\nThe way back is the tray icon's menu, or the widget's own menu: the right button\non it while clicks are not passing — the controls work then as well.")
            : page.i18nc("Windows: the mouse hint", "While clicks go through, both mouse buttons land on the desktop.\nThe way back is the tray icon's menu, or the widget's own menu:\nthe right button on it while clicks are not passing.")
    }
}
