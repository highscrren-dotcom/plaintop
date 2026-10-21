import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import plaintop

// Notes and the sticker: calendar/package/contents/ui/configNotes.qml. The account for
// the widget's own notes is picked from what the script knows — "local" and the accounts
// of the Accounts page — asked through the service's /notes instead of the executable
// engine; the reminder sound is played by the service (/notify), which is what the
// Windows host does for a reminder too. Two hints are Windows' own: the local notes'
// folder and the system notification.
SettingsPage {
    id: page

    readonly property bool notesOn: flag("notes", true)
    readonly property bool remindersOn: notesOn && flag("reminders", true)

    // The sounds in the package (contents/sounds, made by calendar/sounds.py), in the
    // order of the list after "none"; "your own file" ends it.
    readonly property var builtinSounds: ["bell", "blip", "chime", "pager", "tick"]
    // "Your own file" picked while its path is still empty.
    property bool ownSound: false

    property var accountIds: ["local"]
    property var accountNames: [page.i18nc("the account of the widget's own notes: a folder of files", "local — this machine")]

    function loadAccounts() {
        Service.postJson("/notes", { args: ["accounts"] }, function(d) {
            if (!d || d.stdout === undefined)
                return
            try {
                const list = JSON.parse(String(d.stdout))
                if (!Array.isArray(list))
                    return
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
                // No accounts yet: local stays the one choice.
            }
        }, 60000)
    }
    Component.onCompleted: loadAccounts()

    function listen() {
        const name = str("remindSound", "").trim()
        if (name.length === 0)
            return
        Service.postJson("/notify", { sound: builtinSounds.indexOf(name) >= 0 ? "builtin:" + name : name })
    }

    Section { title: page.i18nc("settings section", "Notes") }

    FormRow {
        label: page.i18n("Notes:")
        SettingCheck { key: "notes"; text: page.i18n("mark the days that have entries, open a sticker on click") }
    }
    Hint {
        text: page.i18n("A click on a day opens its sticker: the day's events and tasks from the accounts,\nand a note of yours — the first line is its title. Off, the calendar is the plain grid\nand takes no clicks at all.")
    }
    FormRow {
        label: page.i18n("Write notes to:")
        enabled: page.notesOn
        SettingCombo {
            key: "noteAccount"
            Layout.fillWidth: true
            values: page.accountIds
            model: page.accountNames
        }
    }
    Hint {
        text: page.i18nc("Windows: where the local notes are kept", "“local” keeps them as .ics files in %APPDATA%\\plaincalendar\\notes;\nan account from the Accounts page sends them to that calendar as all-day events.")
    }
    FormRow {
        label: page.i18n("Upcoming lines:")
        enabled: page.notesOn
        SettingSpin { key: "upcoming"; from: 0; to: 10 }
    }
    Hint { text: page.i18n("The next entries, one per line under the months; 0 hides them.") }
    FormRow {
        label: page.i18n("Fetch the accounts every, min:")
        enabled: page.notesOn
        SettingSpin { key: "syncMinutes"; from: 1; to: 180 }
    }

    Section { title: page.i18nc("settings section", "Reminders") }

    FormRow {
        label: page.i18n("Reminders:")
        enabled: page.notesOn
        SettingCheck { key: "reminders"; text: page.i18n("a sheet by the day's cell when an entry is due") }
    }
    Hint {
        text: page.i18n("A note whose first line starts with a time — “14:30 Dentist” — becomes a timed\nentry and rings before it; “!Buy milk” stays a note and rings at the hour below.\nThe accounts' events ring by their own alarms. Both reach the phone through the\naccount. The sheet offers to snooze, to put it off till tomorrow, or done.")
    }
    FormRow {
        label: page.i18n("Before a timed entry, min:")
        enabled: page.remindersOn
        SettingSpin {
            key: "remindLead"
            from: -1
            to: 1440
            textFromValue: function(value) { return value < 0 ? page.i18nc("no reminder before timed notes", "none") : String(value) }
            valueFromText: function(text) { const n = parseInt(text); return isNaN(n) ? -1 : n }
        }
    }
    FormRow {
        label: page.i18n("“!” notes ring at:")
        enabled: page.remindersOn
        SettingText { key: "remindHour"; implicitWidth: 90; placeholderText: "09:00"; maximumLength: 5 }
    }
    FormRow {
        label: page.i18n("Events without an alarm:")
        enabled: page.remindersOn
        SettingCheck { key: "remindEvents"; text: page.i18n("ring before them too, as for a timed note") }
    }
    FormRow {
        label: page.i18n("Snooze for, min:")
        enabled: page.remindersOn
        SettingSpin { key: "snoozeMinutes"; from: 1; to: 180 }
    }
    FormRow {
        label: page.i18n("Show missed ones from the last, h:")
        enabled: page.remindersOn
        SettingSpin { key: "remindMissed"; from: 0; to: 168 }
    }
    Hint { text: page.i18n("While the machine was off: alarms older than this are dropped quietly.") }
    FormRow {
        label: page.i18n("System notification:")
        enabled: page.remindersOn
        SettingCheck {
            key: "remindSystem"
            text: page.i18nc("Windows: the reminder's system notification", "also as a Windows notification — in the notification centre, silenced by focus assist")
        }
    }
    FormRow {
        label: page.i18n("Sound:")
        enabled: page.remindersOn
        ComboBox {
            id: soundBox
            model: [page.i18nc("reminder sound", "none"), page.i18nc("reminder sound: a terminal's bell", "bell"),
                    page.i18nc("reminder sound: two short beeps", "blip"), page.i18nc("reminder sound: two tones ringing out", "chime"),
                    page.i18nc("reminder sound: three quick beeps", "pager"), page.i18nc("reminder sound: two dry ticks", "tick"),
                    page.i18nc("reminder sound", "your own file…")]
            readonly property int own: 6
            // The setting drives the list: a built-in name picks its line, any other
            // text is a file of your own.
            currentIndex: {
                const v = page.str("remindSound", "").trim()
                if (page.ownSound) return own
                if (v.length === 0) return 0
                const i = page.builtinSounds.indexOf(v)
                return i >= 0 ? i + 1 : own
            }
            onActivated: index => {
                page.ownSound = index === own
                if (index === 0) page.set("remindSound", "")
                else if (index < own) page.set("remindSound", page.builtinSounds[index - 1])
                else page.set("remindSound", fileField.text.trim())
            }
        }
        Button {
            text: page.i18nc("play the chosen reminder sound", "Listen")
            enabled: page.str("remindSound", "").trim().length > 0
            onClicked: page.listen()
        }
    }
    FormRow {
        label: page.i18n("Sound file:")
        visible: soundBox.currentIndex === soundBox.own
        enabled: page.remindersOn
        SettingText {
            id: fileField
            key: "remindSound"
            Layout.fillWidth: true
            placeholderText: "C:\\Windows\\Media\\Alarm01.wav"
        }
    }

    Section { title: page.i18nc("settings section", "Sticker") }

    FormRow {
        label: page.i18n("Frame characters:")
        enabled: page.notesOn
        SettingText { key: "frame"; implicitWidth: 150; placeholderText: "┌─┐│└┘├┤"; maximumLength: 8 }
    }
    Hint {
        text: page.i18n("Eight characters: the corners, the horizontal, the vertical and the two\njunctions of a separator — “┌─┐│└┘├┤”, or “+-+|+++” in plain ASCII.")
    }
    FormRow {
        label: page.i18n("Sticker width, characters:")
        enabled: page.notesOn
        SettingSpin { key: "stickerColumns"; from: 20; to: 100 }
    }
    FormRow {
        label: page.i18n("Opening:")
        enabled: page.notesOn
        SettingCombo {
            key: "stickerAnimation"
            model: [page.i18nc("sticker animation", "at once"), page.i18nc("sticker animation", "fade in"), page.i18nc("sticker animation", "unfold line by line")]
        }
    }
    FormRow {
        label: page.i18n("Sheet opacity, %:")
        enabled: page.notesOn
        SettingSpin { key: "paperOpacity"; from: 0; to: 100; stepSize: 5 }
    }

    Section { title: page.i18nc("settings section", "Palette") }

    FormRow {
        label: page.i18nc("palette: colour of", "Days with entries:")
        SettingColor { key: "colorNote"; fallback: "#8FB6E0" }
    }
    FormRow {
        label: page.i18nc("palette: colour of", "Sticker sheet:")
        SettingColor { key: "colorPaper"; fallback: "#141820" }
    }
}
