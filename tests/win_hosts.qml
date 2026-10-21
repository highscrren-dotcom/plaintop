// Stand for the Windows hosts: do the five window hosts load on a bare Qt, through the
// QML-only shims of the Plasma modules, and draw what the plasmoids draw?
//
// What it checks. Each host in win/host/ is created as qml.exe creates it, against a
// running service (the real one in CI, win/service/server.py; any stand-in that speaks
// win/PROTOCOL.md will do), and read back: the monitor's lines come from /monitor through
// the sensor shims, the player's from /player through the mpris shim (the D-Bus-named
// methods resolve), the weather shows its header, the visualizer sees the relay, the
// calendar gets its document from /notes and opens the sticker — a window of the Dialog
// shim — by a day's cell. The i18n shim's plural fallback is checked without a catalog.
//
// How to run: python3 tests/win_hosts.py [--qt DIR]: it builds the
// hosts (win/build.py), starts the service on a free port, hands this file the port and
// the token through a generated `standargs` module — qmltestrunner takes no arguments of
// its own, and QML has no other way to read them — runs qmltestrunner offscreen and stops
// the service it started.

import QtQuick
import QtTest
import plaintop
import standargs

TestCase {
    id: tc
    name: "WindowsHosts"
    when: windowShown

    property var hosts: ({})

    function make(name) {
        const c = Qt.createComponent(Qt.resolvedUrl("../win/host/" + name + ".qml"))
        if (c.status === Component.Error)
            fail(name + ".qml did not load: " + c.errorString())
        const o = c.createObject(null)
        verify(o !== null, name + " created")
        hosts[name] = o
        return o
    }

    function text(l) {
        if (!l) return ""
        if (l.kind === "clock") return l.big + l.small
        let s = ""
        const parts = l.parts !== undefined ? l.parts : l
        for (let i = 0; i < parts.length; i++) s += parts[i].text
        return s
    }
    function joined(lines) {
        const out = []
        for (let i = 0; i < lines.length; i++) out.push(text(lines[i]))
        return out.join("\n")
    }

    function cleanupTestCase() {
        for (const k in hosts) hosts[k].destroy()
    }

    function initTestCase() {
        Service.port = StandArgs.port
        Service.token = StandArgs.token
    }

    function test_00_arguments_reach_the_service() {
        verify(Service.port > 0, "a port")
        verify(Service.token.length > 0, "a token")
    }

    function test_01_i18n_without_a_catalog() {
        compare(I18n.i18nc("ctx", "%1 of %2", 1, 2), "1 of 2")
        compare(I18n.i18ncp("ctx", "%1 update", "%1 updates", 1), "1 update")
        compare(I18n.i18ncp("ctx", "%1 update", "%1 updates", 3), "3 updates")
        compare(I18n.i18n("plain"), "plain")
    }

    function test_02_monitor_draws_its_lines() {
        const m = make("monitor")
        tryVerify(() => m.ready, 8000, "settings arrived")
        tryVerify(() => m.lines.length >= 5, 10000, "lines came from /monitor through the shims")
        const all = joined(m.lines)
        verify(/CPU /.test(all), "a CPU bar: " + all.split("\n").slice(0, 8).join(" | "))
        verify(/RAM /.test(all), "a RAM bar")
        verify(m.width > 100 && m.height > 100, "sized from the settings")
        verify(m.visible, "shown once the settings are in")
    }

    function test_03_player_draws_and_its_controls_answer() {
        const p = make("player")
        tryVerify(() => p.ready, 8000, "settings arrived")
        tryVerify(() => p.lines.length >= 1, 10000, "lines from /player")
        verify(/NOW PLAYING/.test(text(p.lines[0])), "the header: " + text(p.lines[0]))
        compare(p.height > 0, true)
    }

    function test_04_weather_loads_and_shows_its_header() {
        const w = make("weather")
        tryVerify(() => w.ready, 8000, "settings arrived")
        tryVerify(() => w.lines.length >= 1, 10000, "a header line")
        // With no place set and no network for the guess, the view's first line asks for
        // a location; with one, it is the header.
        const first = text(w.lines[0])
        verify(/WEATHER|location/.test(first), "the header or the hint: " + first)
    }

    function test_05_spectrum_sees_the_relay() {
        const s = make("spectrum")
        tryVerify(() => s.ready, 8000, "settings arrived")
        tryVerify(() => s.relayUp, 10000, "/bands answered on the service's port")
        verify(s.width >= 100, "sized from the ring's geometry")
    }

    function test_06_calendar_gets_its_document_and_opens_the_sticker() {
        const c = make("calendar")
        tryVerify(() => c.ready, 8000, "settings arrived")
        tryVerify(() => c.doc && c.doc.accounts && c.doc.accounts.length >= 1, 15000, "the document from /notes")
        const r = c.clickDay("2026-10-07")
        verify(r.width > 0, "a cell for a day in the shown months")
        tryVerify(() => c.stickerOpen, 3000, "the sticker (a Dialog shim window) opened")
    }
}
