pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import plaintop

// The accounts the calendar reads — and the one it writes to: calendar/package/contents/
// ui/configAccounts.qml over the service's /notes. As many as you like, none by default:
// the list is whatever notes.py keeps in its own file (%APPDATA%\plaincalendar\accounts.json);
// this page only talks to the script — `accounts`, `account-save B64JSON`, `account-remove
// ID`, `check ID` — with the arguments as a JSON array, nothing shell-quoted.
//
// The secrets travel inside the base64 JSON. The Plasma page left them in inbox.ini
// because an executable-engine command line is readable by anyone on the machine
// (/proc/*/cmdline); a POST body to 127.0.0.1 carrying the service's token is not a
// command line, and notes.py's account-save keeps a password it finds in the JSON — the
// inbox only adds to it — so there is nothing to stash here.
SettingsPage {
    id: page

    property var accounts: []            // as the script lists them, secrets left out
    property int selected: -1
    property string status: ""
    property bool failed: false
    property var calendars: []           // from the last check: [{href, name}]

    // Presets and their URLs.
    readonly property var presets: [
        { name: page.i18nc("account preset", "Yandex (CalDAV)"), kind: "caldav", url: "https://caldav.yandex.ru/" },
        { name: page.i18nc("account preset", "iCloud (CalDAV)"), kind: "caldav", url: "https://caldav.icloud.com/" },
        { name: page.i18nc("account preset", "Google (CalDAV, OAuth)"), kind: "google", url: "https://apidata.googleusercontent.com/caldav/v2/" },
        { name: page.i18nc("account preset", "any CalDAV server"), kind: "caldav", url: "" },
        { name: page.i18nc("account preset", "ICS link, read-only"), kind: "ics", url: "" }
    ]

    // The form's state — the plasmoid's aliases on its FormLayout.
    property alias accId: idField.text
    property alias accName: nameField.text
    property string kind: "caldav"
    property alias server: urlField.text
    property alias login: userField.text
    property alias password: passwordField.text
    property alias calendar: calendarField.text
    property alias clientId: clientIdField.text
    property alias clientSecret: clientSecretField.text
    property bool hasPassword: false
    property bool signedIn: false

    // One call of notes.py through the service: cb(stdout), "" when nothing came back.
    function run(args, cb) {
        Service.postJson("/notes", { args: args }, function(d) {
            cb(d && d.stdout !== undefined ? String(d.stdout) : "")
        }, 60000)
    }

    // Qt.btoa encodes the string as UTF-8 itself: wrapping it in
    // unescape(encodeURIComponent()) would encode the bytes twice.
    function b64(obj) {
        return Qt.btoa(JSON.stringify(obj))
    }

    function reload() {
        run(["accounts"], function(out) {
            try {
                const list = JSON.parse(out)
                page.accounts = Array.isArray(list) ? list : []
            } catch (e) {
                page.accounts = []
                page.status = page.i18n("The script did not answer: %1", out.length > 0 ? out
                                   : page.i18nc("Windows: /notes gave nothing back", "the service does not answer"))
                page.failed = true
            }
        })
    }

    Component.onCompleted: reload()

    function clearForm() {
        accId = ""; accName = ""; kind = "caldav"; server = ""; login = ""; password = ""; calendar = ""
        clientId = ""; clientSecret = ""; hasPassword = false; signedIn = false
        presetBox.currentIndex = 0
    }

    function pick(i) {
        selected = i
        calendars = []
        status = ""
        failed = false
        if (i < 0 || i >= accounts.length) {
            clearForm()
            return
        }
        const a = accounts[i]
        accId = String(a.id || "")
        accName = String(a.name || "")
        kind = String(a.kind || "caldav")
        server = String(a.url || "")
        login = String(a.user || "")
        password = ""
        calendar = String(a.calendar || "")
        clientId = String(a.client_id || "")
        clientSecret = ""
        hasPassword = a.has_password === true
        signedIn = a.signed_in === true
    }

    // The account as the form has it, secrets included (see the note at the top).
    function fromForm() {
        return { id: accId.trim(), name: accName.trim() || accId.trim(), kind: kind,
                 url: server.trim(), user: login.trim(), password: password,
                 calendar: calendar.trim(), client_id: clientId.trim(), client_secret: clientSecret }
    }

    function saveAccount() {
        if (accId.trim().length === 0) {
            status = page.i18n("The account needs an id — a short word, say “yandex”.")
            failed = true
            return
        }
        const a = fromForm()
        run(["account-save", b64(a)], function(out) {
            page.answer(out, function(list) {
                page.accounts = list
                for (let i = 0; i < list.length; i++)
                    if (list[i].id === a.id)
                        page.pick(i)
                // After pick(), which clears the status.
                page.status = page.i18n("Saved.")
            })
        })
    }

    function removeAccount() {
        if (selected < 0) return
        run(["account-remove", String(accounts[selected].id)], function(out) {
            page.answer(out, function(list) {
                page.accounts = list
                page.pick(-1)
                page.status = page.i18n("Removed.")
            })
        })
    }

    // Saves first, so the check runs with what is in the form, then asks the server.
    function checkAccount() {
        if (accId.trim().length === 0) return
        const a = fromForm()
        status = page.i18n("Asking the server…")
        failed = false
        run(["account-save", b64(a)], function(out) {
            page.answer(out, function(list) {
                page.accounts = list
                page.run(["check", a.id], function(out2) {
                    page.answer(out2, function(found) {
                        page.calendars = found.calendars || []
                        if (a.kind === "ics")
                            page.status = page.i18np("The link answers: %1 entry.", "The link answers: %1 entries.", found.entries || 0)
                        else if (page.calendars.length === 0)
                            page.status = page.i18n("The server answers, but lists no calendar.")
                        else
                            page.status = page.i18np("The server answers: %1 calendar — pick one below, or leave the field empty for the first.",
                                                "The server answers: %1 calendars — pick one below, or leave the field empty for the first.",
                                                page.calendars.length)
                        for (let i = 0; i < list.length; i++)
                            if (list[i].id === a.id) {
                                page.selected = i
                                page.hasPassword = list[i].has_password === true
                                page.signedIn = list[i].signed_in === true
                            }
                    })
                })
            })
        })
    }

    // The script's answer: a JSON document, or {"ok": false, "error": …}.
    function answer(out, then) {
        let parsed
        try {
            parsed = JSON.parse(out)
        } catch (e) {
            status = page.i18n("The script did not answer: %1", out)
            failed = true
            return
        }
        if (parsed && parsed.ok === false) {
            status = String(parsed.error || "")
            failed = true
            return
        }
        failed = false
        then(parsed)
    }

    Hint {
        indent: false
        text: page.i18n("Calendars the widget reads, and the one it writes your notes to (chosen on the Notes page). Yandex and iCloud take an app password from your account's settings; Google signs in once through the browser.")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Frame {
            Layout.fillWidth: true
            implicitHeight: 150
            padding: 1

            ListView {
                id: list
                anchors.fill: parent
                model: page.accounts.length
                clip: true

                delegate: ItemDelegate {
                    id: row
                    required property int index
                    readonly property var a: page.accounts[index] || ({})
                    width: ListView.view.width
                    highlighted: index === page.selected
                    onClicked: page.pick(index)
                    contentItem: ColumnLayout {
                        spacing: 0
                        Label { text: String(row.a.name || row.a.id || "") }
                        Label {
                            text: String(row.a.id || "") + " · " + String(row.a.kind || "")
                                  + (row.a.kind === "google"
                                     ? (row.a.signed_in ? "  · " + page.i18nc("Google account state", "signed in") : "  · " + page.i18nc("Google account state", "not signed in yet"))
                                     : (row.a.kind === "caldav" && !row.a.has_password ? "  · " + page.i18nc("CalDAV account state", "no password") : ""))
                            opacity: 0.6
                            font.pointSize: Math.max(7, Application.font.pointSize - 1)
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: false

            Button {
                text: page.i18n("New")
                Layout.fillWidth: true
                onClicked: page.pick(-1)
            }
            Button {
                text: page.i18n("Remove")
                Layout.fillWidth: true
                enabled: page.selected >= 0
                onClicked: page.removeAccount()
            }
        }
    }

    FormRow {
        label: page.i18n("Provider:")
        ComboBox {
            id: presetBox
            Layout.fillWidth: true
            model: page.presets.map(p => p.name)
            onActivated: {
                const p = page.presets[currentIndex]
                page.kind = p.kind
                if (p.url.length > 0 || page.server.length === 0)
                    page.server = p.url
            }
        }
    }
    FormRow {
        label: page.i18n("Id:")
        TextField {
            id: idField
            placeholderText: page.i18nc("placeholder for an account id", "yandex")
            enabled: page.selected < 0
        }
    }
    FormRow {
        label: page.i18n("Name:")
        TextField {
            id: nameField
            Layout.fillWidth: true
            placeholderText: page.i18nc("placeholder for an account's name", "as it is shown on the sticker")
        }
    }
    FormRow {
        label: page.kind === "ics" ? page.i18n("Link:") : page.i18n("Server:")
        TextField {
            id: urlField
            Layout.fillWidth: true
            placeholderText: page.kind === "ics" ? "https://…/basic.ics" : "https://caldav.example.org/"
        }
    }
    FormRow {
        label: page.kind === "google" ? page.i18n("Google account:") : page.i18n("Login:")
        visible: page.kind !== "ics"
        TextField {
            id: userField
            Layout.fillWidth: true
            placeholderText: page.kind === "google" ? "name@gmail.com" : page.i18nc("placeholder for a login", "your login on the server")
        }
    }
    FormRow {
        label: page.i18n("App password:")
        visible: page.kind === "caldav"
        TextField {
            id: passwordField
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: page.hasPassword ? page.i18nc("placeholder: a password is stored", "stored — type to replace") : ""
        }
    }
    Hint {
        visible: page.kind === "caldav"
        text: page.i18n("Yandex: id.yandex.ru → Security → App passwords → Calendar.\niCloud: appleid.apple.com → Sign-in and security → App-specific passwords.")
    }
    FormRow {
        label: page.i18n("OAuth client id:")
        visible: page.kind === "google"
        TextField {
            id: clientIdField
            Layout.fillWidth: true
        }
    }
    FormRow {
        label: page.i18n("OAuth client secret:")
        visible: page.kind === "google"
        TextField {
            id: clientSecretField
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: page.signedIn ? page.i18nc("placeholder: a secret is stored", "stored — type to replace") : ""
        }
    }
    Hint {
        visible: page.kind === "google"
        // The browser login is the script's own, run once by hand: the service's copy of
        // notes.py writes the refresh token to the same accounts.json it reads.
        text: page.i18nc("Windows: how to sign in to Google", "A “Desktop app” OAuth client from console.cloud.google.com, with the Calendar API\nenabled. Save, then sign in once from a terminal with the service's own notes.py\n(calendar\\package\\contents\\code\\notes.py in the plaintop folder):\npython notes.py google-auth %1", page.accId.length > 0 ? page.accId : "ID")
    }
    FormRow {
        label: page.i18n("Calendar:")
        visible: page.kind !== "ics"
        TextField {
            id: calendarField
            Layout.fillWidth: true
            placeholderText: page.i18nc("placeholder for the calendar href", "empty — the first one on the server")
        }
    }
    FormRow {
        label: page.i18n("Found:")
        visible: page.kind !== "ics" && page.calendars.length > 0
        ComboBox {
            Layout.fillWidth: true
            model: page.calendars.map(c => c.name)
            currentIndex: -1
            displayText: page.i18nc("pick list placeholder", "pick…")
            onActivated: { page.calendar = page.calendars[currentIndex].href; currentIndex = -1 }
        }
    }
    FormRow {
        Button {
            text: page.i18n("Save")
            onClicked: page.saveAccount()
        }
        Button {
            text: page.i18n("Check")
            onClicked: page.checkAccount()
        }
    }

    Label {
        id: statusLabel
        Layout.fillWidth: true
        visible: page.status.length > 0
        text: page.status
        wrapMode: Text.Wrap
        color: page.failed ? "#B03030" : "#2E7D32"
    }
}
