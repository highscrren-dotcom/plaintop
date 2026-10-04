import QtQuick
import QtQuick.Layouts

// The monitor's General page: monitor/package/contents/ui/configGeneral.qml, row for row.
// Two hints are Windows' own: the mouse's (the way back is not the desktop's edit mode
// here) and the placeholders of the terminal and the editor, which name the Windows
// defaults of settings_store.py.
SettingsPage {
    id: page

    FormRow {
        label: page.i18n("Font:")
        SettingText { key: "fontFamily"; Layout.fillWidth: true }
    }
    FormRow {
        label: page.i18nc("font size", "Size:")
        SettingSpin { key: "fontSize"; from: 6; to: 32 }
    }
    FormRow {
        label: page.i18n("Left padding, px:")
        SettingSpin { key: "padLeft"; from: 0; to: 500; stepSize: 4 }
    }
    FormRow {
        label: page.i18n("Top padding, px:")
        SettingSpin { key: "padTop"; from: 0; to: 500; stepSize: 4 }
    }
    FormRow {
        label: page.i18n("Width, px:")
        SettingSpin { key: "widgetWidth"; from: 100; to: 2000; stepSize: 8 }
    }
    FormRow {
        label: page.i18n("Height, px:")
        SettingSpin { key: "widgetHeight"; from: 100; to: 2000; stepSize: 8 }
    }

    FormRow {
        label: page.i18nc("palette: colour of", "Main text:")
        SettingColor { key: "colorFg"; fallback: "#C8CCD4" }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Header and clock:")
        SettingColor { key: "colorAccent"; fallback: "#E05561" }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Secondary:")
        SettingColor { key: "colorDim"; fallback: "#6B7280" }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Values:")
        SettingColor { key: "colorValue"; fallback: "#8FB6E0" }
    }

    FormRow {
        label: page.i18n("Mouse:")
        SettingCheck { key: "clickThrough"; text: page.i18n("let clicks through to the desktop") }
    }
    Hint {
        text: page.i18nc("Windows: the monitor's mouse hint", "While clicks go through, both buttons land on the desktop everywhere but on\nthe active lines, which keep theirs. With those off too, the way back is the\ntray icon's menu, or the widget's own menu: the right button on it while\nclicks are not passing.")
    }

    FormRow {
        label: page.i18n("Active lines:")
        SettingCheck { key: "actions"; text: page.i18n("a click runs the line's action, the right button lists them") }
    }
    Hint {
        text: page.i18n("A bar opens System Monitor, a disk its folder, a unit its status, a process\nasks before it is ended, the header opens these settings. The Blocks page\nswitches a block's lines off or gives them a command of your own.")
    }

    FormRow {
        label: page.i18n("Terminal:")
        SettingText { key: "terminal"; Layout.fillWidth: true; placeholderText: "wt" }
    }
    FormRow {
        label: page.i18n("Editor:")
        SettingText { key: "editor"; Layout.fillWidth: true; placeholderText: "notepad" }
    }
    FormRow {
        label: page.i18n("Menu frame:")
        SettingText { key: "frame"; implicitWidth: 150; maximumLength: 8; placeholderText: "┌─┐│└┘├┤" }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Menu paper:")
        SettingColor { key: "colorPaper"; fallback: "#141820" }
    }
    FormRow {
        label: page.i18n("Paper opacity, %:")
        SettingSpin { key: "paperOpacity"; from: 0; to: 100 }
    }

    Section { title: page.i18nc("settings section", "Lines") }

    FormRow {
        label: page.i18n("Bar width, characters:")
        SettingSpin { key: "barWidth"; from: 4; to: 60 }
    }
    FormRow {
        label: page.i18n("Bar characters:")
        SettingText { key: "barFill"; implicitWidth: 60; maximumLength: 2; placeholderText: "/" }
        SettingText {
            key: "barEmpty"
            implicitWidth: 60
            maximumLength: 2
            placeholderText: page.i18nc("placeholder: the empty part of a bar is a space", "space")
        }
    }
    Hint { text: page.i18n("The filled and the empty part of a bar. Empty fields mean the slash and a space.") }

    FormRow {
        label: page.i18n("Separator:")
        SettingText { key: "separatorChar"; implicitWidth: 60; maximumLength: 2; placeholderText: "-" }
        SettingSpin { key: "separatorWidth"; from: 1; to: 200 }
    }
    FormRow {
        label: page.i18n("Sparkline glyphs:")
        SettingText { key: "sparkGlyphs"; Layout.fillWidth: true; placeholderText: "▁▂▃▄▅▆▇█" }
    }
    Hint {
        text: page.i18n("From lowest to highest, for the “History” parameter of the bar blocks.\nAny run of characters works, say “ .:-=+*#”.")
    }
    FormRow {
        label: page.i18n("Second column at, px:")
        SettingSpin { key: "secondColumn"; from: 0; to: 2000; stepSize: 8 }
    }
    Hint {
        text: page.i18n("Where the second column starts; 0 is half the width. A block goes\nthere by its “Column” field on the Blocks page.")
    }

    Section { title: page.i18nc("settings section", "Updates") }

    FormRow {
        label: page.i18n("Interval, ms:")
        SettingSpin { key: "updateInterval"; from: 200; to: 10000; stepSize: 100 }
    }
    FormRow {
        label: page.i18n("Top processes, every … s:")
        SettingSpin { key: "processInterval"; from: 2; to: 60 }
    }
    Hint {
        text: page.i18n("The process list is the most expensive thing collected: every 2 s\nabout 3% of a core, every 10 s about 1.3%")
    }
}
