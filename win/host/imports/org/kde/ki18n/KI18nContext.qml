import QtQuick
import plaintop

// ki18n's context object, as the shared MonitorData has it: `tr.i18nc(…)` through a
// domain of its own. Here there is one catalog per host process, loaded by the launcher
// (`qml -translation …`), so the domain is kept but not consulted — see I18n.js.
QtObject {
    property string translationDomain: ""

    function i18n(text) { return I18n.i18n.apply(null, arguments) }
    function i18nc(context, text) { return I18n.i18nc.apply(null, arguments) }
    function i18np(singular, plural, n) { return I18n.i18np.apply(null, arguments) }
    function i18ncp(context, singular, plural, n) { return I18n.i18ncp.apply(null, arguments) }
}
