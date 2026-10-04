import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls
import org.kde.plasma.plasma5support as P5Support

// Notes and the sticker. The account for the widget's own notes is picked from what the
// script knows: "local" and the accounts of the Accounts page.
KCM.SimpleKCM {
    id: page

    property alias cfg_notes: notesBox.checked
    property alias cfg_upcoming: upcomingField.value
    property alias cfg_syncMinutes: syncField.value
    property alias cfg_paperOpacity: opacityField.value
    property alias cfg_frame: frameField.text
    property alias cfg_stickerColumns: columnsField.value
    property alias cfg_stickerAnimation: animationBox.currentIndex
    property string cfg_noteAccount: "local"

    // Colours are stored as strings, while ColorButton works with a color: converted in place.
    property string cfg_colorNote: "#8FB6E0"
    property string cfg_colorPaper: "#141820"

    readonly property string script: Qt.resolvedUrl("../code/notes.py").toString().replace("file://", "")
    property var accountIds: ["local"]
    property var accountNames: [i18nc("the account of the widget's own notes: a folder of files", "local — this machine")]

    P5Support.DataSource {
        engine: "executable"
        interval: 0
        connectedSources: ["python3 '" + page.script + "' accounts"]
        onNewData: function(source, data) {
            disconnectSource(source)
            try {
                const list = JSON.parse(String(data.stdout))
                const ids = ["local"], names = [page.accountNames[0]]
                for (let i = 0; i < list.length; i++) {
                    if (list[i].kind === "ics")
                        continue                       // a feed is read-only
                    ids.push(String(list[i].id))
                    names.push(String(list[i].name || list[i].id))
                }
                page.accountIds = ids
                page.accountNames = names
            } catch (e) {
                // No accounts yet, or the script is missing: local stays the one choice.
            }
        }
    }

    function accountIndex() {
        for (let i = 0; i < accountIds.length; i++)
            if (accountIds[i] === cfg_noteAccount)
                return i
        return 0
    }

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Notes") }

        CheckBox {
            id: notesBox
            Kirigami.FormData.label: i18n("Notes:")
            text: i18n("mark the days that have entries, open a sticker on click")
        }

        Label {
            text: i18n("A click on a day opens its sticker: the day's events and tasks from the accounts,\nand a note of yours — the first line is its title. Off, the calendar is the plain grid\nand takes no clicks at all.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        ComboBox {
            id: accountBox
            Kirigami.FormData.label: i18n("Write notes to:")
            enabled: notesBox.checked
            model: page.accountNames
            currentIndex: page.accountIndex()
            onActivated: page.cfg_noteAccount = page.accountIds[currentIndex]
        }

        Label {
            text: i18n("“local” keeps them as .ics files in ~/.local/share/plaincalendar/notes;\nan account from the Accounts page sends them to that calendar as all-day events.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        SpinBox {
            id: upcomingField
            Kirigami.FormData.label: i18n("Upcoming lines:")
            enabled: notesBox.checked
            from: 0
            to: 10
        }

        Label {
            text: i18n("The next entries, one per line under the months; 0 hides them.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        SpinBox {
            id: syncField
            Kirigami.FormData.label: i18n("Fetch the accounts every, min:")
            enabled: notesBox.checked
            from: 1
            to: 180
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Sticker") }

        TextField {
            id: frameField
            Kirigami.FormData.label: i18n("Frame characters:")
            enabled: notesBox.checked
            placeholderText: "┌─┐│└┘├┤"
            maximumLength: 8
        }

        Label {
            text: i18n("Eight characters: the corners, the horizontal, the vertical and the two\njunctions of a separator — “┌─┐│└┘├┤”, or “+-+|+++” in plain ASCII.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        SpinBox {
            id: columnsField
            Kirigami.FormData.label: i18n("Sticker width, characters:")
            enabled: notesBox.checked
            from: 20
            to: 100
        }

        ComboBox {
            id: animationBox
            Kirigami.FormData.label: i18n("Opening:")
            enabled: notesBox.checked
            model: [i18nc("sticker animation", "at once"), i18nc("sticker animation", "fade in"), i18nc("sticker animation", "unfold line by line")]
        }

        SpinBox {
            id: opacityField
            Kirigami.FormData.label: i18n("Sheet opacity, %:")
            enabled: notesBox.checked
            from: 0
            to: 100
            stepSize: 5
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Palette") }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Days with entries:")
            color: page.cfg_colorNote
            onColorChanged: page.cfg_colorNote = color.toString()
        }

        KQuickControls.ColorButton {
            Kirigami.FormData.label: i18nc("palette: colour of", "Sticker sheet:")
            color: page.cfg_colorPaper
            onColorChanged: page.cfg_colorPaper = color.toString()
        }
    }
}
