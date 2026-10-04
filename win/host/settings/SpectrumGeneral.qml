import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The visualizer's Ring page: spectrum/package/contents/ui/configGeneral.qml. The one
// Windows hint is the source's: there is no cava and no relay.env here — the service
// captures the default output itself (win/service/bands.py), on its own port, which the
// host uses while the relay port setting keeps its default.
SettingsPage {
    id: page

    readonly property bool ring: num("layout", 0) === 0
    readonly property bool blocks: num("element", 0) === 1
    readonly property bool quiet: flag("hideWhenQuiet", true)

    Section { title: page.i18nc("settings section", "Shape") }

    FormRow {
        label: page.i18n("Layout:")
        SettingCombo { key: "layout"; model: [page.i18nc("layout", "Ring"), page.i18nc("layout", "Line")] }
    }
    FormRow {
        label: page.i18n("Bars:")
        SettingSpin { key: "bars"; from: 8; to: 512; stepSize: 8 }
    }
    FormRow {
        label: page.i18n("Radius, px:")
        visible: page.ring
        SettingSpin { key: "radius"; from: 20; to: 2000; stepSize: 10 }
    }
    FormRow {
        label: page.i18n("Span, °:")
        visible: page.ring
        SettingSpin { key: "span"; from: 30; to: 360; stepSize: 5 }
    }
    FormRow {
        label: page.i18n("Start angle, °:")
        visible: page.ring
        SettingSpin { key: "startAngle"; from: 0; to: 359; stepSize: 5 }
    }
    FormRow {
        label: page.i18n("Gap between bars, px:")
        visible: !page.ring
        SettingSpin { key: "spacing"; from: 0; to: 60 }
    }
    FormRow {
        label: page.i18n("Bar thickness, px:")
        SettingSpin { key: "thickness"; from: 1; to: 60 }
    }
    FormRow {
        label: page.i18n("Length at silence, px:")
        SettingSpin { key: "minLength"; from: 0; to: 400; stepSize: 2 }
    }
    FormRow {
        label: page.i18n("Extra length at maximum, px:")
        SettingSpin { key: "maxLength"; from: 10; to: 1000; stepSize: 10 }
    }
    FormRow {
        label: page.i18n("Growth:")
        SettingCombo {
            key: "growth"
            model: page.ring
                ? [page.i18nc("growth", "outward"), page.i18nc("growth", "inward"), page.i18nc("growth", "both ways")]
                : [page.i18nc("growth", "up"), page.i18nc("growth", "down"), page.i18nc("growth", "both ways")]
        }
    }
    FormRow {
        label: page.i18n("Order:")
        SettingCheck { key: "mirror"; text: page.i18n("mirrored (low frequencies at the edges)") }
    }
    FormRow {
        SettingCheck { key: "reverse"; text: page.i18n("reverse band order") }
    }
    FormRow {
        label: page.i18n("Channels:")
        SettingCheck { key: "monoSpectrum"; text: page.i18n("one spectrum around the whole ring, both channels averaged") }
    }
    Hint {
        text: page.i18n("Off: as cava gives it — the left channel from high to low, then the right\nfrom low to high, so the ring is mirrored about its middle.")
    }

    Section { title: page.i18nc("settings section", "Appearance") }

    FormRow {
        label: page.i18n("Element:")
        SettingCombo { key: "element"; model: [page.i18nc("element shape", "Bar"), page.i18nc("element shape", "Blocks")] }
    }
    FormRow {
        label: page.i18n("Block, px:")
        visible: page.blocks
        SettingSpin { key: "blockSize"; from: 2; to: 40 }
    }
    FormRow {
        label: page.i18n("Block gap, px:")
        visible: page.blocks
        SettingSpin { key: "blockGap"; from: 0; to: 40 }
    }
    FormRow {
        label: page.i18n("Ends:")
        SettingCheck { key: "rounded"; text: page.i18nc("bar ends", "rounded") }
    }
    FormRow {
        label: page.i18n("Colour:")
        SettingColor { key: "color"; fallback: "#C8CCD4" }
    }
    FormRow {
        label: page.i18n("High-frequency colour:")
        // Empty means "the one colour": the box switches between empty and a copy of it.
        SettingColor {
            id: highColor
            key: "colorHigh"
            fallback: ""
            enabled: page.str("colorHigh", "").length > 0
        }
        CheckBox {
            text: page.i18nc("high-frequency colour", "custom")
            checked: page.str("colorHigh", "").length > 0
            onToggled: page.set("colorHigh", checked ? page.str("color", "#C8CCD4") : "")
        }
    }
    FormRow {
        label: page.i18n("Opacity, %:")
        SettingSpin { key: "opacityPercent"; from: 10; to: 100; stepSize: 5 }
    }
    FormRow {
        label: page.i18n("Circle:")
        visible: page.ring
        SettingCheck { key: "guide"; text: page.i18n("a thin guide under the bars") }
    }

    Section { title: page.i18nc("settings section", "Behaviour") }

    FormRow {
        label: page.i18n("Data frames per second:")
        SettingSpin { key: "dataRate"; from: 5; to: 60; stepSize: 5 }
    }
    FormRow {
        label: page.i18n("Smoothing, ms:")
        SettingSpin { key: "smoothMs"; from: 0; to: 400; stepSize: 10 }
    }
    FormRow {
        label: page.i18n("Mouse:")
        SettingCheck { key: "clickThrough"; text: page.i18n("let clicks through to the desktop") }
    }
    Hint {
        text: page.i18nc("Windows: the mouse hint", "While clicks go through, both mouse buttons land on the desktop.\nThe way back is the tray icon's menu, or the widget's own menu:\nthe right button on it while clicks are not passing.")
    }

    Section { title: page.i18nc("settings section", "Silence") }

    FormRow {
        label: page.i18n("In silence:")
        SettingCheck { key: "hideWhenQuiet"; text: page.i18n("dissolve the ring") }
    }
    FormRow {
        label: page.i18n("Silence threshold, %:")
        enabled: page.quiet
        SettingSpin { key: "quietThreshold"; from: 0; to: 50 }
    }
    FormRow {
        label: page.i18n("Wait before vanishing, ms:")
        enabled: page.quiet
        SettingSpin { key: "quietDelayMs"; from: 100; to: 10000; stepSize: 100 }
    }
    FormRow {
        label: page.i18n("Fade in and out, ms:")
        enabled: page.quiet
        SettingSpin { key: "fadeMs"; from: 0; to: 3000; stepSize: 50 }
    }
    FormRow {
        label: page.i18n("Polls per second in silence:")
        enabled: page.quiet
        SettingSpin { key: "idleRate"; from: 1; to: 30 }
    }
    Hint {
        text: page.i18n("The bars grow out of the ring itself, so a “length at silence” of 0\nmakes them appear out of literally nothing.")
    }
    FormRow {
        label: page.i18n("Relay port:")
        SettingSpin { key: "relayPort"; from: 1024; to: 65535 }
    }
    FormRow {
        label: page.i18n("Source:")
        Label {
            Layout.fillWidth: true
            text: page.i18nc("Windows: where the visualizer's data comes from", "the spectrum is computed by the plaintop service from what the default output\nplays (WASAPI loopback); with the port left at 8788 the host asks the service's own")
            opacity: 0.7
            font.pointSize: Math.max(7, Application.font.pointSize - 1)
            wrapMode: Text.Wrap
        }
    }
}
