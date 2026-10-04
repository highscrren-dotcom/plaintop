// Stand for the Windows settings window (win/host/settings.qml): do the pages of all five
// widgets load on a bare Qt, do the controls carry the plasmoid pages' fields, and does a
// change reach the service and come back?
//
// What it checks. Each widget's window is created as qml.exe creates it, against a
// service that speaks win/PROTOCOL.md (the real one, or a stand-in — the holidays and notes
// answers are the only ones with content the stand relies on: Germany with Bavaria among
// the regions, and the account commands answered by notes.py or an echo of it). Every page must
// load (Loader.status) and lay out its rows; then one control of each kind is driven as a
// user would — a SpinBox by the keyboard, a CheckBox and a list row by the mouse, a text
// field by typing — and the value is read back from GET /settings/<widget>; a value posted
// from outside reaches the control through the window's poll. The Blocks page's list
// operations and its JSON validation, the Holidays page's regions, the Accounts page's
// round trip through /notes (the password inside the base64 JSON) and the Location page's
// typed coordinates are checked through the pages' own functions. Six pages are grabbed to
// PNG files in the temp location (TMPDIR), to be looked at.
//
// How to run: python3 tests/win_hosts.py [--qt DIR] runs this stand after the hosts' one,
// against the service it started, with the port and the token in the generated `standargs`
// module (qmltestrunner takes no arguments of its own).

import QtQuick
import QtTest
import QtCore
import plaintop
import standargs

TestCase {
    id: tc
    name: "WindowsSettings"
    when: windowShown

    readonly property int port: StandArgs.port
    readonly property string token: StandArgs.token
    property var windows: ({})

    function initTestCase() {
        Service.port = port
        Service.token = token
    }

    function cleanupTestCase() {
        for (const k in windows) windows[k].destroy()
    }

    function make(widget) {
        if (windows[widget]) return windows[widget]
        const c = Qt.createComponent(Qt.resolvedUrl("../win/host/settings.qml"))
        if (c.status === Component.Error)
            fail("settings.qml did not load: " + c.errorString())
        const w = c.createObject(null, { widget: widget })
        verify(w !== null, "a window for " + widget)
        windows[widget] = w
        tryVerify(() => w.ready, 8000, widget + ": settings arrived")
        for (let i = 0; i < w.pageCount; i++) {
            tryVerify(() => w.pageStatus(i) === Loader.Ready || w.pageStatus(i) === Loader.Error, 8000,
                      widget + " page " + i + " settled")
            if (w.pageStatus(i) === Loader.Error) {
                // The loader keeps the error to itself; compiling the page gives the text.
                const pc = Qt.createComponent(Qt.resolvedUrl("../win/host/" + w.pageList[i].source))
                fail(widget + " page " + w.pageList[i].source + " did not load: " + pc.errorString())
            }
        }
        return w
    }

    // The page shown and its window made the active one: QtTest's key events go to the
    // focus window, which is whichever window was activated last.
    function page(widget, i) {
        const w = make(widget)
        w.showPage(i)
        w.requestActivate()
        tryVerify(() => w.active, 3000, widget + "'s window is active")
        return w.pageItem(i)
    }

    // The stored settings of a widget, read back from the service.
    property var fetched: null
    function fetch(widget) {
        fetched = null
        Service.getJson("/settings/" + widget, function(d) { tc.fetched = d ? d.values : ({}) })
        tryVerify(() => tc.fetched !== null, 3000, "GET /settings/" + widget)
        return fetched
    }
    function stored(widget, key) { return fetch(widget)[key] }
    function waitStored(widget, key, value) {
        tryVerify(() => String(tc.stored(widget, key)) === String(value), 3000,
                  widget + "." + key + " = " + value + " in the service (is " + tc.stored(widget, key) + ")")
    }
    property bool posted: false
    function post(widget, values) {
        posted = false
        Service.postJson("/settings/" + widget, values, function(d) { tc.posted = d !== null })
        tryVerify(() => tc.posted, 3000, "POST /settings/" + widget)
    }
    // A known state for the keys a test touches, seen by the window: the service keeps
    // what an earlier run left, and nothing here assumes a fresh one.
    function reset(widget, values) {
        post(widget, values)
        const w = make(widget)
        for (const k in values)
            tryVerify(() => String(w.cfg[k]) === String(values[k]), 3000, widget + "." + k + " reset to " + values[k])
    }

    function test_00_arguments_reach_the_service() {
        verify(Service.port > 0, "a port")
        verify(Service.token.length > 0, "a token")
    }

    function test_01_every_page_of_every_widget_loads() {
        const expected = { monitor: 2, spectrum: 2, player: 2, weather: 3, calendar: 5 }
        for (const widget in expected) {
            const w = make(widget)
            compare(w.pageCount, expected[widget], widget + ": the number of pages")
            compare(w.title, "plaintop — " + widget)
            for (let i = 0; i < w.pageCount; i++) {
                const p = w.pageItem(i)
                verify(p !== null, widget + " page " + i + " exists")
                verify(p.settingsPage === true, widget + " page " + i + " is a SettingsPage")
                verify(p.contentHeight > 60, widget + " page " + i + " laid out rows: " + p.contentHeight)
            }
        }
        // The form pages mirror the plasmoid pages' keys, one control each.
        const keys = page("monitor", 0).registry
        for (const k of ["fontFamily", "fontSize", "padLeft", "colorFg", "clickThrough", "actions", "terminal",
                         "barFill", "barEmpty", "separatorWidth", "sparkGlyphs", "secondColumn", "updateInterval", "processInterval"])
            verify(keys[k] !== undefined, "monitor General has " + k)
        const spectrum = page("spectrum", 0).registry
        for (const k of ["layout", "bars", "radius", "growth", "mirror", "monoSpectrum", "element", "color", "colorHigh",
                         "hideWhenQuiet", "quietThreshold", "relayPort", "clickThrough"])
            verify(spectrum[k] !== undefined, "spectrum Ring has " + k)
        const notes = page("calendar", 1).registry
        for (const k of ["notes", "noteAccount", "upcoming", "syncMinutes", "reminders", "remindLead", "remindHour",
                         "remindEvents", "snoozeMinutes", "remindMissed", "remindSystem", "frame", "stickerColumns",
                         "stickerAnimation", "paperOpacity", "colorNote", "colorPaper"])
            verify(notes[k] !== undefined, "calendar Notes has " + k)
    }

    function test_02_a_spinbox_writes_and_follows() {
        const spin = page("monitor", 0).control("fontSize")
        const was = stored("monitor", "fontSize")
        compare(spin.value, was, "the box shows the stored size")
        spin.forceActiveFocus()
        keyClick(Qt.Key_Up)
        waitStored("monitor", "fontSize", was + 1)
        // A change made elsewhere reaches the box through the poll.
        post("monitor", { fontSize: was })
        tryCompare(spin, "value", was, 3000)
    }

    function test_03_a_checkbox_writes_and_follows() {
        reset("player", { clickThrough: false })
        const p = page("player", 1)
        const box = p.control("clickThrough")
        compare(box.checked, false, "clicks do not pass by default")
        mouseClick(box)
        waitStored("player", "clickThrough", true)
        post("player", { clickThrough: false })
        tryCompare(box, "checked", false, 3000)
    }

    function test_04_a_text_field_writes_after_the_debounce() {
        reset("weather", { fontFamily: "monospace", fontSize: 10 })
        const field = page("weather", 0).control("fontFamily")
        tryCompare(field, "text", "monospace", 3000)
        field.forceActiveFocus()
        field.selectAll()
        for (const ch of "Consolas") keyClick(ch)
        compare(field.text, "Consolas")
        // Nothing is written on the keystroke itself: the write waits for the debounce…
        verify(field.pending, "the debounce is running")
        // …and lands 400 ms later.
        waitStored("weather", "fontFamily", "Consolas")
        verify(!field.pending)
        // A poll does not reset the field while it is being edited.
        post("weather", { fontSize: 11 })
        wait(1500)
        compare(field.text, "Consolas", "the field keeps its text under the poll")
    }

    function test_05_a_colour_is_written_only_when_it_is_one() {
        const colour = page("monitor", 0).control("colorFg")
        const was = stored("monitor", "colorFg")
        colour.text = "#12"
        colour.flush()
        wait(300)
        compare(stored("monitor", "colorFg"), was, "a half-typed colour is not written")
        verify(!colour.valid)
        colour.text = "#123456"
        colour.flush()
        waitStored("monitor", "colorFg", "#123456")
        verify(colour.valid)
        post("monitor", { colorFg: was })
        tryCompare(colour, "text", was, 3000)
    }

    function test_06_a_combo_stores_its_values_not_its_index() {
        reset("calendar", { months: 3, firstDay: 0 })
        const months = page("calendar", 0).control("months")
        compare(stored("calendar", "months"), 3)
        compare(months.currentIndex, 1, "three months is the second entry")
        months.forceActiveFocus()
        keyClick(Qt.Key_Up)
        waitStored("calendar", "months", 1)
        post("calendar", { months: 3 })
        tryCompare(months, "currentIndex", 1, 3000)
        const firstDay = page("calendar", 0).control("firstDay")
        firstDay.forceActiveFocus()
        keyClick(Qt.Key_Down)
        waitStored("calendar", "firstDay", 1)
        keyClick(Qt.Key_Down)
        waitStored("calendar", "firstDay", 7)
    }

    function test_07_the_blocks_page() {
        reset("monitor", { blocksJson: "" })
        const p = page("monitor", 1)
        verify(p.blocks.length >= 20, "the default layout from description.js: " + p.blocks.length)
        const first = p.blocks[0].id
        const second = p.blocks[1].id
        p.selected = 0
        p.move(0, 1)
        compare(p.selected, 1)
        tryVerify(() => {
            const raw = tc.stored("monitor", "blocksJson")
            if (!raw) return false
            const list = JSON.parse(raw)
            return list[0].id === second && list[1].id === first
        }, 3000, "the moved layout reached the service")
        // The JSON view follows the list, and the validation names the block.
        verify(p.applyJson !== undefined)
        p.applyJson("[{\"id\": \"x\", \"type\": \"nothing\"}]")
        verify(p.jsonError.indexOf("nothing") >= 0, "an unknown type is named: " + p.jsonError)
        p.applyJson("[{\"id\": \"a\", \"type\": \"clock\"}, {\"id\": \"a\", \"type\": \"date\"}]")
        verify(p.jsonError.indexOf("twice") >= 0, "a duplicate id is named: " + p.jsonError)
        p.applyJson("not json")
        verify(p.jsonError.indexOf("JSON") >= 0, "garbage is named: " + p.jsonError)
        p.applyJson("{}")
        verify(p.jsonError.indexOf("list") >= 0, "a non-list is named: " + p.jsonError)
        // Duplicate, remove, add from the vocabulary.
        const n = p.blocks.length
        p.duplicateBlock(1)
        compare(p.blocks.length, n + 1)
        verify(p.blocks[2].id !== p.blocks[1].id, "a fresh id: " + p.blocks[2].id)
        p.removeBlock(2)
        compare(p.blocks.length, n)
        p.addBlock("clock")
        compare(p.blocks.length, n + 1)
        compare(p.blocks[p.selected].type, "clock")
        verify(p.params.length > 0, "the clock's parameters from the vocabulary")
        // Reset: the setting is emptied and the list is the packaged layout again.
        p.reset()
        waitStored("monitor", "blocksJson", "")
        compare(p.blocks[0].id, first)
        // An edit from elsewhere reloads the list.
        post("monitor", { blocksJson: JSON.stringify([{ id: "only", type: "clock", enabled: true, params: {} }]) })
        tryVerify(() => p.blocks.length === 1 && p.blocks[0].id === "only", 3000, "the list followed the service")
        post("monitor", { blocksJson: "" })
        tryVerify(() => p.blocks.length === n, 3000, "and back to the default")
    }

    // Five writes in a row land in order: the window sends one at a time.
    function test_07b_quick_writes_keep_their_order() {
        const p = page("monitor", 1)
        p.selected = 0
        for (let i = 0; i < 5; i++) p.move(i, i + 1)
        compare(p.selected, 5)
        const expected = p.blocks.map(b => b.id).join(",")
        tryVerify(() => {
            const raw = tc.stored("monitor", "blocksJson")
            return raw && JSON.parse(raw).map(b => b.id).join(",") === expected
        }, 5000, "the last of five quick writes is what the service holds")
        const spin = page("monitor", 0).control("padLeft")
        const was = stored("monitor", "padLeft")
        spin.forceActiveFocus()
        for (let i = 0; i < 4; i++) keyClick(Qt.Key_Up)
        waitStored("monitor", "padLeft", was + 4 * spin.stepSize)
        post("monitor", { blocksJson: "", padLeft: was })
        tryCompare(spin, "value", was, 3000)
    }

    function test_08_the_holidays_page_lists_regions_and_writes_the_codes() {
        reset("calendar", { holidayRegions: "" })
        const p = page("calendar", 2)
        tryVerify(() => p.loaded, 5000, "/holidays/regions answered")
        verify(p.all.length >= 2, "regions: " + p.all.length)
        verify(p.byCode["DE"] !== undefined && p.byCode["DE-BY"] !== undefined, "a country and its subdivision")
        compare(p.chosen.length, 0)
        p.choose("DE", true)
        waitStored("calendar", "holidayRegions", "DE")
        p.choose("DE-BY", true)
        waitStored("calendar", "holidayRegions", "DE,DE-BY")
        tryCompare(p, "chosen", ["DE", "DE-BY"], 3000)
        p.choose("DE", false)
        waitStored("calendar", "holidayRegions", "DE-BY")
        // The filter narrows the list; the "Which" combo keeps its three entries.
        compare(p.control("holidayKind").count, 3)
        post("calendar", { holidayRegions: "" })
        tryCompare(p, "chosen", [], 3000)
    }

    function test_09_the_accounts_page_round_trip_through_notes() {
        const p = page("calendar", 3)
        tryVerify(() => p.accounts !== undefined, 3000)
        p.pick(-1)
        p.accId = "yandex"
        p.accName = "Яндекс"
        p.server = "https://caldav.yandex.ru/"
        p.login = "me"
        p.password = "s3cret"
        p.saveAccount()
        tryCompare(p, "status", "Saved.", 5000)
        verify(p.accounts.length === 1 && p.accounts[0].id === "yandex", "saved through /notes")
        verify(p.accounts[0].has_password === true, "the password reached the script inside the JSON")
        verify(p.accounts[0].password === undefined, "and is not listed back")
        p.checkAccount()
        // Against the real service `check` asks caldav.yandex.ru, which a stand without
        // network or a password cannot reach: the script's answer is an error line then.
        // A stand-in lists one calendar. Either way the script answered.
        tryVerify(() => p.status !== "Asking the server…" && p.status.length > 0, 30000, "check answered: " + p.status)
        if (p.calendars.length === 1)
            verify(p.status.indexOf("1 calendar") >= 0, "the status names it: " + p.status)
        // The Notes page lists the account to write to, and keeps the stored choice when
        // the list arrives (a new model would otherwise reset the combo to "local").
        const notes = page("calendar", 1)
        post("calendar", { noteAccount: "yandex" })
        notes.loadAccounts()
        tryVerify(() => notes.accountIds.length === 2, 5000, "the account reached the Notes page")
        tryCompare(notes.control("noteAccount"), "currentIndex", 1, 3000)
        post("calendar", { noteAccount: "local" })
        tryCompare(notes.control("noteAccount"), "currentIndex", 0, 3000)
        p.removeAccount()
        tryVerify(() => p.accounts.length === 0, 5000, "removed: " + p.status)
        compare(p.status, "Removed.")
        // The Notes page's account list came from the same call.
        verify(page("calendar", 1).accountIds.indexOf("local") === 0)
    }

    function test_10_the_location_page_takes_typed_coordinates() {
        reset("weather", { source: "open-meteo", latitude: "", longitude: "", placeName: "" })
        const p = page("weather", 1)
        p.searchText = "52.52, 13.41"
        p.search()
        waitStored("weather", "latitude", "52.52")
        waitStored("weather", "longitude", "13.41")
        waitStored("weather", "placeName", "52.52, 13.41")
        tryVerify(() => p.latitude === "52.52", 3000)
        p.searchText = "95, 10"
        p.search()
        verify(p.note.length > 0, "out of range is said: " + p.note)
        // The source combo stores the id and shows the key field for the keyed ones.
        const source = p.control("source")
        compare(source.currentIndex, 0)
        source.forceActiveFocus()
        keyClick(Qt.Key_Down)
        waitStored("weather", "source", "met-no")
        keyClick(Qt.Key_Down)
        waitStored("weather", "source", "weatherapi")
        tryCompare(p, "needsKey", true, 3000)
        tryCompare(p.control("apiKey"), "visible", true, 3000)
        post("weather", { source: "open-meteo", latitude: "", longitude: "", placeName: "" })
        tryCompare(source, "currentIndex", 0, 3000)
    }

    function test_11_the_ring_page_hides_the_rows_of_the_other_layout() {
        reset("spectrum", { layout: 0 })
        const p = page("spectrum", 0)
        const radius = p.control("radius")
        verify(p.ring, "the ring by default")
        verify(radius.visible, "the radius row is shown")
        // The growth combo's entries follow the layout; its index must survive the swap.
        const growth = p.control("growth")
        post("spectrum", { growth: 2 })
        tryCompare(growth, "currentIndex", 2, 3000)
        post("spectrum", { layout: 1 })
        tryCompare(radius, "visible", false, 3000)
        tryCompare(p.control("spacing"), "visible", true, 3000)
        compare(growth.currentIndex, 2, "the growth entry after the model changed")
        post("spectrum", { layout: 0, growth: 0 })
        tryCompare(radius, "visible", true, 3000)
        tryCompare(growth, "currentIndex", 0, 3000)
    }

    property int grabbed: 0
    function grab(widget, i, name) {
        const w = make(widget)
        w.showPage(i)
        wait(200)
        // A file URL on Windows is file:///C:/…: the drive letter follows the third slash.
        const path = StandardPaths.writableLocation(StandardPaths.TempLocation).toString()
            .replace(/^file:\/\/\/([A-Za-z]:)/, "$1").replace(/^file:\/\//, "")
                     + "/plaintop-settings-" + name + ".png"
        const before = grabbed
        w.contentItem.grabToImage(function(result) {
            if (result.saveToFile(path)) {
                console.info("stand: grabbed " + path)
                tc.grabbed++
            }
        })
        tryVerify(() => tc.grabbed === before + 1, 5000, "grabbed " + name)
    }

    function test_12_pages_grabbed_to_png() {
        grab("monitor", 0, "monitor-general")
        grab("calendar", 1, "calendar-notes")
        grab("monitor", 1, "monitor-blocks")
        grab("calendar", 2, "calendar-holidays")
        grab("calendar", 3, "calendar-accounts")
        grab("weather", 1, "weather-location")
    }
}
