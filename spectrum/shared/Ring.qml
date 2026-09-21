import QtQuick

// Visual side of the visualizer. A tick is a rectangle inside a zero-sized pivot, so
// ring, arc and line differ only in where the pivot stands and how far it is turned —
// a new shape costs a formula, not a second renderer.
//
// Shared by the plasmoid and the standalone window. Levels arrive from a Spectrum
// handed over as `source`; nothing here polls anything.
Item {
    id: face

    // Data source (shared/Spectrum.qml).
    property QtObject source: null

    // Shape.
    property int layoutMode: 0        // 0 ring, 1 line
    property int bars: 160
    property int radius: 360
    property int span: 360
    property int startAngle: 0
    property int spacing: 2
    property int thickness: 5
    property int minLength: 10
    property int maxLength: 170
    property int growth: 0            // 0 outward/up, 1 inward/down, 2 both ways
    // Element.
    property int element: 0           // 0 solid bar, 1 stack of blocks
    property int blockSize: 6
    property int blockGap: 3
    property bool rounded: false
    // Appearance.
    property color tint: "#C8CCD4"
    property string tintHigh: ""
    property int opacityPercent: 100
    property bool guide: false
    // Dynamics.
    property int smoothMs: 70
    property int fadeMs: 500
    property bool hideWhenQuiet: true

    readonly property int count: Math.max(2, bars)
    readonly property bool isRing: layoutMode === 0
    readonly property real base: isRing ? radius : 0
    readonly property real reach: minLength + maxLength

    // Size follows the geometry, never the live data: a hint that follows the data makes
    // a containment relayout every frame and drops the widget into the corner.
    implicitWidth: isRing ? 2 * (radius + reach + thickness) : count * (thickness + spacing)
    implicitHeight: isRing ? 2 * (radius + reach + thickness) : reach + thickness

    // The whole face fades on silence: one animation instead of one per tick.
    opacity: (!hideWhenQuiet || !source || source.sounding) ? opacityPercent / 100 : 0
    Behavior on opacity { NumberAnimation { duration: face.fadeMs } }

    Connections {
        target: face.source

        function onLevelsReady(values) {
            for (let i = 0; i < values.length; i++) {
                const item = ticks.itemAt(i)
                if (item)
                    item.level = values[i]
            }
        }
    }

    // A thin circle under the ticks: optional, and cheap because it never changes.
    Rectangle {
        visible: face.isRing && face.guide
        width: face.radius * 2
        height: width
        radius: width / 2
        anchors.centerIn: parent
        color: "transparent"
        border.width: 1
        border.color: face.tint
        opacity: 0.35
        antialiasing: true
    }

    Repeater {
        id: ticks
        model: face.count

        // The pivot has no size of its own: it only says where the tick stands and which
        // way it points.
        Item {
            id: pivot
            required property int index
            property real level: 0

            readonly property real step: face.isRing
                ? face.span / face.count
                : face.thickness + face.spacing
            readonly property real len: face.minLength + level * face.maxLength

            x: face.isRing ? parent.width / 2 : index * step + face.thickness / 2
            y: face.isRing
                ? parent.height / 2
                : (face.growth === 1 ? face.thickness / 2 : parent.height - face.thickness / 2)
            rotation: face.isRing ? face.startAngle + index * step : 0

            // A second colour, if set, is mixed in along the spectrum: low bands keep
            // `tint`, high bands drift toward `tintHigh`.
            readonly property color shade: face.tintHigh.length > 0
                ? Qt.tint(face.tint,
                          Qt.rgba(Qt.color(face.tintHigh).r,
                                  Qt.color(face.tintHigh).g,
                                  Qt.color(face.tintHigh).b,
                                  index / face.count))
                : face.tint

            Loader {
                sourceComponent: face.element === 1 ? blocksElement : barElement
            }

            Component {
                id: barElement

                Rectangle {
                    width: face.thickness
                    height: pivot.len
                    radius: face.rounded ? width / 2 : 0
                    x: -width / 2
                    y: face.growth === 1
                        ? -face.base
                        : (face.growth === 2 ? -(face.base + height / 2) : -(face.base + height))
                    color: pivot.shade
                    antialiasing: face.rounded

                    Behavior on height {
                        NumberAnimation {
                            duration: face.smoothMs
                            easing.type: Easing.OutQuad
                        }
                    }
                }
            }

            Component {
                id: blocksElement

                // A ladder of fixed blocks, lit from the inside out. Its height is the
                // full reach, not the current level: with the height following the data
                // the whole ladder would slide every frame.
                //
                // ⚠️ The ids matter here. Inside a Repeater delegate `parent` is already
                // this Item, so `parent.parent` points at the pivot — reaching for `lit`
                // that way yielded undefined, every block got opacity 0, and switching to
                // blocks made the ring vanish. Verified and fixed 2026-09-21.
                Item {
                    id: stack

                    readonly property int slots: Math.max(1, Math.floor(
                        face.reach / (face.blockSize + face.blockGap)))
                    readonly property int lit: Math.round(pivot.level * slots)

                    width: face.thickness
                    height: face.reach
                    x: -width / 2
                    y: face.growth === 1
                        ? -face.base
                        : (face.growth === 2 ? -(face.base + height / 2) : -(face.base + height))

                    Repeater {
                        model: stack.slots

                        delegate: Rectangle {
                            required property int index
                            width: face.thickness
                            height: face.blockSize
                            radius: face.rounded ? width / 2 : 0
                            // Block 0 sits on the ring, the rest climb outward.
                            y: stack.height - (index + 1) * face.blockSize - index * face.blockGap
                            color: pivot.shade
                            opacity: index < stack.lit ? 1 : 0
                            antialiasing: face.rounded

                            Behavior on opacity { NumberAnimation { duration: face.smoothMs } }
                        }
                    }
                }
            }
        }
    }
}
