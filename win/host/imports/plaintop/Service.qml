pragma Singleton
import QtQuick

// The one door to the local service (win/service/, win/PROTOCOL.md). Every shim and every
// host reaches 127.0.0.1 through this object, so the port and the write token live in one
// place: the host reads them from its command line (the service starts the hosts and hands
// both over as arguments — `-- --port 8788 --token …`) and sets them here once.
//
// ⚠️ Qt's XMLHttpRequest ignores its timeout property (docs/GOTCHAS.md), so every request
// carries its own watchdog: a service that stopped answering must not leave a poll hanging
// forever with its caller waiting for a callback that never comes.
QtObject {
    id: service

    property int port: 8788
    property string token: ""
    readonly property string base: "http://127.0.0.1:" + port

    // Seen answering at least once, and the last request's outcome: the hosts show "no
    // data: the service does not answer" from these rather than from a guess.
    property bool up: false
    property int failures: 0

    // Reads the arguments the service passed: everything after "--".
    function readArguments() {
        const args = Qt.application.arguments
        for (let i = 0; i < args.length; i++) {
            if (args[i] === "--port" && i + 1 < args.length) port = Number(args[i + 1]) || port
            if (args[i] === "--token" && i + 1 < args.length) token = String(args[i + 1])
        }
    }

    // argument(name, fallback): a host's own option from the same command line.
    function argument(name, fallback) {
        const args = Qt.application.arguments
        for (let i = 0; i < args.length; i++)
            if (args[i] === name && i + 1 < args.length) return String(args[i + 1])
        return fallback
    }

    Component.onCompleted: readArguments()

    // request(method, path, body, cb, timeoutMs): cb(status, text) once, status 0 on a
    // network failure or the watchdog. The body is sent as JSON.
    function request(method, path, body, cb, timeoutMs) {
        const xhr = new XMLHttpRequest()
        let done = false
        const finish = function(status, text) {
            if (done) return
            done = true
            watchdog.stop(xhr)
            if (status === 0 || status >= 500) {
                service.failures++
            } else {
                service.up = true
                service.failures = 0
            }
            if (cb) cb(status, text)
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            finish(xhr.status, xhr.responseText || "")
        }
        xhr.open(method, base + path)
        if (method !== "GET") {
            xhr.setRequestHeader("Content-Type", "application/json; charset=utf-8")
            if (token.length > 0) xhr.setRequestHeader("X-Plaintop-Token", token)
        }
        watchdog.arm(xhr, timeoutMs || 5000, function() { xhr.abort(); finish(0, "") })
        xhr.send(body === undefined || body === null ? null : JSON.stringify(body))
    }

    function get(path, cb, timeoutMs) { request("GET", path, null, cb, timeoutMs) }
    function post(path, body, cb, timeoutMs) { request("POST", path, body || {}, cb, timeoutMs) }

    // getJson(path, cb): cb(obj) with the parsed answer, or cb(null) on anything else.
    function getJson(path, cb, timeoutMs) {
        get(path, function(status, text) {
            if (status !== 200) { cb(null, status); return }
            try { cb(JSON.parse(text), status) } catch (e) { cb(null, status) }
        }, timeoutMs)
    }
    function postJson(path, body, cb, timeoutMs) {
        post(path, body, function(status, text) {
            if (status !== 200) { if (cb) cb(null, status); return }
            try { if (cb) cb(JSON.parse(text), status) } catch (e) { if (cb) cb(null, status) }
        }, timeoutMs)
    }

    // One Timer for all watchdogs: a request is a few milliseconds, so a 250 ms sweep is
    // enough, and a Timer per request would be created and destroyed thirty times a second
    // by the visualizer's polling alone.
    readonly property QtObject watchdog: QtObject {
        property var pending: []
        property Timer sweep: Timer {
            interval: 250
            repeat: true
            running: service.watchdog.pending.length > 0
            onTriggered: service.watchdog.check()
        }
        function arm(xhr, ms, onTimeout) {
            pending.push({ xhr: xhr, due: Date.now() + ms, fire: onTimeout })
            pendingChanged()
        }
        function stop(xhr) {
            for (let i = 0; i < pending.length; i++)
                if (pending[i].xhr === xhr) { pending.splice(i, 1); pendingChanged(); return }
        }
        function check() {
            const now = Date.now()
            const late = pending.filter(p => p.due <= now)
            pending = pending.filter(p => p.due > now)
            for (const p of late) p.fire()
        }
    }
}
