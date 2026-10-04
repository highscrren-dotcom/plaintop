pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import plaintop

// The settings window of one widget on Windows. On Plasma each widget's pages are the
// package's config*.qml under the shell's dialog, with KConfig behind them; here the same
// pages — the same fields, labels, ranges and hints, so the same catalog strings — are
// plain QtQuick.Controls under a TabBar, and the settings belong to the service: the
// window reads /settings/<widget> and every control writes its key back the moment it
// changes (text fields a few hundred milliseconds after the last keystroke), so there is
// no Apply — the running widget picks the change up within a second (win/PROTOCOL.md).
//
// Started by the service (win/service/ui.py):
//   qml -I win/host/imports [-translation x.qm] win/host/settings.qml -- --port P --token T --widget monitor
Window {
    id: win

    property string widget: Service.argument("--widget", "monitor")
    // The settings, as /settings/<widget> gives them: every key of the plasmoid's main.xml
    // plus the window keys.
    property var cfg: ({})
    property int cfgStamp: -1
    readonly property bool ready: cfgStamp >= 0

    title: "plaintop — " + widget
    width: 760
    height: 700
    minimumWidth: 480
    minimumHeight: 320
    visible: true
    color: palette.window

    // ── i18n ──────────────────────────────────────────────────────────────────
    function i18n(text) { return I18n.i18n.apply(null, arguments) }
    function i18nc(context, text) { return I18n.i18nc.apply(null, arguments) }
    function i18np(singular, plural, n) { return I18n.i18np.apply(null, arguments) }
    function i18ncp(context, singular, plural, n) { return I18n.i18ncp.apply(null, arguments) }

    // ── the pages ─────────────────────────────────────────────────────────────
    // The titles are the plasmoids' config.qml ones, so the catalogs already have them.
    readonly property var pages: ({
        monitor: [
            { title: i18nc("settings page", "General"), source: "settings/MonitorGeneral.qml" },
            { title: i18nc("settings page", "Blocks"), source: "settings/MonitorBlocks.qml" }
        ],
        spectrum: [
            { title: i18nc("settings page", "Ring"), source: "settings/SpectrumGeneral.qml" },
            { title: i18nc("settings page", "Player"), source: "settings/SpectrumPlayer.qml" }
        ],
        player: [
            { title: i18nc("settings page", "General"), source: "settings/PlayerGeneral.qml" },
            { title: i18nc("settings page", "Mouse"), source: "settings/MousePage.qml", controls: true }
        ],
        weather: [
            { title: i18nc("settings page", "General"), source: "settings/WeatherGeneral.qml" },
            { title: i18nc("settings page", "Location"), source: "settings/WeatherLocation.qml" },
            { title: i18nc("settings page", "Mouse"), source: "settings/MousePage.qml" }
        ],
        calendar: [
            { title: i18nc("settings page", "General"), source: "settings/CalendarGeneral.qml" },
            { title: i18nc("settings page", "Notes"), source: "settings/CalendarNotes.qml" },
            { title: i18nc("settings page", "Holidays"), source: "settings/CalendarHolidays.qml" },
            { title: i18nc("settings page", "Accounts"), source: "settings/CalendarAccounts.qml" },
            { title: i18nc("settings page", "Mouse"), source: "settings/MousePage.qml" }
        ]
    })
    readonly property var pageList: pages[widget] || []
    readonly property int pageCount: pageList.length

    // For the stand (tests/win_settings.qml): the loaded page and the loader's state.
    function pageItem(i) {
        const l = pageLoaders.itemAt(i)
        return l ? l.item : null
    }
    function pageStatus(i) {
        const l = pageLoaders.itemAt(i)
        return l ? l.status : Loader.Null
    }
    function showPage(i) { tabs.currentIndex = i }

    // ── settings ──────────────────────────────────────────────────────────────
    function pollSettings() {
        const since = cfgStamp
        Service.get("/settings/" + widget + "?since=" + since, function(status, text) {
            if (status !== 200) return
            try {
                const d = JSON.parse(text)
                if (!d || d.values === undefined) return
                // Two polls may be in flight (the timer's and a write's), and the older
                // answer must not turn a control back for a second: one that is behind
                // what the window already has is dropped — unless it is behind what it
                // asked with too, which is a service that started over.
                const stamp = Number(d.stamp) || 0
                if (stamp > since && stamp < win.cfgStamp) return
                win.cfg = d.values
                win.cfgStamp = Number(d.stamp) || 0
            } catch (e) {
                console.warn("plaintop: /settings did not parse:", e)
            }
        }, 3000)
    }

    // save({key: value}): to the service, which writes the file; the poll brings it back —
    // at once, so a control that depends on another's value follows without a wait.
    //
    // One write at a time. Qt sends consecutive requests over parallel connections, so
    // three quick clicks on a SpinBox's arrow could reach the service in any order and the
    // last one lose (seen on the stand: five Blocks-page writes applied scrambled). What
    // arrives while a write is in flight is merged into the next one, a later value for
    // the same key replacing the earlier.
    property var pendingWrite: ({})
    property bool writing: false
    function save(values) {
        for (const k in values) pendingWrite[k] = values[k]
        if (!writing) nextWrite()
    }
    function nextWrite() {
        const keys = Object.keys(pendingWrite)
        if (keys.length === 0) { writing = false; return }
        writing = true
        const body = pendingWrite
        pendingWrite = ({})
        Service.postJson("/settings/" + widget, body, function(d) {
            if (d) win.pollSettings()
            win.nextWrite()
        })
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: win.pollSettings()
    }

    // Under the pages: the window's own colour is not part of its content item, so a
    // grab of the content (the stand's PNGs) would come out without a background.
    Rectangle {
        anchors.fill: parent
        color: win.palette.window
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TabBar {
            id: tabs
            Layout.fillWidth: true
            Repeater {
                model: win.pageList
                TabButton {
                    required property var modelData
                    text: modelData.title
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            Repeater {
                id: pageLoaders
                model: win.pageList
                Loader {
                    id: loader
                    required property var modelData
                    // The window goes in as an initial property, so a page that reads the
                    // settings in its Component.onCompleted already has them.
                    Component.onCompleted: setSource(Qt.resolvedUrl(modelData.source),
                                                     modelData.controls === true ? { win: win, controls: true } : { win: win })
                    onStatusChanged: if (status === Loader.Error) console.warn("plaintop: the settings page did not load:", modelData.source)
                }
            }
        }

        // A service that stopped answering: said once, under the pages, rather than by a
        // control that quietly keeps what nobody saved.
        Label {
            Layout.fillWidth: true
            Layout.margins: 8
            visible: Service.failures >= 3
            wrapMode: Text.Wrap
            color: "#B03030"
            text: win.i18nc("the settings window: the service does not answer", "The plaintop service does not answer — nothing changed here is saved.")
        }
    }
}
