import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

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
    title: "plainspectrum — настройки"

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
                status.text = "реле не отвечает на порту " + app.port
                return
            }
            app.cfg = JSON.parse(xhr.responseText)
            app.loaded = true
            status.text = "настройки прочитаны"
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
                    status.text = xhr.status === 200 ? "сохранено" : "не сохранилось: " + xhr.status
            }
            xhr.open("POST", "http://127.0.0.1:" + app.port + "/config")
            xhr.setRequestHeader("Content-Type", "application/json")
            xhr.send(body)
        }
    }

    Component.onCompleted: load()

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing

            Label {
                id: status
                text: "загрузка…"
                Layout.fillWidth: true
            }

            Button {
                text: "Перечитать"
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

                Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Форма" }

                ComboBox {
                    Kirigami.FormData.label: "Раскладка:"
                    model: ["Кольцо", "Линия"]
                    currentIndex: app.num("layout", 0)
                    onActivated: app.change("layout", currentIndex)
                }

                SpinBox {
                    Kirigami.FormData.label: "Штрихов:"
                    from: 8; to: 512; stepSize: 8
                    value: app.num("bars", 160)
                    onValueModified: app.change("bars", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Радиус, px:"
                    from: 20; to: 2000; stepSize: 10
                    value: app.num("radius", 360)
                    onValueModified: app.change("radius", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Охват, °:"
                    from: 30; to: 360; stepSize: 5
                    value: app.num("span", 360)
                    onValueModified: app.change("span", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Начальный угол, °:"
                    from: 0; to: 359; stepSize: 5
                    value: app.num("startAngle", 0)
                    onValueModified: app.change("startAngle", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Толщина штриха, px:"
                    from: 1; to: 60
                    value: app.num("thickness", 5)
                    onValueModified: app.change("thickness", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Зазор (для линии), px:"
                    from: 0; to: 60
                    value: app.num("spacing", 2)
                    onValueModified: app.change("spacing", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Длина в тишине, px:"
                    from: 0; to: 400; stepSize: 2
                    value: app.num("minLength", 10)
                    onValueModified: app.change("minLength", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Добавка на максимуме, px:"
                    from: 10; to: 1000; stepSize: 10
                    value: app.num("maxLength", 170)
                    onValueModified: app.change("maxLength", value)
                }

                ComboBox {
                    Kirigami.FormData.label: "Рост:"
                    model: ["наружу", "внутрь", "в обе стороны"]
                    currentIndex: app.num("growth", 0)
                    onActivated: app.change("growth", currentIndex)
                }

                CheckBox {
                    Kirigami.FormData.label: "Порядок:"
                    text: "зеркально"
                    checked: app.num("mirror", false)
                    onToggled: app.change("mirror", checked)
                }

                CheckBox {
                    text: "обратный порядок"
                    checked: app.num("reverse", false)
                    onToggled: app.change("reverse", checked)
                }

                Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Вид" }

                ComboBox {
                    Kirigami.FormData.label: "Элемент:"
                    model: ["Полоска", "Блоки"]
                    currentIndex: app.num("element", 0)
                    onActivated: app.change("element", currentIndex)
                }

                SpinBox {
                    Kirigami.FormData.label: "Блок, px:"
                    from: 2; to: 40
                    value: app.num("blockSize", 6)
                    onValueModified: app.change("blockSize", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Зазор блоков, px:"
                    from: 0; to: 40
                    value: app.num("blockGap", 3)
                    onValueModified: app.change("blockGap", value)
                }

                CheckBox {
                    Kirigami.FormData.label: "Концы:"
                    text: "скруглять"
                    checked: app.num("rounded", false)
                    onToggled: app.change("rounded", checked)
                }

                KQuickControls.ColorButton {
                    Kirigami.FormData.label: "Цвет:"
                    color: app.num("color", "#C8CCD4")
                    onColorChanged: app.change("color", color.toString())
                }

                RowLayout {
                    Kirigami.FormData.label: "Цвет высоких:"

                    KQuickControls.ColorButton {
                        id: highColor
                        enabled: highOn.checked
                        color: app.num("colorHigh", "") !== "" ? app.num("colorHigh", "") : app.num("color", "#C8CCD4")
                        onColorChanged: if (highOn.checked) app.change("colorHigh", color.toString())
                    }

                    CheckBox {
                        id: highOn
                        text: "свой"
                        checked: app.num("colorHigh", "") !== ""
                        onToggled: app.change("colorHigh", checked ? highColor.color.toString() : "")
                    }
                }

                SpinBox {
                    Kirigami.FormData.label: "Прозрачность, %:"
                    from: 10; to: 100; stepSize: 5
                    value: app.num("opacityPercent", 100)
                    onValueModified: app.change("opacityPercent", value)
                }

                CheckBox {
                    Kirigami.FormData.label: "Окружность:"
                    text: "тонкая направляющая"
                    checked: app.num("guide", false)
                    onToggled: app.change("guide", checked)
                }

                Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Поведение" }

                SpinBox {
                    Kirigami.FormData.label: "Кадров данных в секунду:"
                    from: 5; to: 60; stepSize: 5
                    value: app.num("dataRate", 30)
                    onValueModified: app.change("dataRate", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Сглаживание, мс:"
                    from: 0; to: 400; stepSize: 10
                    value: app.num("smoothMs", 70)
                    onValueModified: app.change("smoothMs", value)
                }

                CheckBox {
                    Kirigami.FormData.label: "В тишине:"
                    text: "растворять"
                    checked: app.num("hideWhenQuiet", true)
                    onToggled: app.change("hideWhenQuiet", checked)
                }

                SpinBox {
                    Kirigami.FormData.label: "Порог тишины, %:"
                    from: 0; to: 50
                    value: app.num("quietThreshold", 2)
                    onValueModified: app.change("quietThreshold", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Ждать до исчезновения, мс:"
                    from: 100; to: 10000; stepSize: 100
                    value: app.num("quietDelayMs", 900)
                    onValueModified: app.change("quietDelayMs", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Появление, мс:"
                    from: 0; to: 3000; stepSize: 50
                    value: app.num("fadeMs", 500)
                    onValueModified: app.change("fadeMs", value)
                }

                SpinBox {
                    Kirigami.FormData.label: "Опросов в тишине:"
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
                text: "живой просмотр · масштаб " + previewRing.scale.toFixed(2)
            }
        }
    }
}
