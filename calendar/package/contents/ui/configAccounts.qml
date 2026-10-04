import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as P5Support

// The accounts the calendar reads — and the one it writes to. As many as you like, none
// by default: the list is whatever contents/code/notes.py keeps in its own file,
// ~/.config/plaincalendar/accounts.json, mode 600; this page only talks to the script.
// One protocol for all three providers, CalDAV: Yandex and iCloud with an app password,
// Google with its OAuth login run once in a terminal; and a read-only ICS link for any.
KCM.SimpleKCM {
    id: page

    readonly property string script: Qt.resolvedUrl("../code/notes.py").toString().replace("file://", "")

    property var accounts: []            // as the script lists them, secrets left out
    property int selected: -1
    property string status: ""
    property bool failed: false
    property var calendars: []           // from the last check: [{href, name}]

    // Kinds, presets and their URLs — the same index in each.
    readonly property var kinds: ["caldav", "google", "ics"]
    readonly property var presets: [
        { name: i18nc("account preset", "Yandex (CalDAV)"), kind: "caldav", url: "https://caldav.yandex.ru/" },
        { name: i18nc("account preset", "iCloud (CalDAV)"), kind: "caldav", url: "https://caldav.icloud.com/" },
        { name: i18nc("account preset", "Google (CalDAV, OAuth)"), kind: "google", url: "https://apidata.googleusercontent.com/caldav/v2/" },
        { name: i18nc("account preset", "any CalDAV server"), kind: "caldav", url: "" },
        { name: i18nc("account preset", "ICS link, read-only"), kind: "ics", url: "" }
    ]

    // One source, many one-shot commands: each is tagged with a nonce after a comment
    // sign, which the shell ignores, so two identical commands stay apart.
    P5Support.DataSource {
        id: runner
        engine: "executable"
        interval: 0
        property var pending: ({})
        function run(cmd, cb) {
            const key = cmd + " # " + Date.now() + "." + Math.floor(Math.random() * 1e6)
            pending[key] = cb
            connectSource(key)
        }
        onNewData: function(source, data) {
            disconnectSource(source)
            const cb = pending[source]
            delete pending[source]
            if (cb)
                cb(String(data.stdout), String(data.stderr))
        }
    }

    function cmd(args) {
        return "python3 '" + page.script + "' " + args
    }

    function b64(obj) {
        return Qt.btoa(unescape(encodeURIComponent(JSON.stringify(obj))))
    }

    function reload() {
        runner.run(cmd("accounts"), function(out) {
            try {
                page.accounts = JSON.parse(out)
            } catch (e) {
                page.accounts = []
                page.status = i18n("The script did not answer: %1", out.length > 0 ? out : i18n("is python3 installed?"))
                page.failed = true
            }
        })
    }

    Component.onCompleted: reload()

    function pick(i) {
        selected = i
        calendars = []
        status = ""
        failed = false
        if (i < 0 || i >= accounts.length) {
            form.clear()
            return
        }
        const a = accounts[i]
        form.id = String(a.id || "")
        form.name = String(a.name || "")
        form.kind = String(a.kind || "caldav")
        form.url = String(a.url || "")
        form.user = String(a.user || "")
        form.password = ""
        form.calendar = String(a.calendar || "")
        form.clientId = String(a.client_id || "")
        form.clientSecret = ""
        form.hasPassword = a.has_password === true
        form.signedIn = a.signed_in === true
    }

    function save() {
        if (form.id.trim().length === 0) {
            status = i18n("The account needs an id — a short word, say “yandex”.")
            failed = true
            return
        }
        const a = { id: form.id.trim(), name: form.name.trim() || form.id.trim(), kind: form.kind,
                    url: form.url.trim(), user: form.user.trim(), password: form.password,
                    calendar: form.calendar.trim(), client_id: form.clientId.trim(), client_secret: form.clientSecret }
        runner.run(cmd("account-save " + b64(a)), function(out) {
            page.answer(out, function(list) {
                page.accounts = list
                page.status = i18n("Saved.")
                for (let i = 0; i < list.length; i++)
                    if (list[i].id === a.id)
                        page.pick(i)
            })
        })
    }

    function remove() {
        if (selected < 0) return
        runner.run(cmd("account-remove '" + accounts[selected].id + "'"), function(out) {
            page.answer(out, function(list) {
                page.accounts = list
                page.pick(-1)
                page.status = i18n("Removed.")
            })
        })
    }

    // Saves first, so the check runs with what is in the form, then asks the server.
    function check() {
        if (form.id.trim().length === 0) return
        const a = { id: form.id.trim(), name: form.name.trim() || form.id.trim(), kind: form.kind,
                    url: form.url.trim(), user: form.user.trim(), password: form.password,
                    calendar: form.calendar.trim(), client_id: form.clientId.trim(), client_secret: form.clientSecret }
        status = i18n("Asking the server…")
        failed = false
        runner.run(cmd("account-save " + b64(a)), function(out) {
            page.answer(out, function(list) {
                page.accounts = list
                runner.run(cmd("check '" + a.id + "'"), function(out2) {
                    page.answer(out2, function(found) {
                        page.calendars = found.calendars || []
                        if (a.kind === "ics")
                            page.status = i18np("The link answers: %1 entry.", "The link answers: %1 entries.", found.entries || 0)
                        else if (page.calendars.length === 0)
                            page.status = i18n("The server answers, but lists no calendar.")
                        else
                            page.status = i18np("The server answers: %1 calendar — pick one below, or leave the field empty for the first.",
                                                "The server answers: %1 calendars — pick one below, or leave the field empty for the first.",
                                                page.calendars.length)
                        for (let i = 0; i < list.length; i++)
                            if (list[i].id === a.id) { page.selected = i; form.hasPassword = list[i].has_password === true; form.signedIn = list[i].signed_in === true }
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
            status = i18n("The script did not answer: %1", out)
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

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: true
            text: i18n("Calendars the widget reads, and the one it writes your notes to (chosen on the Notes page). Yandex and iCloud take an app password from your account's settings; Google signs in once through the browser.")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 8

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    model: page.accounts.length
                    clip: true
                    currentIndex: page.selected

                    delegate: ItemDelegate {
                        required property int index
                        readonly property var a: page.accounts[index] || ({})
                        width: list.width
                        highlighted: index === page.selected
                        onClicked: page.pick(index)
                        contentItem: ColumnLayout {
                            spacing: 0
                            Label { text: String(a.name || a.id || "") }
                            Label {
                                text: String(a.id || "") + " · " + String(a.kind || "")
                                      + (a.kind === "google"
                                         ? (a.signed_in ? "  · " + i18nc("Google account state", "signed in") : "  · " + i18nc("Google account state", "not signed in yet"))
                                         : (a.kind === "caldav" && !a.has_password ? "  · " + i18nc("CalDAV account state", "no password") : ""))
                                opacity: 0.6
                                font: Kirigami.Theme.smallFont
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop

                Button {
                    icon.name: "list-add"
                    text: i18n("New")
                    onClicked: page.pick(-1)
                }

                Button {
                    icon.name: "list-remove"
                    text: i18n("Remove")
                    enabled: page.selected >= 0
                    onClicked: page.remove()
                }
            }
        }

        Kirigami.FormLayout {
            id: form
            Layout.fillWidth: true

            property alias id: idField.text
            property alias name: nameField.text
            property string kind: "caldav"
            property alias url: urlField.text
            property alias user: userField.text
            property alias password: passwordField.text
            property alias calendar: calendarField.text
            property alias clientId: clientIdField.text
            property alias clientSecret: clientSecretField.text
            property bool hasPassword: false
            property bool signedIn: false

            function clear() {
                id = ""; name = ""; kind = "caldav"; url = ""; user = ""; password = ""; calendar = ""
                clientId = ""; clientSecret = ""; hasPassword = false; signedIn = false
                presetBox.currentIndex = 0
            }

            ComboBox {
                id: presetBox
                Kirigami.FormData.label: i18n("Provider:")
                model: page.presets.map(p => p.name)
                onActivated: {
                    const p = page.presets[currentIndex]
                    form.kind = p.kind
                    if (p.url.length > 0 || form.url.length === 0)
                        form.url = p.url
                }
            }

            TextField {
                id: idField
                Kirigami.FormData.label: i18n("Id:")
                placeholderText: i18nc("placeholder for an account id", "yandex")
                enabled: page.selected < 0
            }

            TextField {
                id: nameField
                Kirigami.FormData.label: i18n("Name:")
                placeholderText: i18nc("placeholder for an account's name", "as it is shown on the sticker")
            }

            TextField {
                id: urlField
                Kirigami.FormData.label: form.kind === "ics" ? i18n("Link:") : i18n("Server:")
                Layout.fillWidth: true
                placeholderText: form.kind === "ics" ? "https://…/basic.ics" : "https://caldav.example.org/"
            }

            TextField {
                id: userField
                Kirigami.FormData.label: form.kind === "google" ? i18n("Google account:") : i18n("Login:")
                visible: form.kind !== "ics"
                placeholderText: form.kind === "google" ? "name@gmail.com" : i18nc("placeholder for a login", "your login on the server")
            }

            TextField {
                id: passwordField
                Kirigami.FormData.label: i18n("App password:")
                visible: form.kind === "caldav"
                echoMode: TextInput.Password
                placeholderText: form.hasPassword ? i18nc("placeholder: a password is stored", "stored — type to replace") : ""
            }

            Label {
                visible: form.kind === "caldav"
                text: i18n("Yandex: id.yandex.ru → Security → App passwords → Calendar.\niCloud: appleid.apple.com → Sign-in and security → App-specific passwords.")
                opacity: 0.7
                font: Kirigami.Theme.smallFont
            }

            TextField {
                id: clientIdField
                Kirigami.FormData.label: i18n("OAuth client id:")
                visible: form.kind === "google"
                Layout.fillWidth: true
            }

            TextField {
                id: clientSecretField
                Kirigami.FormData.label: i18n("OAuth client secret:")
                visible: form.kind === "google"
                echoMode: TextInput.Password
                placeholderText: form.signedIn ? i18nc("placeholder: a secret is stored", "stored — type to replace") : ""
            }

            Label {
                visible: form.kind === "google"
                text: i18n("A “Desktop app” OAuth client from console.cloud.google.com, with the Calendar API\nenabled. Save, then sign in once from a terminal:\npython3 %1 google-auth %2", page.script, form.id.length > 0 ? form.id : "ID")
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            TextField {
                id: calendarField
                Kirigami.FormData.label: i18n("Calendar:")
                visible: form.kind !== "ics"
                Layout.fillWidth: true
                placeholderText: i18nc("placeholder for the calendar href", "empty — the first one on the server")
            }

            ComboBox {
                visible: form.kind !== "ics" && page.calendars.length > 0
                Kirigami.FormData.label: i18n("Found:")
                model: page.calendars.map(c => c.name)
                currentIndex: -1
                displayText: i18nc("pick list placeholder", "pick…")
                onActivated: { form.calendar = page.calendars[currentIndex].href; currentIndex = -1 }
            }

            RowLayout {
                Button {
                    icon.name: "document-save"
                    text: i18n("Save")
                    onClicked: page.save()
                }
                Button {
                    icon.name: "network-connect"
                    text: i18n("Check")
                    onClicked: page.check()
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: page.failed ? Kirigami.MessageType.Error : Kirigami.MessageType.Positive
            visible: page.status.length > 0
            text: page.status
        }

        Item { Layout.fillHeight: true }
    }
}
