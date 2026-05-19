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

    property string accountStatus: "Vérification…"
    property bool authBusy: false

    readonly property string pluginDir: Quickshell.env("HOME") + "/.config/DankMaterialShell/plugins/googleCalendar"

    function refreshStatus() {
        var p = statusProcComponent.createObject(root)
        p.running = true
    }

    function runLogin() {
        root.authBusy = true
        root.accountStatus = "Ouverture du navigateur…"
        var p = loginProcComponent.createObject(root)
        p.running = true
    }

    function runLogout() {
        var p = logoutProcComponent.createObject(root)
        p.running = true
    }

    Component {
        id: statusProcComponent
        Process {
            command: ["python3", root.pluginDir + "/auth.py", "status"]
            stdout: StdioCollector { onStreamFinished: root.accountStatus = text.trim() || "non connecté" }
            onExited: destroy()
        }
    }

    Component {
        id: loginProcComponent
        Process {
            command: ["python3", root.pluginDir + "/auth.py", "login"]
            onExited: function(code) {
                root.authBusy = false
                if (code === 0) {
                    ToastService.showInfo("Compte Google connecté")
                    root.refreshStatus()
                    // déclenche un premier fetch
                    var f = fetchProcComponent.createObject(root)
                    f.running = true
                } else {
                    ToastService.showError("Échec de la connexion (code " + code + ")")
                    root.accountStatus = "Échec — vérifie client_id/secret"
                }
                destroy()
            }
        }
    }

    Component {
        id: logoutProcComponent
        Process {
            command: ["python3", root.pluginDir + "/auth.py", "logout"]
            onExited: function(code) {
                ToastService.showInfo("Déconnecté")
                root.refreshStatus()
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

    Component.onCompleted: refreshStatus()

    StyledText {
        width: parent.width
        text: "Google Calendar"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Affiche ton agenda Google dans la barre. Authentification OAuth via navigateur (flux loopback)."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // ── Compte ──────────────────────────────────────────────────────────────
    StyledRect {
        width: parent.width
        height: accountCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: accountCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Compte Google"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            StyledText {
                text: "Statut : " + root.accountStatus
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Row {
                spacing: Theme.spacingM

                Button {
                    text: root.authBusy ? "En attente du navigateur…" : "Se connecter à Google"
                    enabled: !root.authBusy
                    onClicked: root.runLogin()
                }

                Button {
                    text: "Se déconnecter"
                    onClicked: root.runLogout()
                }

                Button {
                    text: "Rafraîchir"
                    onClicked: root.refreshStatus()
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
                text: "Crée un OAuth Client de type « Desktop app » dans Google Cloud Console, active l'API Google Calendar, puis colle ici l'ID + secret. Voir le README pour les étapes."
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
                settingKey: "calendarId"
                label: "Calendar ID"
                description: "« primary » pour ton agenda principal, ou un ID complet (email du calendrier partagé)"
                placeholder: "primary"
                defaultValue: "primary"
            }

            StringSetting {
                settingKey: "maxResults"
                label: "Nombre d'événements"
                description: "Combien d'événements à venir charger"
                placeholder: "10"
                defaultValue: "10"
            }

            StringSetting {
                settingKey: "refreshMinutes"
                label: "Intervalle de rafraîchissement (min)"
                description: "Toutes les N minutes, on requête l'API Google"
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
