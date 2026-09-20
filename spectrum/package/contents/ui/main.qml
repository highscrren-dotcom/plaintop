import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    // The visualizer lives on the wallpaper: no plate, no frame. The user can put
    // one back through the standard dialog.
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    preferredRepresentation: fullRepresentation

    readonly property var cfg: Plasmoid.configuration

    readonly property int count: Math.max(2, cfg.bars)
    readonly property bool isRing: cfg.layout === 0
    readonly property real base: isRing ? cfg.radius : 0
    readonly property real reach: cfg.minLength + cfg.maxLength

    // ⚠️ Size comes from the geometry, and the hint on the root must be constant for
    // the given settings: a hint that follows live data makes the containment relayout
    // every frame and drop the widget into the 0,0 corner. See docs/GOTCHAS.md.
    readonly property real boardWidth: isRing
        ? 2 * (cfg.radius + reach + cfg.thickness)
        : count * (cfg.thickness + cfg.spacing)
    readonly property real boardHeight: isRing
        ? 2 * (cfg.radius + reach + cfg.thickness)
        : reach + cfg.thickness

    Layout.minimumWidth: boardWidth
    Layout.minimumHeight: boardHeight
    Layout.preferredWidth: boardWidth
    Layout.preferredHeight: boardHeight

    // ── Data ──────────────────────────────────────────────────────────────────
    // The relay serves cava's bands as a comma-separated line over local HTTP.
    // Plain text rather than JSON: at 30 polls a second the parsing shows up.
    property var target: []
    property bool relayUp: false

    function poll() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status !== 200) {
                root.relayUp = false
                return
            }
            root.relayUp = true
            const raw = xhr.responseText.split(",")
            const values = new Array(raw.length)
            for (let i = 0; i < raw.length; i++)
                values[i] = (+raw[i]) / 1000
            root.target = values
            root.apply()
        }
        xhr.open("GET", "http://127.0.0.1:" + cfg.relayPort + "/bands?bars=" + count)
        xhr.send()
    }

    // Band order: mirrored halves fold the spectrum back on itself, reverse flips it.
    function bandOf(i) {
        let k = cfg.reverse ? count - 1 - i : i
        if (cfg.mirror) {
            const half = Math.floor(count / 2)
            k = k < half ? k : count - 1 - k
            return Math.min(k * 2, count - 1)
        }
        return k
    }

    // ⚠️ The root cannot reach an id declared inside fullRepresentation: a Component
    // has its own scope, and qmllint does not catch it — it shows up at runtime as
    // "ticks is not defined". So the root hands the values over by signal instead.
    signal levelsReady(var values)

    function apply() {
        const t = target
        if (t.length < count)
            return
        const mapped = new Array(count)
        for (let i = 0; i < count; i++)
            mapped[i] = t[bandOf(i)]
        root.levelsReady(mapped)
    }

    Timer {
        interval: Math.max(8, Math.round(1000 / Math.max(1, cfg.dataRate)))
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    // ── Drawing ───────────────────────────────────────────────────────────────
    fullRepresentation: Item {
        implicitWidth: root.boardWidth
        implicitHeight: root.boardHeight

        // A thin circle under the ticks: optional, and cheap because it never changes.
        Rectangle {
            visible: root.isRing && root.cfg.guide
            width: root.cfg.radius * 2
            height: width
            radius: width / 2
            anchors.centerIn: parent
            color: "transparent"
            border.width: 1
            border.color: root.cfg.color
            opacity: root.cfg.opacityPercent / 100 * 0.35
            antialiasing: true
        }

        // Values are written straight into the items. Rebuilding a shared array instead
        // makes all of them re-read it at once, which measured three times more expensive.
        Connections {
            target: root

            function onLevelsReady(values) {
                for (let i = 0; i < values.length; i++) {
                    const item = ticks.itemAt(i)
                    if (item)
                        item.level = values[i]
                }
            }
        }

        Repeater {
            id: ticks
            model: root.count

            // The pivot carries no size of its own: it only says where the tick
            // stands and which way it points. Ring and line differ here and nowhere else.
            Item {
                id: pivot
                required property int index
                property real level: 0

                readonly property real step: root.isRing
                    ? root.cfg.span / root.count
                    : root.cfg.thickness + root.cfg.spacing

                x: root.isRing ? parent.width / 2 : index * step + root.cfg.thickness / 2
                y: root.isRing
                    ? parent.height / 2
                    : (root.cfg.growth === 1 ? root.cfg.thickness / 2 : parent.height - root.cfg.thickness / 2)
                rotation: root.isRing ? root.cfg.startAngle + index * step : 0

                readonly property real len: root.cfg.minLength + level * root.cfg.maxLength

                Loader {
                    sourceComponent: root.cfg.element === 1 ? blocksElement : barElement
                }

                Component {
                    id: barElement

                    Rectangle {
                        width: root.cfg.thickness
                        height: pivot.len
                        radius: root.cfg.rounded ? width / 2 : 0
                        x: -width / 2
                        // Outward from the baseline, inward toward it, or both ways.
                        y: root.cfg.growth === 1
                            ? -root.base
                            : (root.cfg.growth === 2 ? -(root.base + height / 2) : -(root.base + height))
                        color: pivot.tint
                        opacity: root.cfg.opacityPercent / 100
                        antialiasing: root.cfg.rounded

                        Behavior on height {
                            NumberAnimation {
                                duration: root.cfg.smoothMs
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                }

                Component {
                    id: blocksElement

                    Item {
                        width: root.cfg.thickness
                        height: pivot.len
                        x: -width / 2
                        y: root.cfg.growth === 1
                            ? -root.base
                            : (root.cfg.growth === 2 ? -(root.base + pivot.len / 2) : -(root.base + pivot.len))

                        readonly property int slots: Math.max(1, Math.floor(
                            (root.cfg.minLength + root.cfg.maxLength) / (root.cfg.blockSize + root.cfg.blockGap)))
                        readonly property int lit: Math.ceil(pivot.level * slots)

                        Repeater {
                            model: parent.slots

                            Rectangle {
                                required property int index
                                width: root.cfg.thickness
                                height: root.cfg.blockSize
                                radius: root.cfg.rounded ? width / 2 : 0
                                y: parent.height - (index + 1) * (root.cfg.blockSize + root.cfg.blockGap)
                                color: pivot.tint
                                opacity: index < parent.parent.lit ? root.cfg.opacityPercent / 100 : 0
                                antialiasing: root.cfg.rounded

                                Behavior on opacity { NumberAnimation { duration: root.cfg.smoothMs } }
                            }
                        }
                    }
                }

                // A second colour, if set, is mixed in along the spectrum: low bands
                // keep `color`, high bands drift toward `colorHigh`.
                readonly property color tint: root.cfg.colorHigh.length > 0
                    ? Qt.tint(root.cfg.color,
                              Qt.rgba(Qt.color(root.cfg.colorHigh).r,
                                      Qt.color(root.cfg.colorHigh).g,
                                      Qt.color(root.cfg.colorHigh).b,
                                      index / root.count))
                    : root.cfg.color
            }
        }

        // Without the relay there is nothing to draw, and silence would look the same
        // as a missing service — so say which it is.
        Text {
            visible: !root.relayUp
            anchors.centerIn: parent
            color: root.cfg.color
            opacity: 0.7
            font.family: "monospace"
            text: "нет данных: служба plainspectrum-relay не отвечает\nпорт " + root.cfg.relayPort
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
