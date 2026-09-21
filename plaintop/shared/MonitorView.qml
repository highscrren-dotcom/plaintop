import QtQuick

// View side of the text monitor: draws the line descriptors that MonitorData builds.
//
// Every part of a line carries a role — "fg", "dim", "accent", "value" — and the palette
// lives here, so the same descriptors serve both hosts and the colours stay one setting
// rather than four literals scattered through the builder.
Item {
    id: view

    property var lines: []

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
    }

    // ⚠️ The padding is drawn INSIDE the widget rather than set through its coordinates:
    // a place set by a script is reset to the 0,0 corner by plasmashell on the next start
    // anyway — verified. This way the conky-like gap from the edge holds wherever the host
    // put the widget.
    Column {
        id: column
        x: view.padLeft
        y: view.padTop
        spacing: 0

        Repeater {
            model: view.lines

            Item {
                required property var modelData

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
                        model: partsRow.visible ? modelData.parts : []

                        Line {
                            required property var modelData
                            text: modelData.text
                            color: view.paint(modelData.role)
                        }
                    }
                }
            }
        }
    }
}
