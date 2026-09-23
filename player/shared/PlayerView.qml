import QtQuick

import org.kde.plasma.private.mpris as Mpris

// The player as text. Reads one MPRIS player through Plasma's own kmpris model and draws
// it the way the monitor draws its lines: monospace, no frames, a slash bar for the
// position. The controls are text too — three glyphs with a mouse area under each.
//
// Shared by two hosts — the player widget and the visualizer, which draws it in the
// centre of its ring — so install.sh copies this file into both packages from
// player/shared/. Strings go through the bare i18n() of whichever plasmoid loads the
// copy: the domain follows the host, and both catalogs carry these strings.
//
// The data is org.kde.plasma.private.mpris, the module behind Plasma's media controller:
// its Mpris2Model lists every player on the session bus, row 0 being a multiplexer that
// follows whoever is playing. Should that private module ever break, the same properties
// are reachable through org.kde.plasma.workspace.dbus (a Properties object on
// org.mpris.MediaPlayer2.<name> over SessionBus) — a fallback, not implemented.
Item {
    id: view

    // Which player to follow. Empty: the multiplexer, whoever is playing. Otherwise the
    // row whose identity or desktop entry contains the text, case-insensitively — "vlc",
    // "spotify", "strawberry" — with the multiplexer as the fallback when none does.
    property string playerFilter: ""
    property bool showAlbum: true
    property bool showControls: true
    property int columns: 44
    // With no player on the bus the widget says so; inside the visualizer's ring the same
    // moment should draw nothing at all, so the host sets this and the lines come out empty.
    property bool quietWhenNoPlayer: false

    property string fontFamily: "JetBrainsMono Nerd Font Mono"
    property int fontSize: 10
    property color colorFg: "#C8CCD4"
    property color colorAccent: "#E05561"
    property color colorDim: "#6B7280"

    Mpris.Mpris2Model { id: mpris2Model }

    // Every row of the model as a small object, so a player can be found by name with
    // the roles addressed by name rather than by number. The rows are few.
    Instantiator {
        id: rows
        model: mpris2Model
        delegate: QtObject {
            required property int index
            required property string identity
            required property string desktopEntry
            required property bool isMultiplexer
            required property var container
            // The name arrives after the row: match again when it does.
            onIdentityChanged: view.pick()
            onDesktopEntryChanged: view.pick()
        }
        onObjectAdded: (index, object) => view.pick()
        onObjectRemoved: (index, object) => view.pick()
    }

    // The container of the row that matches the filter; null means "use the multiplexer".
    // The model's own currentPlayer is left alone: its bookkeeping across players coming
    // and going is what Plasma's controller relies on, and it already means "whoever plays".
    property var chosen: null
    readonly property var player: chosen ?? (mpris2Model.currentPlayer ?? null)

    onPlayerFilterChanged: pick()

    function pick() {
        const want = playerFilter.trim().toLowerCase()
        let found = null
        if (want.length > 0) {
            for (let i = 0; i < rows.count; ++i) {
                const r = rows.objectAt(i)
                if (!r || r.isMultiplexer)
                    continue
                if (r.identity.toLowerCase().includes(want) || r.desktopEntry.toLowerCase().includes(want)) {
                    found = r.container
                    break
                }
            }
        }
        chosen = found
    }

    // What the widget shows, read through `?.`: the player is null whenever nothing is on
    // the bus, and the multiplexer's container goes away with the last player.
    readonly property string identity: player?.identity ?? ""
    readonly property string track: player?.track ?? ""
    readonly property string artist: player?.artist ?? ""
    readonly property string album: player?.album ?? ""
    readonly property double length: player?.length ?? 0          // µs
    readonly property real rate: player?.rate ?? 1
    readonly property int status: player?.playbackStatus ?? Mpris.PlaybackStatus.Unknown
    readonly property bool playing: status === Mpris.PlaybackStatus.Playing
    readonly property bool paused: status === Mpris.PlaybackStatus.Paused
    readonly property bool canGoNext: player?.canGoNext ?? false
    readonly property bool canGoPrevious: player?.canGoPrevious ?? false
    readonly property bool canPlay: player?.canPlay ?? false
    readonly property bool canPause: player?.canPause ?? false

    // The position is not polled by the model: it holds what the player last reported —
    // a Seeked signal or an explicit query — and the widget counts on from there at the
    // playback rate, asking the player again every ten seconds while playing; the model
    // asks by itself on a track, rate or status change. Plasma's own controller does the same.
    property double position: 0                                     // µs

    Connections {
        target: view.player
        function onPositionChanged() { view.position = view.player.position }
    }

    onPlayerChanged: {
        position = player?.position ?? 0
        player?.updatePosition()
    }

    Timer {
        id: clock
        interval: 1000
        repeat: true
        running: view.playing && view.player !== null
        property int ticks: 0
        onRunningChanged: ticks = 0
        onTriggered: {
            view.position += view.rate * 1000000
            if (view.length > 0 && view.position > view.length)
                view.position = view.length
            if (++ticks % 10 === 0)
                view.player.updatePosition()
        }
    }

    // ── Formatting ────────────────────────────────────────────────────────────
    // Written here, not through a Formatter: the ready-made ones insert invisible
    // U+2009/U+200B characters and the monospace columns drift (docs/GOTCHAS.md).

    // m:ss, or h:mm:ss when the track is an hour or longer.
    function timeText(us, hours) {
        const s = Math.max(0, Math.round(us / 1000000))
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60
        const head = hours ? h + ":" + String(m).padStart(2, "0") : String(m)
        return head + ":" + String(sec).padStart(2, "0")
    }

    // Slashes then spaces, a fixed width — the monitor's bar.
    function bar(pct, width) {
        const k = Math.max(0, Math.min(width, Math.round(pct * width / 100)))
        return "/".repeat(k) + " ".repeat(width - k)
    }

    // Cuts a line of parts to the column width, ending it with an ellipsis. Code points,
    // not UTF-16 units, so a dash or a non-Latin title is not cut in half.
    function fit(parts) {
        let left = columns
        const out = []
        for (let i = 0; i < parts.length; ++i) {
            const chars = Array.from(parts[i].text)
            if (chars.length > left) {
                out.push({ text: chars.slice(0, Math.max(0, left - 1)).join("") + "…", role: parts[i].role })
                break
            }
            out.push(parts[i])
            left -= chars.length
            // The parts so far fill the line exactly and more is to come: the ellipsis
            // takes the last column, so the dropped part still shows as a cut.
            if (left === 0 && parts.slice(i + 1).some(p => p.text.length > 0)) {
                out[i] = { text: chars.slice(0, -1).join("") + "…", role: parts[i].role }
                break
            }
        }
        return out
    }

    // ── Lines ─────────────────────────────────────────────────────────────────
    // Each line is a list of parts with a role — "fg", "dim", "accent" — as in the
    // monitor. A line with nothing to say is left out, not left blank.
    readonly property var lines: {
        const out = []
        const header = i18nc("the widget's header line", "NOW PLAYING")
        if (!player) {
            if (quietWhenNoPlayer)
                return out
            out.push([{ text: header, role: "fg" },
                      { text: "  " + i18nc("no MPRIS player on the bus", "no player"), role: "dim" }])
            return out
        }
        out.push(fit([{ text: header, role: "fg" }, { text: "  " + identity, role: "dim" }]))

        if (artist.length > 0 && track.length > 0)
            out.push(fit([{ text: artist + " — ", role: "fg" }, { text: track, role: "accent" }]))
        else if (track.length > 0)
            out.push(fit([{ text: track, role: "accent" }]))
        else if (artist.length > 0)
            out.push(fit([{ text: artist, role: "fg" }]))

        if (showAlbum && album.length > 0)
            out.push(fit([{ text: album, role: "dim" }]))

        if (!playing && !paused) {
            out.push([{ text: i18nc("playback status", "stopped"), role: "dim" }])
            return out
        }
        // With the controls hidden a pause has nowhere else to show: it goes after the time.
        const note = (paused && !showControls) ? "  " + i18nc("playback status", "paused") : ""
        let line
        if (length > 0) {
            // Elapsed is padded to the total's width, so the bar keeps its width for the
            // whole track and the time column does not wander. The hour digit is decided
            // on the rounded seconds, as the text is: 59:59.7 reads 1:00:00, not 0:00.
            const hours = Math.round(length / 1000000) >= 3600
            const total = timeText(length, hours)
            const elapsed = timeText(Math.min(position, length), hours).padStart(total.length)
            const time = elapsed + " / " + total
            const width = columns - 2 - time.length - note.length
            line = (width > 0 ? bar(position * 100 / length, width) + "  " : "") + time
        } else {
            line = timeText(position, Math.round(position / 1000000) >= 3600)
        }
        const parts = [{ text: line, role: "fg" }]
        if (note.length > 0)
            parts.push({ text: note, role: "dim" })
        out.push(fit(parts))
        return out
    }

    function paint(role) {
        switch (role) {
        case "accent": return view.colorAccent
        case "dim": return view.colorDim
        default: return view.colorFg
        }
    }

    // The controls row's rectangle in the view's coordinates: from the first glyph to the end
    // of the last, the row's height. Empty while the row is hidden — no player, or the
    // controls switched off — so that nothing in the widget takes the mouse then. The hosts
    // put this rectangle on the applet's wrapper as its containmentMask (decision 11), and
    // only this area takes clicks while the rest passes them through. Summed by hand rather
    // than through mapToItem(): a binding follows only the properties it reads, and the
    // column, the row and the glyphs are each the direct child of the previous one.
    readonly property rect controlsRect: controlsRow.visible
        ? Qt.rect(board.x + controlsRow.x + prevControl.x, board.y + controlsRow.y,
                  nextControl.x + nextControl.width - prevControl.x, controlsRow.height)
        : Qt.rect(0, 0, 0, 0)

    // A widget line: monospace text, colour and size set in place.
    // ⚠️ textFormat: PlainText is what keeps the widget out of the mouse's way: a Text with
    // the default AutoText accepts the left button (qquicktext.cpp), and under the partial
    // mask any child that accepts the button arms the wrapper's press-and-hold timer, so an
    // ordinary click on the text would enter the desktop's edit mode 800 ms later —
    // tests/passthrough.qml, test_10. Every Text here derives from this one.
    component Line: Text {
        color: view.colorFg
        font.family: view.fontFamily
        font.pointSize: view.fontSize
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
    }

    // A control: a glyph and a mouse area, nothing drawn around it. Dim when the player
    // says it cannot do it — the call would silently do nothing anyway.
    component Control: Line {
        property bool can: true
        signal pressed()
        color: can ? view.colorFg : view.colorDim
        MouseArea {
            anchors.fill: parent
            cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: parent.pressed()
        }
    }

    Column {
        id: board
        spacing: 0

        // The model is a count, not the array: with a count the delegates stay when the
        // lines are rebuilt every second, and a Text whose string did not change does
        // nothing (docs/GOTCHAS.md, the Repeater note).
        Repeater {
            model: view.lines.length

            Row {
                id: lineRow
                required property int index
                readonly property var parts: view.lines[index] || []
                spacing: 0

                Repeater {
                    model: lineRow.parts.length

                    Line {
                        required property int index
                        readonly property var part: lineRow.parts[index] || ({ text: "", role: "fg" })
                        text: part.text
                        color: view.paint(part.role)
                    }
                }
            }
        }

        // The only part of the widget that takes the mouse — see controlsRect above. The
        // three MouseAreas are the widget's only input items; a hover area over the whole
        // board would take hover everywhere (tests/passthrough.qml, test_13).
        Row {
            id: controlsRow
            visible: view.showControls && view.player !== null
            spacing: 0

            Control {
                id: prevControl
                text: "<<"
                can: view.canGoPrevious
                onPressed: view.player?.Previous()
            }
            Line { text: "   " }
            Control {
                text: view.playing ? "||" : "> "
                can: view.playing ? view.canPause : view.canPlay
                onPressed: view.player?.PlayPause()
            }
            Line { text: "   " }
            Control {
                id: nextControl
                text: ">>"
                can: view.canGoNext
                onPressed: view.player?.Next()
            }
            Line {
                visible: view.paused
                text: "  " + i18nc("playback status", "paused")
                color: view.colorDim
            }
        }
    }
}
