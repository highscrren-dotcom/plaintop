import QtQuick

// View side of the text monitor: draws the line descriptors that MonitorData builds.
//
// Every part of a line carries a role — "fg", "dim", "accent", "value" — and the palette
// lives here, so the same descriptors serve both hosts and the colours stay one setting
// rather than four literals scattered through the builder. Two columns: the first at the
// left padding, the second — the blocks whose "column" field says so — at `secondColumn`.
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

    function paint(role) {
        switch (role) {
        case "accent": return view.colorAccent
        case "dim": return view.colorDim
        case "value": return view.colorValue
        default: return view.colorFg
        }
    }

    // A widget line: monospace text, colour and size set in place.
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
        spacing: 0

        Repeater {
            model: column.items.length

            Item {
                id: lineItem
                required property int index
                readonly property var modelData: column.items[index] || ({ kind: "parts", parts: [] })

                implicitWidth: modelData.kind === "clock" ? clockRow.implicitWidth : partsRow.implicitWidth
                implicitHeight: modelData.kind === "clock" ? clockRow.implicitHeight : partsRow.implicitHeight

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
        x: view.padLeft
        y: view.padTop
        items: view.lines
    }

    LineColumn {
        x: view.secondColumn > 0 ? view.secondColumn : Math.round(view.width / 2)
        y: view.padTop
        items: view.lines2
        visible: items.length > 0
    }
}
