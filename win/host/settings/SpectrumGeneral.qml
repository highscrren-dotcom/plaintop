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

    // ── the performance tiers ─────────────────────────────────────────────────
    // What one click writes into the four knobs below. Measured on the machine the budget
    // was taken on (this desk, 370 processes): the ring alone costs about 25% of a core on
    // the smooth tier, 12% on the balanced one and 5% on the quiet one, and the service's
    // capture follows "Data frames per second" — so a lower tier is cheaper end to end than
    // the ring's own figure alone. The numbers are free to be edited afterwards: that is
    // what "Custom" is, and the combo says so by itself.
    readonly property var presets: ({
        "quiet": {"dataRate": 10, "idleRate": 1, "smoothMs": 0, "bars": 96},
        "balanced": {"dataRate": 20, "idleRate": 2, "smoothMs": 0, "bars": 160},
        "smooth": {"dataRate": 30, "idleRate": 4, "smoothMs": 70, "bars": 160}
    })
    readonly property var presetText: ({
        "quiet": page.i18n("Quiet — 10 frames a second, 96 bars, no smoothing"),
        "balanced": page.i18n("Balanced — 20 frames a second, 160 bars, no smoothing"),
        "smooth": page.i18n("Smooth — 30 frames a second, 160 bars, smoothed"),
        "custom": page.i18n("Custom — the numbers below")
    })
    // Which tier the numbers add up to now: a hand-edited number makes it "Custom" by
    // itself, so the combo never claims a tier the settings do not hold.
    readonly property string profile: {
        const id = page.str("renderProfile", "balanced")
        const p = presets[id]
        if (p === undefined) return "custom"
        return (num("dataRate", 20) === p.dataRate && num("idleRate", 2) === p.idleRate
                && num("smoothMs", 0) === p.smoothMs && num("bars", 160) === p.bars) ? id : "custom"
    }
    function applyPreset(id) {
        page.set("renderProfile", id)
        const p = presets[id]
        if (p !== undefined) page.save(p)
    }

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
        label: page.i18n("Performance:")
        ComboBox {
            id: presetBox
            Layout.fillWidth: true
            textRole: "text"
            valueRole: "id"
            model: {
                const out = []
                for (const k of ["quiet", "balanced", "smooth", "custom"])
                    out.push({ "id": k, "text": page.presetText[k] })
                return out
            }
            currentIndex: {
                for (let i = 0; i < model.length; i++)
                    if (model[i].id === page.profile) return i
                return 0
            }
            onActivated: index => page.applyPreset(model[index].id)
            // Registered under the key it writes first, so the stand can drive it as it drives
            // every other control.
            Component.onCompleted: page.register("renderProfile", presetBox)
        }
    }
    Hint {
        text: page.i18n("One click writes the four numbers below. The smoothing animation is what the\nring costs most — about a quarter of one core on the machine the idle budget was\ntaken on, half that without it — and “Data frames a second” is what the service's own\ncapture follows. The bars' count is the other lever. Pick by how it looks and by the\nfan.")
    }

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
