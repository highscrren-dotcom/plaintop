import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import org.kde.ki18n

// Settings editor for the standalone visualizer. The window host has no Plasma dialog
// behind it, so this is that dialog.
//
// It never touches the file: the relay owns ring.json, this window reads GET /config and
// sends changes with POST /config. QML cannot write files, and one owner beats two.
ApplicationWindow {
    id: app

    width: 1040
    height: 720
    visible: true
    title: tr.i18n("plainspectrum — settings")

    readonly property int port: 8788

    property var cfg: ({})
    property bool loaded: false

    function num(key, fallback) {
        const v = cfg[key]
        return (v === undefined || v === null) ? fallback : v
    }

    function load() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status !== 200) {
                status.text = tr.i18n("the relay does not answer on port %1", app.port)
                return
            }
            app.cfg = JSON.parse(xhr.responseText)
            app.loaded = true
            status.text = tr.i18n("settings read")
        }
        xhr.open("GET", "http://127.0.0.1:" + port + "/config")
        xhr.send()
    }

    // Changes are collected and sent together: dragging a spin box would otherwise fire a
    // request per step.
    property var pending: ({})

    function change(key, value) {
        if (!loaded)
            return
        const copy = ({})
        for (const k in cfg) copy[k] = cfg[k]
        copy[key] = value
        cfg = copy
        pending[key] = value
        saveTimer.restart()
    }

    Timer {
        id: saveTimer
        interval: 250
        onTriggered: {
            const body = JSON.stringify(app.pending)
            app.pending = ({})
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE)
                    status.text = xhr.status === 200 ? tr.i18n("saved") : tr.i18n("not saved: %1", xhr.status)
            }
            xhr.open("POST", "http://127.0.0.1:" + app.port + "/config")
            xhr.setRequestHeader("Content-Type", "application/json")
            xhr.send(body)
        }
    }

    Component.onCompleted: load()

    // The plasmoid's own catalog: the bare qml6 runner has no i18n(), so the calls go
    // through a context object (decision 7 in docs/DECISIONS.md).
    KI18nContext {
        id: tr
        translationDomain: "plasma_applet_org.s1dd1.plainspectrum"
    }

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing

            Label {
                id: status
                text: tr.i18n("loading…")
                Layout.fillWidth: true
            }

            Button {
                text: tr.i18n("Reload")
                onClicked: app.load()
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        ScrollView {
            Layout.fillHeight: true
            Layout.preferredWidth: 520
            contentWidth: availableWidth

            Kirigami.FormLayout {
                width: parent.width

                Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: tr.i18nc("settings section", "Shape") }

                ComboBox {
                    Kirigami.FormData.label: tr.i18n("Layout:")
                    model: [tr.i18nc("layout", "Ring"), tr.i18nc("layout", "Line")]
                    currentIndex: app.num("layout", 0)
                    onActivated: app.change("layout", currentIndex)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Bars:")
                    from: 8; to: 512; stepSize: 8
                    value: app.num("bars", 160)
                    onValueModified: app.change("bars", value)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Radius, px:")
                    from: 20; to: 2000; stepSize: 10
                    value: app.num("radius", 360)
                    onValueModified: app.change("radius", value)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Span, °:")
                    from: 30; to: 360; stepSize: 5
                    value: app.num("span", 360)
                    onValueModified: app.change("span", value)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Start angle, °:")
                    from: 0; to: 359; stepSize: 5
                    value: app.num("startAngle", 0)
                    onValueModified: app.change("startAngle", value)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Bar thickness, px:")
                    from: 1; to: 60
                    value: app.num("thickness", 5)
                    onValueModified: app.change("thickness", value)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Gap (line layout), px:")
                    from: 0; to: 60
                    value: app.num("spacing", 2)
                    onValueModified: app.change("spacing", value)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Length at silence, px:")
                    from: 0; to: 400; stepSize: 2
                    value: app.num("minLength", 10)
                    onValueModified: app.change("minLength", value)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Extra length at maximum, px:")
                    from: 10; to: 1000; stepSize: 10
                    value: app.num("maxLength", 170)
                    onValueModified: app.change("maxLength", value)
                }

                ComboBox {
                    Kirigami.FormData.label: tr.i18n("Growth:")
                    // The same three indices read differently on a line, as on the
                    // plasmoid's page: a ring grows outward, a line grows up.
                    model: app.num("layout", 0) === 0
                        ? [tr.i18nc("growth", "outward"), tr.i18nc("growth", "inward"),
                           tr.i18nc("growth", "both ways")]
                        : [tr.i18nc("growth", "up"), tr.i18nc("growth", "down"),
                           tr.i18nc("growth", "both ways")]
                    currentIndex: app.num("growth", 0)
                    onActivated: app.change("growth", currentIndex)
                }

                CheckBox {
                    Kirigami.FormData.label: tr.i18n("Order:")
                    text: tr.i18n("mirrored")
                    checked: app.num("mirror", false)
                    onToggled: app.change("mirror", checked)
                }

                CheckBox {
                    text: tr.i18n("reverse order")
                    checked: app.num("reverse", false)
                    onToggled: app.change("reverse", checked)
                }

                Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: tr.i18nc("settings section", "Appearance") }

                ComboBox {
                    Kirigami.FormData.label: tr.i18n("Element:")
                    model: [tr.i18nc("element shape", "Bar"), tr.i18nc("element shape", "Blocks")]
                    currentIndex: app.num("element", 0)
                    onActivated: app.change("element", currentIndex)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Block, px:")
                    from: 2; to: 40
                    value: app.num("blockSize", 6)
                    onValueModified: app.change("blockSize", value)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Block gap, px:")
                    from: 0; to: 40
                    value: app.num("blockGap", 3)
                    onValueModified: app.change("blockGap", value)
                }

                CheckBox {
                    Kirigami.FormData.label: tr.i18n("Ends:")
                    text: tr.i18nc("bar ends", "rounded")
                    checked: app.num("rounded", false)
                    onToggled: app.change("rounded", checked)
                }

                KQuickControls.ColorButton {
                    Kirigami.FormData.label: tr.i18n("Colour:")
                    color: app.num("color", "#C8CCD4")
                    onColorChanged: app.change("color", color.toString())
                }

                RowLayout {
                    Kirigami.FormData.label: tr.i18n("Highs colour:")

                    KQuickControls.ColorButton {
                        id: highColor
                        enabled: highOn.checked
                        color: app.num("colorHigh", "") !== "" ? app.num("colorHigh", "") : app.num("color", "#C8CCD4")
                        onColorChanged: if (highOn.checked) app.change("colorHigh", color.toString())
                    }

                    CheckBox {
                        id: highOn
                        text: tr.i18nc("high-frequency colour", "custom")
                        checked: app.num("colorHigh", "") !== ""
                        onToggled: app.change("colorHigh", checked ? highColor.color.toString() : "")
                    }
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Opacity, %:")
                    from: 10; to: 100; stepSize: 5
                    value: app.num("opacityPercent", 100)
                    onValueModified: app.change("opacityPercent", value)
                }

                CheckBox {
                    Kirigami.FormData.label: tr.i18n("Circle:")
                    text: tr.i18n("a thin guide")
                    checked: app.num("guide", false)
                    onToggled: app.change("guide", checked)
                }

                Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: tr.i18nc("settings section", "Behaviour") }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Data frames per second:")
                    from: 5; to: 60; stepSize: 5
                    value: app.num("dataRate", 30)
                    onValueModified: app.change("dataRate", value)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Smoothing, ms:")
                    from: 0; to: 400; stepSize: 10
                    value: app.num("smoothMs", 70)
                    onValueModified: app.change("smoothMs", value)
                }

                CheckBox {
                    Kirigami.FormData.label: tr.i18n("In silence:")
                    text: tr.i18n("dissolve")
                    checked: app.num("hideWhenQuiet", true)
                    onToggled: app.change("hideWhenQuiet", checked)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Silence threshold, %:")
                    from: 0; to: 50
                    value: app.num("quietThreshold", 2)
                    onValueModified: app.change("quietThreshold", value)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Delay before vanishing, ms:")
                    from: 100; to: 10000; stepSize: 100
                    value: app.num("quietDelayMs", 900)
                    onValueModified: app.change("quietDelayMs", value)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Fade, ms:")
                    from: 0; to: 3000; stepSize: 50
                    value: app.num("fadeMs", 500)
                    onValueModified: app.change("fadeMs", value)
                }

                SpinBox {
                    Kirigami.FormData.label: tr.i18n("Polls in silence:")
                    from: 1; to: 30
                    value: app.num("idleRate", 4)
                    onValueModified: app.change("idleRate", value)
                }
            }
        }

        // Live preview: the same Ring the desktop draws, scaled to fit.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#12111c"
            radius: 4
            clip: true

            Spectrum {
                id: preview
                relayPort: app.port
                bars: app.num("bars", 160)
                dataRate: 20
                idleRate: 4
                hideWhenQuiet: app.num("hideWhenQuiet", true)
                quietThreshold: app.num("quietThreshold", 2)
                quietDelayMs: app.num("quietDelayMs", 900)
                mirror: app.num("mirror", false)
                reverse: app.num("reverse", false)
            }

            Ring {
                id: previewRing
                anchors.centerIn: parent
                source: preview
                scale: Math.min(1, Math.min(parent.width / Math.max(1, implicitWidth),
                                            parent.height / Math.max(1, implicitHeight)))

                layoutMode: app.num("layout", 0)
                bars: app.num("bars", 160)
                radius: app.num("radius", 360)
                span: app.num("span", 360)
                startAngle: app.num("startAngle", 0)
                spacing: app.num("spacing", 2)
                thickness: app.num("thickness", 5)
                minLength: app.num("minLength", 10)
                maxLength: app.num("maxLength", 170)
                growth: app.num("growth", 0)
                element: app.num("element", 0)
                blockSize: app.num("blockSize", 6)
                blockGap: app.num("blockGap", 3)
                rounded: app.num("rounded", false)
                tint: app.num("color", "#C8CCD4")
                tintHigh: app.num("colorHigh", "")
                opacityPercent: app.num("opacityPercent", 100)
                guide: app.num("guide", false)
                smoothMs: app.num("smoothMs", 70)
                fadeMs: app.num("fadeMs", 500)
                hideWhenQuiet: app.num("hideWhenQuiet", true)
            }

            Label {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                color: "#6B7280"
                text: tr.i18n("live preview · scale %1", previewRing.scale.toFixed(2))
            }
        }
    }
}
