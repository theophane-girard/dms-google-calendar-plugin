import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "googleCalendar"

    property bool authBusy: false
    property var accounts: []

    readonly property string pluginDir: Quickshell.env("HOME") + "/.config/DankMaterialShell/plugins/googleCalendar"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/DankMaterialShell/plugins/googleCalendar"
    readonly property string accountsPath: stateDir + "/accounts.json"

    function runAddAccount() {
        root.authBusy = true
        var p = loginProcComponent.createObject(root)
        p.running = true
    }

    function runLogout(email) {
        var p = logoutProcComponent.createObject(root, { email: email })
        p.running = true
    }

    function runListCalendars() {
        var p = listCalProcComponent.createObject(root)
        p.running = true
    }

    function runToggleCalendar(email, calId) {
        var p = toggleCalProcComponent.createObject(root, { email: email, calId: calId })
        p.running = true
    }

    function runFetch() {
        var p = fetchProcComponent.createObject(root)
        p.running = true
    }

    Component {
        id: loginProcComponent
        Process {
            command: ["python3", root.pluginDir + "/auth.py", "login"]
            onExited: function(code) {
                root.authBusy = false
                if (code === 0) {
                    ToastService.showInfo("Compte ajouté")
                    accountsFile.reload()
                    root.runFetch()
                } else {
                    ToastService.showError("Échec de la connexion (code " + code + ")")
                }
                destroy()
            }
        }
    }

    Component {
        id: logoutProcComponent
        Process {
            property string email: ""
            command: ["python3", root.pluginDir + "/auth.py", "logout", email]
            onExited: function(code) {
                ToastService.showInfo("Compte retiré")
                accountsFile.reload()
                root.runFetch()
                destroy()
            }
        }
    }

    Component {
        id: listCalProcComponent
        Process {
            command: ["python3", root.pluginDir + "/auth.py", "list-calendars"]
            onExited: function(code) {
                if (code === 0) {
                    ToastService.showInfo("Liste des calendriers rafraîchie")
                    accountsFile.reload()
                } else {
                    ToastService.showError("Échec du rafraîchissement (code " + code + ")")
                }
                destroy()
            }
        }
    }

    Component {
        id: toggleCalProcComponent
        Process {
            property string email: ""
            property string calId: ""
            command: ["python3", root.pluginDir + "/auth.py", "toggle-calendar", email, calId]
            onExited: function(code) {
                accountsFile.reload()
                root.runFetch()
                destroy()
            }
        }
    }

    Component {
        id: fetchProcComponent
        Process {
            command: ["python3", root.pluginDir + "/auth.py", "fetch"]
            onExited: destroy()
        }
    }

    FileView {
        id: accountsFile
        path: root.accountsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.accounts = JSON.parse(text())
            } catch (e) {
                root.accounts = []
            }
        }
        onLoadFailed: root.accounts = []
    }

    Component.onCompleted: accountsFile.reload()

    StyledText {
        width: parent.width
        text: "Google Calendar"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Multi-compte. Connecte plusieurs comptes Google et active les calendriers de chacun individuellement."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // ── Comptes ─────────────────────────────────────────────────────────────
    StyledRect {
        width: parent.width
        height: accountsCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: accountsCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                width: parent.width
                spacing: Theme.spacingM
                StyledText {
                    text: "Comptes Google"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: root.accounts.length + " compte" + (root.accounts.length > 1 ? "s" : "")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                visible: root.accounts.length === 0
                text: "Aucun compte connecté. Renseigne d'abord client_id et secret OAuth ci-dessous, puis clique « + Connecter un compte »."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Repeater {
                model: root.accounts

                delegate: StyledRect {
                    width: accountsCol.width
                    height: accountColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surface

                    property var accountData: modelData

                    Column {
                        id: accountColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "account_circle"
                                size: Theme.iconSize
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: accountData.email || "(inconnu)"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 220
                                elide: Text.ElideRight
                            }
                            Button {
                                text: "Retirer"
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: root.runLogout(accountData.email)
                            }
                        }

                        StyledText {
                            text: "Calendriers"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            topPadding: Theme.spacingS
                        }

                        Repeater {
                            model: accountData.calendars || []

                            delegate: Item {
                                width: accountColumn.width
                                height: calRow.implicitHeight + Theme.spacingXS * 2

                                property var calData: modelData

                                Row {
                                    id: calRow
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingS

                                    Rectangle {
                                        width: 20; height: 20; radius: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        border.width: 2
                                        border.color: calData.enabled ? Theme.primary : Theme.surfaceVariantText
                                        color: calData.enabled ? Theme.primary : "transparent"
                                        DankIcon {
                                            anchors.centerIn: parent
                                            visible: calData.enabled
                                            name: "check"
                                            size: 14
                                            color: Theme.onPrimary
                                        }
                                    }
                                    Rectangle {
                                        width: 12; height: 12; radius: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: calData.backgroundColor || Theme.primary
                                        visible: !!calData.backgroundColor
                                    }
                                    StyledText {
                                        text: (calData.summary || calData.id) + (calData.primary ? "  (primary)" : "")
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runToggleCalendar(accountData.email, calData.id)
                                }
                            }
                        }
                    }
                }
            }

            Row {
                spacing: Theme.spacingM

                Button {
                    text: root.authBusy ? "En attente du navigateur…" : "+ Connecter un compte"
                    enabled: !root.authBusy
                    onClicked: root.runAddAccount()
                }

                Button {
                    text: "Rafraîchir les calendriers"
                    enabled: root.accounts.length > 0
                    onClicked: root.runListCalendars()
                }
            }
        }
    }

    // ── OAuth credentials ───────────────────────────────────────────────────
    StyledRect {
        width: parent.width
        height: credsCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: credsCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "OAuth Client (Google Cloud)"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            StyledText {
                text: "Un seul OAuth Client suffit pour plusieurs comptes Google. Crée un client « Desktop app » dans Google Cloud Console (voir README). Tous les comptes que tu ajoutes doivent figurer en « Test users » de cet écran de consentement."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
            }

            StringSetting {
                settingKey: "clientId"
                label: "Client ID"
                placeholder: "xxxxx.apps.googleusercontent.com"
                defaultValue: ""
            }

            StringSetting {
                settingKey: "clientSecret"
                label: "Client Secret"
                placeholder: "GOCSPX-…"
                defaultValue: ""
            }
        }
    }

    // ── Affichage ───────────────────────────────────────────────────────────
    StyledRect {
        width: parent.width
        height: displayCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: displayCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Affichage"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            StringSetting {
                settingKey: "refreshMinutes"
                label: "Intervalle de rafraîchissement (min)"
                description: "Toutes les N minutes, on re-requête l'API Google pour tous les calendriers activés"
                placeholder: "5"
                defaultValue: "5"
            }
        }
    }

    // ── Notifications ───────────────────────────────────────────────────────
    StyledRect {
        width: parent.width
        height: notifCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: notifCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Notifications"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "notifications"
                label: "Rappels d'événement"
                description: "Notifications 15 min, 5 min et à l'heure de chaque event, avec actions Snooze 5 min / Stop"
                defaultValue: true
            }
        }
    }
}
