import QtQuick
import org.kde.plasma.workspace.calendar as PlasmaCalendar
import "HolidayKinds.js" as Kinds

// The holidays of the shown months. They come from Plasma's own calendar plugin
// ("holidaysevents", on KHolidays — 170 regions), the regions chosen in the file the digital
// clock shares (~/.config/plasma_calendar_holiday_regions; none chosen: the locale's own).
// The plugin fills a day grid one month at a time, so there is a Calendar per shown month,
// and it hands over every entry alike: HolidayKinds.js (made by calendar/holidays.py from
// the plans) tells the days off and the name days. The world days are this widget's own
// short list.
Item {
    id: holidays

    property bool active: true
    property var months: []             // [[year, month 1–12], …] — the grid's months
    property int kind: 0                // 0: days off only; 1: every holiday but name days; 2: all
    property bool world: false          // the UN's and UNESCO's days too

    // dateKey → [{title, public, world}], what the view colours and the sticker lists.
    readonly property var days: build(raw, kind, world, months)

    property var raw: ({})              // dateKey → [titles], as the plugin reads them

    readonly property var publicSet: toSet(Kinds.PUBLIC)
    readonly property var namedaySet: toSet(Kinds.NAMEDAY)
    function toSet(list) {
        const out = {}
        for (let i = 0; i < list.length; i++)
            out[list[i]] = true
        return out
    }

    function key(y, m, d) {
        return y + "-" + String(m).padStart(2, "0") + "-" + String(d).padStart(2, "0")
    }

    // The international days, by month and day: the UN's and UNESCO's best known.
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
            for (const title of raw[k]) {
                const pub = publicSet[title] === true
                if (kind === 0 ? !pub : kind === 1 && namedaySet[title] === true)
                    continue
                (out[k] = out[k] || []).push({ title: title, public: pub, world: false })
            }
        }
        if (world) {
            for (const ym of months) {
                for (const w of worldDays) {
                    if (Number(w.md.slice(0, 2)) !== ym[1])
                        continue
                    const k = key(ym[0], ym[1], Number(w.md.slice(3)))
                    const list = out[k] = out[k] || []
                    // A country's own day of the same name wins over the world's.
                    if (!list.some(x => x.title === w.title))
                        list.push({ title: w.title, public: false, world: true })
                }
            }
        }
        return out
    }

    PlasmaCalendar.EventPluginsManager {
        id: plugins
        enabledPlugins: holidays.active ? ["holidaysevents"] : []
    }

    // Reads one month's days out of its grid into `raw`.
    function collect(cal, y, m) {
        const next = Object.assign({}, raw)
        const last = new Date(y, m, 0).getDate()
        for (let d = 1; d <= last; d++) {
            const k = key(y, m, d)
            const events = cal.daysModel.eventsForDate(new Date(y, m - 1, d))
            const titles = []
            for (let i = 0; i < events.length; i++)
                if (titles.indexOf(events[i].title) < 0)
                    titles.push(String(events[i].title))
            if (titles.length > 0)
                next[k] = titles
            else
                delete next[k]
        }
        raw = next
    }

    Instantiator {
        model: holidays.active ? holidays.months : []
        delegate: QtObject {
            id: month
            required property var modelData
            readonly property int y: modelData[0]
            readonly property int m: modelData[1]
            property var cal: PlasmaCalendar.Calendar {
                days: 7
                weeks: 6
                firstDayOfWeek: 1
                today: new Date()
            }
            // The plugin answers asynchronously: read when the agenda changes, and once
            // more a moment after the start in case the signal came first.
            property var watch: Connections {
                target: month.cal.daysModel
                function onAgendaUpdated() { holidays.collect(month.cal, month.y, month.m) }
            }
            property var late: Timer {
                interval: 1500
                running: true
                onTriggered: holidays.collect(month.cal, month.y, month.m)
            }
            Component.onCompleted: {
                cal.daysModel.setPluginsManager(plugins)
                cal.goToYearAndMonth(y, m)
            }
        }
    }

    onActiveChanged: if (!active) raw = ({})
}
