import QtQuick
import plaintop

// The holidays of the shown months, for the Windows host: the same interface as the
// plasmoid's Holidays.qml (active, months, kind, world → days), the data from the
// service's /holidays — the `holidays` package, which also says which day is a day off,
// so HolidayKinds.js' name lists are not needed here. The regions are the setting
// `holidayRegions` ("DE,DE-BY,RU" — the package's ISO codes; empty: the locale's
// country). The world days are the plasmoid's list, carried over as it stands.
Item {
    id: holidays

    property bool active: true
    property var months: []             // [[year, month 1–12], …]
    property int kind: 0                // 0: days off only; 1: every holiday but name days; 2: all
    property bool world: false
    property string regions: ""

    readonly property var days: build(raw, kind, world, months)
    property var raw: ({})              // dateKey → [{title, public}]

    function key(y, m, d) {
        return y + "-" + String(m).padStart(2, "0") + "-" + String(d).padStart(2, "0")
    }

    readonly property var worldDays: [
        { md: "02-21", title: i18nc("a world day", "International Mother Language Day") },
        { md: "03-08", title: i18nc("a world day", "International Women's Day") },
        { md: "04-07", title: i18nc("a world day", "World Health Day") },
        { md: "04-22", title: i18nc("a world day", "International Mother Earth Day") },
        { md: "05-01", title: i18nc("a world day", "International Workers' Day") },
        { md: "06-01", title: i18nc("a world day", "International Children's Day") },
        { md: "06-05", title: i18nc("a world day", "World Environment Day") },
        { md: "09-21", title: i18nc("a world day", "International Day of Peace") },
        { md: "10-05", title: i18nc("a world day", "World Teachers' Day") },
        { md: "10-24", title: i18nc("a world day", "United Nations Day") },
        { md: "12-10", title: i18nc("a world day", "Human Rights Day") }
    ]

    function build(raw, kind, world, months) {
        const out = {}
        for (const k in raw) {
            for (const h of raw[k]) {
                // The package has no name days; "every holiday but name days" is "every holiday".
                if (kind === 0 && h.public !== true)
                    continue
                (out[k] = out[k] || []).push({ title: h.title, public: h.public === true, world: false })
            }
        }
        if (world) {
            for (const ym of months) {
                for (const w of worldDays) {
                    if (Number(w.md.slice(0, 2)) !== ym[1])
                        continue
                    const k = key(ym[0], ym[1], Number(w.md.slice(3)))
                    const list = out[k] = out[k] || []
                    if (!list.some(x => x.title === w.title))
                        list.push({ title: w.title, public: false, world: true })
                }
            }
        }
        return out
    }

    readonly property string regionList: {
        const r = regions.trim()
        if (r.length > 0) return r
        // The locale's country: "ru_RU" → "RU".
        const parts = Qt.locale().name.split("_")
        return parts.length > 1 ? parts[1].toUpperCase() : ""
    }
    readonly property string lang: Qt.locale().name.split("_")[0]

    function fetch() {
        if (!active || months.length === 0) { raw = ({}); return }
        let pending = months.length
        const next = {}
        for (const ym of months) {
            Service.getJson("/holidays?regions=" + encodeURIComponent(regionList) + "&year=" + ym[0]
                            + "&month=" + ym[1] + "&lang=" + encodeURIComponent(lang), function(d) {
                if (d && d.days)
                    for (const k in d.days) next[k] = d.days[k]
                if (--pending === 0)
                    holidays.raw = next
            }, 8000)
        }
    }

    onActiveChanged: fetch()
    onMonthsChanged: fetch()
    onRegionsChanged: fetch()
    Component.onCompleted: fetch()
    // The day may turn and the regions change under a running host: once an hour is enough.
    Timer { interval: 3600000; running: holidays.active; repeat: true; onTriggered: holidays.fetch() }
}
