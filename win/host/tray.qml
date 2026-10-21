import QtQuick
import Qt.labs.platform as Platform
import plaintop

// The tray icon: the one place to reach the widgets while their clicks pass through —
// which widgets are shown, their settings, quit. It speaks to the service's /ui, which
// starts and stops the host processes (win/service/ui.py). A native icon through
// Qt.labs.platform; no window of its own.
QtObject {
    id: tray

    readonly property var widgets: ["monitor", "spectrum", "player", "weather", "calendar"]
    readonly property var titles: ({
        monitor: I18n.i18nc("tray: the widget", "Monitor"),
        spectrum: I18n.i18nc("tray: the widget", "Visualizer"),
        player: I18n.i18nc("tray: the widget", "Player"),
        weather: I18n.i18nc("tray: the widget", "Weather"),
        calendar: I18n.i18nc("tray: the widget", "Calendar")
    })
    property var running: ({})
    property var shown: ({})
    // The palettes the service lists (/themes) and the one the settings carry now.
    property var themes: []
    property string theme: ""

    function refresh() {
        Service.getJson("/ui", function(d) {
            if (d && d.running) tray.running = d.running
        })
        Service.getJson("/themes", function(d) {
            if (!d || !d.themes) return
            tray.theme = String(d.current || "")
            // Only on change: rebuilding the submenu while it is open would close it.
            const names = d.themes.map(t => t.name).join("\n")
            if (names !== tray.themes.map(t => t.name).join("\n")) tray.themes = d.themes
        })
        for (const w of widgets) {
            Service.getJson("/settings/" + w, function(d) {
                if (!d || !d.values) return
                const s = Object.assign({}, tray.shown)
                s[w] = d.values.shown !== false
                tray.shown = s
            })
        }
    }

    property Timer poll: Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: tray.refresh()
    }

    property Platform.SystemTrayIcon icon: Platform.SystemTrayIcon {
        visible: true
        icon.source: Qt.resolvedUrl("plaintop.svg")
        tooltip: "plaintop"
        onActivated: reason => { tray.refresh(); menu.open() }

        menu: Platform.Menu {
            id: menu

            Platform.MenuItem {
                text: I18n.i18nc("tray menu", "Widgets")
                enabled: false
            }
            Platform.MenuItem {
                text: tray.titles.monitor; checkable: true; checked: tray.shown.monitor === true
                onTriggered: Service.postJson("/ui", { show: "monitor", on: checked }, tray.refresh)
            }
            Platform.MenuItem {
                text: tray.titles.spectrum; checkable: true; checked: tray.shown.spectrum === true
                onTriggered: Service.postJson("/ui", { show: "spectrum", on: checked }, tray.refresh)
            }
            Platform.MenuItem {
                text: tray.titles.player; checkable: true; checked: tray.shown.player === true
                onTriggered: Service.postJson("/ui", { show: "player", on: checked }, tray.refresh)
            }
            Platform.MenuItem {
                text: tray.titles.weather; checkable: true; checked: tray.shown.weather === true
                onTriggered: Service.postJson("/ui", { show: "weather", on: checked }, tray.refresh)
            }
            Platform.MenuItem {
                text: tray.titles.calendar; checkable: true; checked: tray.shown.calendar === true
                onTriggered: Service.postJson("/ui", { show: "calendar", on: checked }, tray.refresh)
            }
            Platform.MenuSeparator {}
            Platform.Menu {
                title: I18n.i18nc("tray menu", "Settings")
                Platform.MenuItem { text: tray.titles.monitor; onTriggered: Service.postJson("/ui", { settings: "monitor" }) }
                Platform.MenuItem { text: tray.titles.spectrum; onTriggered: Service.postJson("/ui", { settings: "spectrum" }) }
                Platform.MenuItem { text: tray.titles.player; onTriggered: Service.postJson("/ui", { settings: "player" }) }
                Platform.MenuItem { text: tray.titles.weather; onTriggered: Service.postJson("/ui", { settings: "weather" }) }
                Platform.MenuItem { text: tray.titles.calendar; onTriggered: Service.postJson("/ui", { settings: "calendar" }) }
            }
            Platform.Menu {
                id: themeMenu
                title: I18n.i18nc("tray menu", "Theme")
                Instantiator {
                    model: tray.themes
                    delegate: Platform.MenuItem {
                        required property var modelData
                        text: modelData.title + (modelData.error ? "  ✗" : "")
                        enabled: !modelData.error
                        checkable: true
                        checked: tray.theme === modelData.name
                        onTriggered: Service.postJson("/themes", { name: modelData.name }, tray.refresh)
                    }
                    onObjectAdded: (index, object) => themeMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => themeMenu.removeItem(object)
                }
            }
            Platform.MenuSeparator {}
            Platform.MenuItem {
                text: I18n.i18nc("tray menu", "Quit plaintop")
                onTriggered: Service.postJson("/ui", { quit: true })
            }
        }
    }
}
