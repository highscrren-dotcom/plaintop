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
    property alias cfg_reminders: remindBox.checked
    property alias cfg_remindLead: leadField.value
    property alias cfg_remindHour: hourField.text
    property alias cfg_remindEvents: eventsBox.checked
    property alias cfg_remindMissed: missedField.value
    property alias cfg_snoozeMinutes: snoozeField.value
    property alias cfg_remindSystem: systemBox.checked
    // "" none, a built-in sound's name ("chime"), or a file's path.
    property string cfg_remindSound: ""

    // Colours are stored as strings, while ColorButton works with a color: converted in place.
    property string cfg_colorNote: "#8FB6E0"
    property string cfg_colorPaper: "#141820"

    readonly property string script: Qt.resolvedUrl("../code/notes.py").toString().replace("file://", "")
    // The sounds in the package (contents/sounds, made by calendar/sounds.py), in the
    // order of the list after "none"; "your own file" ends it.
    readonly property var builtinSounds: ["bell", "blip", "chime", "pager", "tick"]
    // "Your own file" picked while its path is still empty.
    property bool ownSound: false
    function soundFile(v) {
        const name = String(v || "").trim()
        if (builtinSounds.indexOf(name) >= 0)
            return Qt.resolvedUrl("../sounds/" + name + ".wav").toString().replace("file://", "")
        return name.replace(/^file:\/\//, "")
    }
    function shQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    P5Support.DataSource {
        id: player
        engine: "executable"
        interval: 0
        onNewData: function(source, data) { disconnectSource(source) }
    }
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

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18nc("settings section", "Reminders") }

        CheckBox {
            id: remindBox
            Kirigami.FormData.label: i18n("Reminders:")
            enabled: notesBox.checked
            text: i18n("a sheet by the day's cell when an entry is due")
        }

        Label {
            text: i18n("A note whose first line starts with a time — “14:30 Dentist” — becomes a timed\nentry and rings before it; “!Buy milk” stays a note and rings at the hour below.\nThe accounts' events ring by their own alarms. Both reach the phone through the\naccount. The sheet offers to snooze, to put it off till tomorrow, or done.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        SpinBox {
            id: leadField
            Kirigami.FormData.label: i18n("Before a timed entry, min:")
            enabled: notesBox.checked && remindBox.checked
            from: -1
            to: 1440
            textFromValue: function(value) { return value < 0 ? i18nc("no reminder before timed notes", "none") : String(value) }
            valueFromText: function(text) { const n = parseInt(text); return isNaN(n) ? -1 : n }
        }

        TextField {
            id: hourField
            Kirigami.FormData.label: i18n("“!” notes ring at:")
            enabled: notesBox.checked && remindBox.checked
            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
            placeholderText: "09:00"
            maximumLength: 5
        }

        CheckBox {
            id: eventsBox
            Kirigami.FormData.label: i18n("Events without an alarm:")
            enabled: notesBox.checked && remindBox.checked
            text: i18n("ring before them too, as for a timed note")
        }

        SpinBox {
            id: snoozeField
            Kirigami.FormData.label: i18n("Snooze for, min:")
            enabled: notesBox.checked && remindBox.checked
            from: 1
            to: 180
        }

        SpinBox {
            id: missedField
            Kirigami.FormData.label: i18n("Show missed ones from the last, h:")
            enabled: notesBox.checked && remindBox.checked
            from: 0
            to: 168
        }

        Label {
            text: i18n("While the machine was off: alarms older than this are dropped quietly.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        CheckBox {
            id: systemBox
            Kirigami.FormData.label: i18n("System notification:")
            enabled: notesBox.checked && remindBox.checked
            text: i18n("also through notify-send — in Plasma's history, silenced by Do Not Disturb")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Sound:")
            enabled: notesBox.checked && remindBox.checked
            ComboBox {
                id: soundBox
                model: [i18nc("reminder sound", "none"), i18nc("reminder sound: a terminal's bell", "bell"),
                        i18nc("reminder sound: two short beeps", "blip"), i18nc("reminder sound: two tones ringing out", "chime"),
                        i18nc("reminder sound: three quick beeps", "pager"), i18nc("reminder sound: two dry ticks", "tick"),
                        i18nc("reminder sound", "your own file…")]
                readonly property int own: model.length - 1
                // The setting drives the list: a built-in name picks its line, any other
                // text is a file of your own.
                currentIndex: {
                    const v = String(page.cfg_remindSound).trim()
                    if (page.ownSound) return own
                    if (v.length === 0) return 0
                    const i = page.builtinSounds.indexOf(v)
                    return i >= 0 ? i + 1 : own
                }
                onActivated: index => {
                    page.ownSound = index === own
                    if (index === 0) page.cfg_remindSound = ""
                    else if (index < own) page.cfg_remindSound = page.builtinSounds[index - 1]
                    else page.cfg_remindSound = fileField.text.trim()
                }
            }
            Button {
                text: i18nc("play the chosen reminder sound", "Listen")
                icon.name: "media-playback-start"
                enabled: page.soundFile(page.cfg_remindSound).trim().length > 0
                onClicked: {
                    const f = page.shQuote(page.soundFile(page.cfg_remindSound).trim())
                    player.connectSource("(pw-play " + f + " || paplay " + f + ") >/dev/null 2>&1 # " + Date.now())
                }
            }
        }

        TextField {
            id: fileField
            Kirigami.FormData.label: i18n("Sound file:")
            visible: soundBox.currentIndex === soundBox.own
            enabled: notesBox.checked && remindBox.checked
            Layout.fillWidth: true
            text: page.builtinSounds.indexOf(String(page.cfg_remindSound).trim()) < 0 ? String(page.cfg_remindSound).trim() : ""
            placeholderText: "/usr/share/sounds/freedesktop/stereo/message.oga"
            onTextEdited: page.cfg_remindSound = text.trim()
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
