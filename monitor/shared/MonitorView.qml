import QtQuick

// View side of the text monitor: draws the line descriptors that MonitorData builds.
//
// Every part of a line carries a role — "fg", "dim", "accent", "value" — and the palette
// lives here, so the same descriptors serve both hosts and the colours stay one setting
// rather than four literals scattered through the builder. Two columns: the first at the
// left padding, the second — the blocks whose "column" field says so — at `secondColumn`.
//
// Active lines: a line that carries an `action` gets a mouse area of its own size and a
// one-pixel frame while the pointer is over it (dimmer while its menu is open). The view
// only reports the click — `activate` — and answers hit tests for the host's containment
// masks (`activeAt`, `activeBounds`); running the actions is the host's business.
Item {
    id: view

    property var lines: []
    property var lines2: []
    // The second column's left edge in pixels; 0 puts it at half the width.
    property int secondColumn: 0

    property string fontFamily: "JetBrainsMono Nerd Font Mono"
    property int fontSize: 10
    property int padLeft: 48
    property int padTop: 44

    // Palette carried over from conky/plainext.conf — the same PlainExt.
    property color colorFg: "#C8CCD4"
    property color colorAccent: "#E05561"
    property color colorDim: "#6B7280"
    property color colorValue: "#8FB6E0"

    // The line whose menu is open keeps its frame: the column (1 or 2) and the index.
    property int framedColumn: -1
    property int framedIndex: -1

    // A click on an active line: its action, the button, where it is (column, index)
    // and its rectangle in the view's coordinates — the anchor for the menu.
    signal activate(var action, int button, int column, int index, rect area)

    function paint(role) {
        switch (role) {
        case "accent": return view.colorAccent
        case "dim": return view.colorDim
        case "value": return view.colorValue
        default: return view.colorFg
        }
    }

    // Is there an active line at this point of the view? Asked by the host's containment
    // masks on every press and hover while clicks pass through, so it is a hit test on the
    // live delegates — childAt() — rather than a cached list of rectangles.
    function activeAt(x, y) {
        const columns = [leftColumn, rightColumn]
        for (let i = 0; i < columns.length; i++) {
            const col = columns[i]
            if (!col.visible) continue
            const c = col.childAt(x - col.x, y - col.y)
            if (c && c.active === true) return true
        }
        return false
    }

    // The rectangle around every active line, in the view's coordinates; 0×0 without
    // one. The host's fallback mask when a function mask is refused.
    function activeBounds() {
        let r = null
        const columns = [leftColumn, rightColumn]
        for (let i = 0; i < columns.length; i++) {
            const col = columns[i]
            if (!col.visible) continue
            for (let k = 0; k < col.children.length; k++) {
                const c = col.children[k]
                if (!c || c.active !== true) continue
                const x0 = col.x + c.x, y0 = col.y + c.y, x1 = x0 + c.width, y1 = y0 + c.height
                r = r === null ? [x0, y0, x1, y1]
                               : [Math.min(r[0], x0), Math.min(r[1], y0), Math.max(r[2], x1), Math.max(r[3], y1)]
            }
        }
        return r === null ? Qt.rect(0, 0, 0, 0) : Qt.rect(r[0], r[1], r[2] - r[0], r[3] - r[1])
    }

    // A widget line: monospace text, colour and size set in place.
    // ⚠️ PlainText, and not only for the markup: a Text with the default textFormat accepts
    // the left button, and under a partial containment mask such a child arms the
    // wrapper's press-and-hold timer on a plain click (docs/GOTCHAS.md, decision 11).
    component Line: Text {
        color: view.colorFg
        font.family: view.fontFamily
        font.pointSize: view.fontSize
        renderType: Text.NativeRendering
        // Journal messages are free text: "<b>" or "<a …>" in one must not become markup.
        textFormat: Text.PlainText
    }

    // One column of lines. ⚠️ The model is a count, not the array. `items` is a new array
    // on every tick, and a Repeater handed an array destroys and recreates every delegate
    // when it changes: 41 lines rebuilt 1.4 times a second, 3.5% of a core. With a count
    // the delegates stay, their bindings re-read their line, and a Text whose string did
    // not change does no work. Measured on s1dPC 2026-09-22, same picture compared by
    // screenshot.
    component LineColumn: Column {
        id: column
        property var items: []
        property int which: 1
        spacing: 0

        Repeater {
            model: column.items.length

            Item {
                id: lineItem
                required property int index
                readonly property var modelData: column.items[index] || ({ kind: "parts", parts: [] })
                // The line's action, when it has one: what the mouse area reports and what
                // the host's hit test (activeAt) looks for in the column's children.
                readonly property var action: modelData.action || null
                readonly property bool active: action !== null && action !== undefined

                implicitWidth: modelData.kind === "clock" ? clockRow.implicitWidth : partsRow.implicitWidth
                implicitHeight: modelData.kind === "clock" ? clockRow.implicitHeight : partsRow.implicitHeight

                // The frame: a pixel around the line under the pointer, dimmer around the
                // line whose menu is open. A Rectangle takes no mouse.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -1
                    color: "transparent"
                    border.width: 1
                    border.color: view.colorValue
                    visible: lineItem.active
                             && (area.containsMouse
                                 || (view.framedColumn === column.which && view.framedIndex === lineItem.index))
                    opacity: area.containsMouse ? 0.9 : 0.5
                }

                // The one thing in the widget that takes the mouse, and only on an active
                // line: disabled, it is not a pointer target and gets no hover.
                MouseArea {
                    id: area
                    anchors.fill: parent
                    enabled: lineItem.active
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => view.activate(lineItem.action, mouse.button, column.which, lineItem.index,
                                                      lineItem.mapToItem(view, 0, 0, lineItem.width, lineItem.height))
                }

                // Row sets only x, so the small seconds can sit on the baseline of the big
                // clock — otherwise they drift in height.
                Row {
                    id: clockRow
                    visible: modelData.kind === "clock"
                    spacing: 0

                    Line {
                        id: bigClock
                        text: clockRow.visible ? modelData.big : ""
                        font.pointSize: view.fontSize * 3.4
                        font.bold: true
                        color: view.colorAccent
                    }

                    Line {
                        text: clockRow.visible ? modelData.small : ""
                        font.pointSize: view.fontSize * 1.5
                        color: view.colorValue
                        anchors.baseline: bigClock.baseline
                    }
                }

                Row {
                    id: partsRow
                    visible: modelData.kind !== "clock"
                    spacing: 0

                    Repeater {
                        // A count here too, for the same reason.
                        model: partsRow.visible ? lineItem.modelData.parts.length : 0

                        Line {
                            required property int index
                            readonly property var part: lineItem.modelData.parts[index] || ({ text: "", role: "fg" })
                            text: part.text
                            color: view.paint(part.role)
                        }
                    }
                }
            }
        }
    }

    // ⚠️ The padding is drawn INSIDE the widget rather than set through its coordinates:
    // a place set by a script is reset to the 0,0 corner by plasmashell on the next start
    // anyway — verified. This way the conky-like gap from the edge holds wherever the host
    // put the widget.
    LineColumn {
        id: leftColumn
        x: view.padLeft
        y: view.padTop
        items: view.lines
        which: 1
    }

    LineColumn {
        id: rightColumn
        x: view.secondColumn > 0 ? view.secondColumn : Math.round(view.width / 2)
        y: view.padTop
        items: view.lines2
        which: 2
        visible: items.length > 0
    }
}
