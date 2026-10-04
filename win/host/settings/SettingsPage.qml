import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import plaintop

// One page of the settings window: a scrolling column of rows over the settings the window
// polls from the service. The controls (SettingSpin, SettingText, …) find this page by
// walking up their parents (Form.js), read their key from `cfg` and write it back through
// set(), which posts to the service — so a page is a plain list of rows, as the plasmoid's
// FormLayout is, and no page carries an Apply button: the service writes the ini and the
// running widget picks it up within a second (win/PROTOCOL.md).
Flickable {
    id: page

    // What the controls look for when they walk up the parents.
    readonly property bool settingsPage: true
    // The settings window (settings.qml): the settings, and the way to write them.
    property var win: null
    readonly property var cfg: win ? win.cfg : ({})
    // key → control, for the stand (tests/win_settings.qml).
    property var registry: ({})
    default property alias content: column.data

    function num(key, fallback) {
        const v = cfg[key]
        return (v === undefined || v === null) ? fallback : v
    }
    function str(key, fallback) {
        const v = cfg[key]
        return (v === undefined || v === null) ? (fallback === undefined ? "" : fallback) : String(v)
    }
    function flag(key, fallback) {
        const v = cfg[key]
        return (v === undefined || v === null) ? (fallback === true) : v === true
    }
    function set(key, value) {
        const values = {}
        values[key] = value
        save(values)
    }
    function save(values) {
        if (win) win.save(values)
    }
    function register(key, item) { registry[key] = item }
    function control(key) { return registry[key] !== undefined ? registry[key] : null }

    // ki18n's functions for a bare i18n() in the pages — the same ones the window hosts
    // carry (WidgetWindow.qml), over Qt's translator and the converted po/ catalogs.
    function i18n(text) { return I18n.i18n.apply(null, arguments) }
    function i18nc(context, text) { return I18n.i18nc.apply(null, arguments) }
    function i18np(singular, plural, n) { return I18n.i18np.apply(null, arguments) }
    function i18ncp(context, singular, plural, n) { return I18n.i18ncp.apply(null, arguments) }

    contentWidth: width
    contentHeight: column.implicitHeight + 2 * column.y
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    ColumnLayout {
        id: column
        x: 16
        y: 12
        // The right margin leaves room for the scroll bar.
        width: page.width - x - 28
        spacing: 8
    }
}
