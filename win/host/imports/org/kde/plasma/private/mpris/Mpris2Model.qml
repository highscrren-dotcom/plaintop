import QtQuick
import plaintop

// Plasma's Mpris2Model for the player view, fed by the service's /player (the System Media
// Transport Controls). A ListModel, so the view's Instantiator gets its rows — identity,
// desktopEntry, isMultiplexer, container — and `currentPlayer` is the multiplexer's
// container: a QtObject mirroring whichever session Windows calls current, as kmpris's
// row 0 follows whoever is playing. A container has the properties the view binds to and
// the methods it calls.
//
// ⚠️ The view calls the D-Bus-named methods Previous(), PlayPause(), Next(), and QML
// refuses to declare a method whose name begins with a capital letter. A QObject wrapper
// looks an unknown name up along the JavaScript prototype chain, so the three names are
// put on Object.prototype once, forwarding to the lowercase methods of the object they are
// called on. Attaching them to the objects themselves does not work: the wrappers of
// QML-created objects are not extensible, and the row objects of a ListModel are, but
// their extra properties vanish with the next garbage collection (verified, Qt 6.10 —
// docs/GOTCHAS.md).
ListModel {
    id: model

    property var currentPlayer: null
    property int pollMs: 500
    property bool serviceUp: false

    // The multiplexer's container, and one per session by its id.
    property QtObject mux: Container { isMux: true }
    property var containers: ({})
    property var keep: []               // the containers, so none is collected

    component Container: QtObject {
        property bool isMux: false
        property string sessionId: ""
        property string identity: ""
        property string desktopEntry: ""
        property string track: ""
        property string artist: ""
        property string album: ""
        property double length: 0
        property double position: 0
        property real rate: 1
        property int playbackStatus: 0
        property bool canGoNext: false
        property bool canGoPrevious: false
        property bool canPlay: false
        property bool canPause: false
        // Where the position stood when it was last set, to tell a seek from the clock.
        property double positionStamp: 0

        function command(name) {
            if (sessionId.length === 0) return
            const c = this
            Service.postJson("/player", { id: sessionId, command: name }, function(d) {
                // The answer after a command is fetched at once; a position asked for is
                // forced into the container, so the view hears it even when unchanged.
                Service.getJson("/player", function(d2) {
                    if (!d2 || !d2.players) return
                    model.apply(d2)
                    if (name === "Position") {
                        for (const p of d2.players)
                            if (String(p.id) === c.sessionId) model.fill(c, p, true)
                    }
                })
            })
        }
        function previous() { command("Previous") }
        function playPause() { command("PlayPause") }
        function next() { command("Next") }
        function play() { if (playbackStatus !== 3) command("PlayPause") }
        function pause() { if (playbackStatus === 3) command("PlayPause") }
        function stop() { pause() }
        function updatePosition() { command("Position") }
    }

    function installPrototype() {
        const map = { Previous: "previous", PlayPause: "playPause", Next: "next",
                      Play: "play", Pause: "pause", Stop: "stop" }
        for (const name in map) {
            if (Object.prototype[name] !== undefined) continue
            const target = map[name]
            Object.defineProperty(Object.prototype, name, {
                value: function() { return this[target]() }, configurable: true, writable: true
            })
        }
    }

    function fill(c, p, force) {
        const set = function(key, v) { if (c[key] !== v) c[key] = v }
        set("sessionId", String(p.id || ""))
        set("identity", String(p.identity || ""))
        set("desktopEntry", String(p.desktopEntry || ""))
        set("track", String(p.track || ""))
        set("artist", String(p.artist || ""))
        set("album", String(p.album || ""))
        set("length", Number(p.length) || 0)
        set("rate", Number(p.rate) || 1)
        set("playbackStatus", Number(p.playbackStatus) || 0)
        set("canGoNext", p.canGoNext === true)
        set("canGoPrevious", p.canGoPrevious === true)
        set("canPlay", p.canPlay === true)
        set("canPause", p.canPause === true)
        // The position is reported only when it jumped: the view keeps its own clock from
        // the last report and asks (updatePosition) every ten seconds, as with kmpris.
        const now = Date.now()
        const expected = c.position + (c.playbackStatus === 3 ? (now - c.positionStamp) * 1000 * c.rate : 0)
        const got = Number(p.position) || 0
        if (force || Math.abs(got - expected) > 1500000 || c.positionStamp === 0) {
            c.positionStamp = now
            const same = c.position === got
            c.position = got
            if (same) c.positionChanged()      // an answered updatePosition() must be heard
        }
    }

    function poll() {
        Service.getJson("/player", function(d) {
            if (!d || !d.players) { model.serviceUp = false; return }
            model.serviceUp = true
            model.apply(d)
        }, 3000)
    }

    function apply(d) {
        const players = d.players || []
        const seen = ({})
        // Rows after the multiplexer: one per session, kept in the service's order.
        for (let i = 0; i < players.length; i++) {
            const p = players[i]
            const id = String(p.id || i)
            seen[id] = true
            let c = containers[id]
            if (!c) {
                c = containerFactory.createObject(model, {})
                containers[id] = c
                keep.push(c)
            }
            fill(c, p, false)
            const row = i + 1
            if (row < count) {
                if (get(row).sessionId !== id) {
                    set(row, { identity: c.identity, desktopEntry: c.desktopEntry, isMultiplexer: false,
                               container: c, sessionId: id })
                } else {
                    if (get(row).identity !== c.identity) setProperty(row, "identity", c.identity)
                    if (get(row).desktopEntry !== c.desktopEntry) setProperty(row, "desktopEntry", c.desktopEntry)
                }
            } else {
                append({ identity: c.identity, desktopEntry: c.desktopEntry, isMultiplexer: false,
                         container: c, sessionId: id })
            }
        }
        while (count > players.length + 1) remove(count - 1)
        for (const id in containers)
            if (!seen[id]) { containers[id].sessionId = ""; delete containers[id] }

        const cur = Number(d.current)
        if (players.length > 0) {
            const p = players[(cur >= 0 && cur < players.length) ? cur : 0]
            fill(mux, p, false)
            if (currentPlayer !== mux) currentPlayer = mux
        } else if (currentPlayer !== null) {
            currentPlayer = null
        }
    }

    property Component containerFactory: Component { Container {} }

    property Timer timer: Timer {
        interval: Math.max(250, model.pollMs)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: model.poll()
    }

    Component.onCompleted: {
        installPrototype()
        // Row 0 is the multiplexer, as in kmpris: always there, following whoever plays.
        append({ identity: "", desktopEntry: "", isMultiplexer: true, container: mux, sessionId: "" })
    }
}
