import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "i18n.js" as I18n

// Plugin Google Calendar : pill dans la barre + popout multi-vues.
// Voir PopoutMain.qml pour la UI principale.
PluginComponent {
    id: root

    layerNamespacePlugin: "google-calendar"

    // ── Settings (lus depuis pluginData / plugin_settings.json) ───────────
    property string calendarId: pluginData.calendarId || "primary"
    property int refreshMinutes: pluginData.refreshMinutes || 5
    property bool notificationsEnabled: pluginData.notifications !== undefined ? pluginData.notifications : true

    // ── État partagé avec PopoutMain ──────────────────────────────────────
    property var events: []
    property bool authenticated: false

    readonly property string pluginDir: Quickshell.env("HOME") + "/.config/DankMaterialShell/plugins/googleCalendar"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/DankMaterialShell/plugins/googleCalendar"
    readonly property string eventsPath: stateDir + "/events.json"
    readonly property string accountsPath: stateDir + "/accounts.json"

    // i18n — détectée par PopoutMain aussi, mais utile ici pour les toasts
    readonly property string locale: Qt.locale().name.startsWith("fr") ? "fr" : "en"
    function tr(key, params) { return I18n.tr(locale, key, params) }

    // ── Indicateur visuel sur la pill : nombre d'events restants today ────
    readonly property int upcomingTodayCount: {
        var now = new Date()
        var endOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59)
        var n = 0
        for (var i = 0; i < events.length; ++i) {
            var ev = events[i]
            if (!ev.start) continue
            var s = new Date(ev.start)
            var e = ev.end ? new Date(ev.end) : s
            if (e >= now && s <= endOfToday) n++
        }
        return n
    }

    // ── Actions exposées (PopoutMain les invoque via la prop `plugin`) ────
    signal eventCreated()

    function refreshEvents() {
        fetchProcComponent.createObject(root).running = true
    }

    function createEvent(payloadJson) {
        var marker = "GCAL_HEREDOC_" + Math.floor(Math.random() * 1e9).toString(36)
        var script = "python3 " + root.pluginDir + "/auth.py create <<'" + marker + "'\n"
                     + payloadJson + "\n" + marker + "\n"
        createProcComponent.createObject(root, { scriptStr: script }).running = true
    }

    // ── I/O (lit ce que le daemon Python produit) ─────────────────────────
    FileView {
        id: eventsFile
        path: root.eventsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                var data = JSON.parse(text())
                root.events = data.events || []
            } catch (e) { /* ignore */ }
        }
    }

    FileView {
        id: accountsFile
        path: root.accountsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.authenticated = (text() || "").indexOf("refresh_token") !== -1
        }
        onLoadFailed: root.authenticated = false
    }

    // ── Subprocesses (fetch / create / notification daemon) ───────────────
    Component {
        id: fetchProcComponent
        Process {
            command: ["python3", root.pluginDir + "/auth.py", "fetch"]
            onExited: function(code) {
                if (code !== 0) ToastService.showWarning(root.tr("toast_fetch_fail", { code: code }))
                destroy()
            }
        }
    }

    Component {
        id: createProcComponent
        Process {
            property string scriptStr: ""
            command: ["sh", "-c", scriptStr]
            onExited: function(code) {
                if (code === 0) {
                    ToastService.showInfo(root.tr("toast_event_created"))
                    root.refreshEvents()
                    root.eventCreated()
                } else {
                    ToastService.showError(root.tr("toast_create_fail", { code: code }))
                }
                destroy()
            }
        }
    }

    Timer {
        interval: Math.max(1, root.refreshMinutes) * 60 * 1000
        repeat: true
        running: root.authenticated
        triggeredOnStart: true
        onTriggered: root.refreshEvents()
    }

    Process {
        id: notifDaemon
        command: ["python3", root.pluginDir + "/auth.py", "daemon"]
        running: root.authenticated && root.notificationsEnabled
    }

    Component.onCompleted: {
        eventsFile.reload()
        accountsFile.reload()
    }

    pillRightClickAction: function () {
        root.refreshEvents()
        ToastService.showInfo(root.tr("toast_refresh"))
    }

    // ── Pill (icône seule, couleur primary si event today à venir) ────────
    horizontalBarPill: Component {
        Item {
            implicitWidth: Theme.iconSize + Theme.spacingS
            implicitHeight: Theme.iconSize
            DankIcon {
                anchors.centerIn: parent
                name: root.authenticated ? "event" : "event_busy"
                size: Theme.iconSize
                color: !root.authenticated
                    ? Theme.warningText
                    : (root.upcomingTodayCount > 0 ? Theme.primary : Theme.widgetIconColor)
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: Theme.iconSize + Theme.spacingS
            implicitHeight: Theme.iconSize
            DankIcon {
                anchors.centerIn: parent
                name: root.authenticated ? "event" : "event_busy"
                size: Theme.barIconSize(root.barThickness, -2)
                color: !root.authenticated
                    ? Theme.warningText
                    : (root.upcomingTodayCount > 0 ? Theme.primary : Theme.widgetIconColor)
            }
        }
    }

    popoutWidth: 540
    popoutHeight: 620

    popoutContent: Component {
        PopoutMain {
            plugin: root
        }
    }
}
