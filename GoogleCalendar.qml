import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "google-calendar"

    property string calendarId: pluginData.calendarId || "primary"
    property int refreshMinutes: pluginData.refreshMinutes || 5
    property bool notificationsEnabled: pluginData.notifications !== undefined ? pluginData.notifications : true

    property var events: []
    property bool authenticated: false

    readonly property string pluginDir: Quickshell.env("HOME") + "/.config/DankMaterialShell/plugins/googleCalendar"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/DankMaterialShell/plugins/googleCalendar"
    readonly property string eventsPath: stateDir + "/events.json"
    readonly property string tokensPath: stateDir + "/tokens.json"

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

    function refreshEvents() {
        var p = fetchProcComponent.createObject(root)
        p.running = true
    }

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
        id: tokensFile
        path: root.tokensPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.authenticated = (text() || "").indexOf("refresh_token") !== -1
        }
        onLoadFailed: root.authenticated = false
    }

    Component {
        id: fetchProcComponent
        Process {
            command: ["python3", root.pluginDir + "/auth.py", "fetch"]
            onExited: function(code) {
                if (code !== 0) {
                    ToastService.showWarning("Google Calendar: échec du fetch (code " + code + ")")
                }
                destroy()
            }
        }
    }

    signal eventCreated()

    Component {
        id: createProcComponent
        Process {
            property string scriptStr: ""
            command: ["sh", "-c", scriptStr]
            onExited: function(code) {
                if (code === 0) {
                    ToastService.showInfo("Événement créé ✓")
                    root.refreshEvents()
                    root.eventCreated()
                } else {
                    ToastService.showError("Google Calendar: échec de création (code " + code + ")")
                }
                destroy()
            }
        }
    }

    function createEvent(payloadJson) {
        var marker = "GCAL_HEREDOC_" + Math.floor(Math.random() * 1e9).toString(36)
        var script = "python3 " + root.pluginDir + "/auth.py create <<'" + marker + "'\n"
                     + payloadJson + "\n" + marker + "\n"
        var p = createProcComponent.createObject(root, { scriptStr: script })
        p.running = true
    }

    Timer {
        interval: Math.max(1, root.refreshMinutes) * 60 * 1000
        repeat: true
        running: root.authenticated
        triggeredOnStart: true
        onTriggered: root.refreshEvents()
    }

    // Daemon de notifications : lance auth.py daemon tant qu'on est authentifié
    // et que les notifs sont activées. Quickshell tue le child au démontage.
    Process {
        id: notifDaemon
        command: ["python3", root.pluginDir + "/auth.py", "daemon"]
        running: root.authenticated && root.notificationsEnabled
    }

    Component.onCompleted: {
        eventsFile.reload()
        tokensFile.reload()
    }

    pillRightClickAction: function () {
        root.refreshEvents()
        ToastService.showInfo("Google Calendar: rafraîchissement…")
    }

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
        FocusScope {
            id: popoutColumn

            implicitHeight: bodyColumn.implicitHeight
            focus: true

            // PluginPopout injects these via Loader:
            property var closePopout: null
            property var parentPopout: null
            readonly property int headerHeight: 40  // matches PopoutComponent

            onParentPopoutChanged: {
                if (parentPopout) {
                    // Sinon DankPopout.focusHelper grab tous les keys
                    parentPopout.contentHandlesKeys = true
                    Qt.callLater(function () { popoutColumn.forceActiveFocus() })
                }
            }

            // ── State ──────────────────────────────────────────────────────
            property var anchorDate: {
                var d = new Date(); d.setHours(0, 0, 0, 0); return d
            }
            property int scopeDays: 1
            property var nowTick: new Date()

            readonly property bool viewIncludesToday: {
                for (var i = 0; i < scopeDays; ++i) {
                    var d = new Date(anchorDate)
                    d.setDate(d.getDate() + i)
                    if (_sameDay(d, nowTick)) return true
                }
                return false
            }

            // mode = "list" | "form"
            property string mode: "list"

            Connections {
                target: root
                function onEventCreated() {
                    popoutColumn.mode = "list"
                }
            }

            // Densité verticale : combien de px par minute (proportional sizing).
            readonly property real pxPerMin: 1.5
            readonly property real minTileHeight: 28

            // ── Focus / clavier ────────────────────────────────────────────
            property int focusedIndex: 0

            // focusables: liste linéaire d'éléments navigables
            // { kind: "prev"|"today"|"next"|"scope"|"event", value?, evId? }
            readonly property var focusables: {
                var list = [
                    { kind: "prev" },
                    { kind: "today" },
                    { kind: "next" },
                    { kind: "scope", value: 1 },
                    { kind: "scope", value: 3 },
                    { kind: "refresh" },
                    { kind: "add" }
                ]
                for (var i = 0; i < groupedDays.length; ++i) {
                    var d = groupedDays[i]
                    for (var j = 0; j < d.allDay.length; ++j) {
                        list.push({ kind: "event", evId: d.allDay[j].id })
                    }
                    for (var k = 0; k < d.clusters.length; ++k) {
                        var packed = d.clusters[k].events
                        for (var l = 0; l < packed.length; ++l) {
                            list.push({ kind: "event", evId: packed[l].ev.id })
                        }
                    }
                }
                return list
            }

            onFocusablesChanged: {
                if (focusedIndex >= focusables.length) focusedIndex = focusables.length - 1
                if (focusedIndex < 0) focusedIndex = 0
            }

            function findEventById(id) {
                for (var i = 0; i < root.events.length; ++i)
                    if (root.events[i].id === id) return root.events[i]
                return null
            }

            function activateFocused() {
                var f = focusables[focusedIndex]
                if (!f) return
                if (f.kind === "prev") shiftAnchor(-scopeDays)
                else if (f.kind === "next") shiftAnchor(scopeDays)
                else if (f.kind === "today") resetToToday()
                else if (f.kind === "scope") scopeDays = f.value
                else if (f.kind === "refresh") {
                    root.refreshEvents()
                    ToastService.showInfo("Google Calendar: rafraîchissement…")
                }
                else if (f.kind === "add") mode = "form"
                else if (f.kind === "event") {
                    var ev = findEventById(f.evId)
                    if (ev && ev.htmlLink) Quickshell.execDetached(["xdg-open", ev.htmlLink])
                    if (closePopout) closePopout()
                }
            }

            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Escape) {
                    if (mode === "form") { mode = "list" }
                    else if (closePopout) closePopout()
                    event.accepted = true
                    return
                }
                // En mode form, on laisse les DankTextField gérer les touches.
                if (mode === "form") return

                if (event.key === Qt.Key_H) {
                    shiftAnchor(-scopeDays); event.accepted = true
                } else if (event.key === Qt.Key_L) {
                    shiftAnchor(scopeDays); event.accepted = true
                } else if (event.key === Qt.Key_J) {
                    if (focusedIndex < focusables.length - 1) focusedIndex++
                    event.accepted = true
                } else if (event.key === Qt.Key_K) {
                    if (focusedIndex > 0) focusedIndex--
                    event.accepted = true
                } else if (event.key === Qt.Key_Space
                           || event.key === Qt.Key_Return
                           || event.key === Qt.Key_Enter) {
                    activateFocused(); event.accepted = true
                } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_N) {
                    mode = "form"; event.accepted = true
                }
            }

            Component.onCompleted: forceActiveFocus()

            Timer {
                interval: 60 * 1000
                repeat: true
                running: true
                onTriggered: popoutColumn.nowTick = new Date()
            }

            function shiftAnchor(deltaDays) {
                var d = new Date(popoutColumn.anchorDate)
                d.setDate(d.getDate() + deltaDays)
                popoutColumn.anchorDate = d
            }

            function resetToToday() {
                var d = new Date(); d.setHours(0, 0, 0, 0)
                popoutColumn.anchorDate = d
            }

            function _sameDay(a, b) {
                return a.getFullYear() === b.getFullYear()
                    && a.getMonth() === b.getMonth()
                    && a.getDate() === b.getDate()
            }

            function _formatDate(d) {
                return d.getFullYear() + "-"
                     + (d.getMonth() + 1).toString().padStart(2, "0") + "-"
                     + d.getDate().toString().padStart(2, "0")
            }

            function _tzOffsetString() {
                var off = -new Date().getTimezoneOffset()
                var sign = off >= 0 ? "+" : "-"
                var abs = Math.abs(off)
                return sign + Math.floor(abs / 60).toString().padStart(2, "0")
                     + ":" + (abs % 60).toString().padStart(2, "0")
            }

            function submitForm(title, date, startT, endT, location, allDay) {
                title = (title || "").trim()
                date = (date || "").trim()
                startT = (startT || "").trim()
                endT = (endT || "").trim()
                location = (location || "").trim()

                if (!title) { ToastService.showWarning("Titre requis"); return }
                if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || isNaN(new Date(date).getTime())) {
                    ToastService.showWarning("Date invalide (AAAA-MM-JJ)")
                    return
                }

                var payload = { summary: title }
                if (location) payload.location = location

                if (allDay) {
                    var d = new Date(date)
                    var next = new Date(d); next.setDate(d.getDate() + 1)
                    payload.start = { date: date }
                    payload.end = { date: _formatDate(next) }
                } else {
                    if (!/^\d{1,2}:\d{2}$/.test(startT) || !/^\d{1,2}:\d{2}$/.test(endT)) {
                        ToastService.showWarning("Heures invalides (HH:MM)")
                        return
                    }
                    if (startT.length === 4) startT = "0" + startT
                    if (endT.length === 4) endT = "0" + endT
                    var tz = _tzOffsetString()
                    payload.start = { dateTime: date + "T" + startT + ":00" + tz }
                    payload.end = { dateTime: date + "T" + endT + ":00" + tz }
                }

                root.createEvent(JSON.stringify(payload))
            }

            function _fmtTime(iso) {
                if (!iso) return ""
                var d = (iso instanceof Date) ? iso : new Date(iso)
                if (isNaN(d.getTime())) return iso
                return d.getHours().toString().padStart(2, "0") + ":" + d.getMinutes().toString().padStart(2, "0")
            }

            function _fmtDayHeader(d) {
                var now = new Date()
                var tomorrow = new Date(now); tomorrow.setDate(now.getDate() + 1)
                var yesterday = new Date(now); yesterday.setDate(now.getDate() - 1)
                if (_sameDay(d, now)) return "Aujourd'hui"
                if (_sameDay(d, tomorrow)) return "Demain"
                if (_sameDay(d, yesterday)) return "Hier"
                var days = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]
                var months = ["janv.", "févr.", "mars", "avr.", "mai", "juin",
                              "juil.", "août", "sept.", "oct.", "nov.", "déc."]
                return days[d.getDay()] + " " + d.getDate() + " " + months[d.getMonth()]
            }

            function _fmtRangeLabel() {
                var start = popoutColumn.anchorDate
                if (popoutColumn.scopeDays === 1) return _fmtDayHeader(start)
                var end = new Date(start)
                end.setDate(end.getDate() + popoutColumn.scopeDays - 1)
                var months = ["janv.", "févr.", "mars", "avr.", "mai", "juin",
                              "juil.", "août", "sept.", "oct.", "nov.", "déc."]
                if (start.getMonth() === end.getMonth())
                    return start.getDate() + "–" + end.getDate() + " " + months[start.getMonth()]
                return start.getDate() + " " + months[start.getMonth()] + " → " + end.getDate() + " " + months[end.getMonth()]
            }

            // Sweep-line + lane packing + sequential-Y dans chaque lane pour
            // que les minimum heights ne fassent JAMAIS chevaucher deux events.
            // Returns { events: [{ev, lane, y, height}], laneCount, start, end, height }
            function _packCluster(events) {
                var px = popoutColumn.pxPerMin
                var minH = popoutColumn.minTileHeight

                var sorted = events.slice().sort(function (a, b) {
                    return new Date(a.start).getTime() - new Date(b.start).getTime()
                })
                var clusterStart = new Date(sorted[0].start)
                var clusterEnd = new Date(sorted[0].end || sorted[0].start)
                var lanes = []   // lanes[i] = end timestamp (logique) du dernier event de la lane
                var packed = []
                for (var i = 0; i < sorted.length; ++i) {
                    var ev = sorted[i]
                    var s = new Date(ev.start)
                    var e = ev.end ? new Date(ev.end) : s
                    if (e > clusterEnd) clusterEnd = e
                    var lane = -1
                    for (var j = 0; j < lanes.length; ++j) {
                        if (lanes[j] <= s.getTime()) { lane = j; lanes[j] = e.getTime(); break }
                    }
                    if (lane === -1) { lanes.push(e.getTime()); lane = lanes.length - 1 }
                    packed.push({ ev: ev, lane: lane })
                }

                // 2e passe : position Y séquentielle par lane (no overlap visuel)
                var laneBottomY = []
                for (var k = 0; k < lanes.length; ++k) laneBottomY.push(0)
                var clusterHeight = 0
                for (var m = 0; m < packed.length; ++m) {
                    var p = packed[m]
                    var ps = new Date(p.ev.start).getTime()
                    var pe = (p.ev.end ? new Date(p.ev.end) : new Date(p.ev.start)).getTime()
                    var naturalY = (ps - clusterStart.getTime()) / 60000 * px
                    var h = Math.max(minH, (pe - ps) / 60000 * px)
                    var y = Math.max(naturalY, laneBottomY[p.lane])
                    p.y = y
                    p.height = h
                    laneBottomY[p.lane] = y + h
                    if (y + h > clusterHeight) clusterHeight = y + h
                }

                return {
                    events: packed,
                    laneCount: lanes.length,
                    start: clusterStart,
                    end: clusterEnd,
                    height: clusterHeight
                }
            }

            function _buildClusters(timed) {
                var sorted = timed.slice().sort(function (a, b) {
                    return new Date(a.start).getTime() - new Date(b.start).getTime()
                })
                var clusters = []
                var current = []
                var currentEnd = null
                for (var i = 0; i < sorted.length; ++i) {
                    var ev = sorted[i]
                    var s = new Date(ev.start)
                    var e = ev.end ? new Date(ev.end) : s
                    if (currentEnd !== null && s.getTime() < currentEnd.getTime()) {
                        current.push(ev)
                        if (e > currentEnd) currentEnd = e
                    } else {
                        if (current.length) clusters.push(_packCluster(current))
                        current = [ev]; currentEnd = e
                    }
                }
                if (current.length) clusters.push(_packCluster(current))
                return clusters
            }

            readonly property var groupedDays: {
                var days = []
                for (var i = 0; i < popoutColumn.scopeDays; ++i) {
                    var d = new Date(popoutColumn.anchorDate)
                    d.setDate(d.getDate() + i)
                    days.push({ date: d, allDay: [], timed: [] })
                }
                for (var j = 0; j < root.events.length; ++j) {
                    var ev = root.events[j]
                    if (!ev.start) continue
                    var s = new Date(ev.start)
                    for (var k = 0; k < days.length; ++k) {
                        if (popoutColumn._sameDay(s, days[k].date)) {
                            if (ev.allDay) days[k].allDay.push(ev)
                            else days[k].timed.push(ev)
                            break
                        }
                    }
                }
                for (var m = 0; m < days.length; ++m)
                    days[m].clusters = popoutColumn._buildClusters(days[m].timed)
                return days
            }

            readonly property int totalVisibleEvents: {
                var n = 0
                for (var i = 0; i < groupedDays.length; ++i)
                    n += groupedDays[i].allDay.length + groupedDays[i].timed.length
                return n
            }

            // ── UI ─────────────────────────────────────────────────────────
            Column {
                id: bodyColumn
                width: parent.width
                spacing: 0

                // Header bar (replaces PopoutComponent header)
                Item {
                    id: header
                    width: parent.width
                    height: 40

                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Google Calendar"
                        font.pixelSize: Theme.fontSizeLarge + 4
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        StyledText {
                            text: "h/l ◀▶  j/k ↕  ⏎ activer"
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            width: 32; height: 32; radius: 16
                            color: closeArea.containsMouse ? Theme.errorHover : "transparent"
                            DankIcon {
                                anchors.centerIn: parent
                                name: "close"
                                size: Theme.iconSize - 4
                                color: closeArea.containsMouse ? Theme.error : Theme.surfaceText
                            }
                            MouseArea {
                                id: closeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { if (popoutColumn.closePopout) popoutColumn.closePopout() }
                            }
                        }
                    }
                }

                // Toolbar
                Item {
                    id: toolbar
                    width: parent.width
                    height: 44

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        Component {
                            id: navButtonComponent
                            StyledRect {
                                property string iconName: ""
                                property bool focused: false
                                property bool hovered: false
                                signal navClicked()
                                width: 32; height: 32; radius: 16
                                color: hovered ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                                border.width: focused ? 2 : 0
                                border.color: Theme.primary
                            }
                        }

                        // Prev
                        StyledRect {
                            width: 32; height: 32; radius: 16
                            color: prevMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            border.width: popoutColumn.focusables[popoutColumn.focusedIndex]
                                          && popoutColumn.focusables[popoutColumn.focusedIndex].kind === "prev" ? 2 : 0
                            border.color: Theme.primary
                            DankIcon {
                                anchors.centerIn: parent
                                name: "chevron_left"
                                size: Theme.iconSize - 2
                                color: Theme.surfaceText
                            }
                            MouseArea {
                                id: prevMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popoutColumn.shiftAnchor(-popoutColumn.scopeDays)
                            }
                        }

                        // "Aujourd'hui" — toujours, primary quand la vue inclut aujourd'hui
                        StyledRect {
                            width: todayLabel.implicitWidth + Theme.spacingM * 2
                            height: 32
                            radius: Theme.cornerRadius
                            color: popoutColumn.viewIncludesToday
                                ? (todayMouse.containsMouse ? Qt.lighter(Theme.primary, 1.15) : Theme.primary)
                                : (todayMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                            border.width: popoutColumn.focusables[popoutColumn.focusedIndex]
                                          && popoutColumn.focusables[popoutColumn.focusedIndex].kind === "today" ? 2 : 0
                            border.color: popoutColumn.viewIncludesToday ? Theme.onPrimary : Theme.primary
                            StyledText {
                                id: todayLabel
                                anchors.centerIn: parent
                                text: "Aujourd'hui"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: popoutColumn.viewIncludesToday ? Theme.onPrimary : Theme.surfaceText
                            }
                            MouseArea {
                                id: todayMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popoutColumn.resetToToday()
                            }
                        }

                        // Next
                        StyledRect {
                            width: 32; height: 32; radius: 16
                            color: nextMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            border.width: popoutColumn.focusables[popoutColumn.focusedIndex]
                                          && popoutColumn.focusables[popoutColumn.focusedIndex].kind === "next" ? 2 : 0
                            border.color: Theme.primary
                            DankIcon {
                                anchors.centerIn: parent
                                name: "chevron_right"
                                size: Theme.iconSize - 2
                                color: Theme.surfaceText
                            }
                            MouseArea {
                                id: nextMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popoutColumn.shiftAnchor(popoutColumn.scopeDays)
                            }
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        StyledRect {
                            width: 44; height: 32
                            radius: Theme.cornerRadius
                            property bool focused: popoutColumn.focusables[popoutColumn.focusedIndex]
                                                  && popoutColumn.focusables[popoutColumn.focusedIndex].kind === "scope"
                                                  && popoutColumn.focusables[popoutColumn.focusedIndex].value === 1
                            color: popoutColumn.scopeDays === 1
                                ? Theme.primary
                                : (scope1Mouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                            border.width: focused ? 2 : 0
                            border.color: Theme.primary
                            StyledText {
                                anchors.centerIn: parent
                                text: "1j"
                                color: popoutColumn.scopeDays === 1 ? Theme.onPrimary : Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                            }
                            MouseArea {
                                id: scope1Mouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popoutColumn.scopeDays = 1
                            }
                        }

                        StyledRect {
                            width: 44; height: 32
                            radius: Theme.cornerRadius
                            property bool focused: popoutColumn.focusables[popoutColumn.focusedIndex]
                                                  && popoutColumn.focusables[popoutColumn.focusedIndex].kind === "scope"
                                                  && popoutColumn.focusables[popoutColumn.focusedIndex].value === 3
                            color: popoutColumn.scopeDays === 3
                                ? Theme.primary
                                : (scope3Mouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                            border.width: focused ? 2 : 0
                            border.color: Theme.primary
                            StyledText {
                                anchors.centerIn: parent
                                text: "3j"
                                color: popoutColumn.scopeDays === 3 ? Theme.onPrimary : Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                            }
                            MouseArea {
                                id: scope3Mouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popoutColumn.scopeDays = 3
                            }
                        }

                        // Spacer
                        Item { width: Theme.spacingM; height: 1 }

                        // Refresh : force le fetch
                        StyledRect {
                            width: 32; height: 32; radius: 16
                            property bool focused: popoutColumn.focusables[popoutColumn.focusedIndex]
                                                  && popoutColumn.focusables[popoutColumn.focusedIndex].kind === "refresh"
                            color: refreshMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            border.width: focused ? 2 : 0
                            border.color: Theme.primary
                            DankIcon {
                                id: refreshIcon
                                anchors.centerIn: parent
                                name: "refresh"
                                size: Theme.iconSize - 2
                                color: Theme.surfaceText

                                RotationAnimation on rotation {
                                    id: refreshSpin
                                    from: 0; to: 360
                                    duration: 700
                                    loops: 1
                                    running: false
                                }
                            }
                            MouseArea {
                                id: refreshMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.refreshEvents()
                                    ToastService.showInfo("Google Calendar: rafraîchissement…")
                                    refreshSpin.start()
                                }
                            }
                        }

                        // "+" : nouvel événement
                        StyledRect {
                            width: 32; height: 32; radius: 16
                            property bool focused: popoutColumn.focusables[popoutColumn.focusedIndex]
                                                  && popoutColumn.focusables[popoutColumn.focusedIndex].kind === "add"
                            color: addMouse.containsMouse ? Qt.lighter(Theme.primary, 1.15) : Theme.primary
                            border.width: focused ? 2 : 0
                            border.color: Theme.onPrimary
                            DankIcon {
                                anchors.centerIn: parent
                                name: "add"
                                size: Theme.iconSize - 2
                                color: Theme.onPrimary
                            }
                            MouseArea {
                                id: addMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popoutColumn.mode = "form"
                            }
                        }
                    }
                }

                // Body
                Item {
                    id: body
                    width: parent.width
                    height: root.popoutHeight - header.height - toolbar.height - Theme.spacingM

                    StyledText {
                        visible: popoutColumn.mode === "list"
                                 && (!root.authenticated || popoutColumn.totalVisibleEvents === 0)
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: !root.authenticated
                            ? "Compte non connecté.\nOuvre les réglages → Se connecter."
                            : "Rien de prévu sur cette période 🌴"
                        font.pixelSize: Theme.fontSizeLarge
                        color: Theme.surfaceVariantText
                    }

                    DankListView {
                        id: dayList
                        visible: popoutColumn.mode === "list"
                                 && root.authenticated && popoutColumn.totalVisibleEvents > 0
                        anchors.fill: parent
                        anchors.topMargin: Theme.spacingS
                        clip: true
                        spacing: Theme.spacingM
                        model: popoutColumn.groupedDays

                        delegate: Column {
                            id: dayDelegate
                            width: dayList.width
                            spacing: Theme.spacingXS

                            property var dayInfo: modelData
                            property bool isToday: popoutColumn._sameDay(dayInfo.date, popoutColumn.nowTick)
                            property int totalCount: dayInfo.allDay.length + dayInfo.timed.length

                            // Où placer le now-indicator pour ce jour
                            //   { type: "none"|"before"|"between"|"after"|"in", clusterIndex, offsetMin }
                            property var nowPlacement: {
                                if (!isToday) return { type: "none" }
                                var c = dayInfo.clusters
                                if (c.length === 0) return { type: "none" }
                                var now = popoutColumn.nowTick.getTime()
                                if (now < c[0].start.getTime()) return { type: "before" }
                                if (now > c[c.length - 1].end.getTime()) return { type: "after" }
                                for (var i = 0; i < c.length; ++i) {
                                    if (now >= c[i].start.getTime() && now <= c[i].end.getTime())
                                        return { type: "in", clusterIndex: i,
                                                 offsetMin: (now - c[i].start.getTime()) / 60000 }
                                    if (i < c.length - 1 && now > c[i].end.getTime() && now < c[i + 1].start.getTime())
                                        return { type: "between", clusterIndex: i }
                                }
                                return { type: "none" }
                            }

                            // Day header
                            Row {
                                width: parent.width
                                spacing: Theme.spacingS
                                StyledText {
                                    text: popoutColumn._fmtDayHeader(dayDelegate.dayInfo.date)
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Bold
                                    color: dayDelegate.isToday ? Theme.primary : Theme.surfaceText
                                }
                                StyledText {
                                    text: "(" + dayDelegate.totalCount + ")"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // All-day banners
                            Repeater {
                                model: dayDelegate.dayInfo.allDay
                                delegate: StyledRect {
                                    width: dayDelegate.width
                                    height: 30
                                    radius: Theme.cornerRadius
                                    color: Theme.primary
                                    opacity: allDayMouse.containsMouse ? 1.0 : 0.85

                                    property bool focused: {
                                        var f = popoutColumn.focusables[popoutColumn.focusedIndex]
                                        return f && f.kind === "event" && f.evId === modelData.id
                                    }
                                    border.width: focused ? 2 : 0
                                    border.color: Theme.surface

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.spacingS
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingXS
                                        DankIcon {
                                            name: "event_available"
                                            size: Theme.iconSize - 6
                                            color: Theme.onPrimary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        StyledText {
                                            text: modelData.title || "(sans titre)"
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                            color: Theme.onPrimary
                                            elide: Text.ElideRight
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: allDayMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.htmlLink) Quickshell.execDetached(["xdg-open", modelData.htmlLink])
                                            if (popoutColumn.closePopout) popoutColumn.closePopout()
                                        }
                                    }
                                }
                            }

                            // Now-line en haut si "before"
                            Loader {
                                width: parent.width
                                active: dayDelegate.nowPlacement.type === "before"
                                sourceComponent: nowSeparatorComponent
                            }

                            // Clusters
                            Repeater {
                                model: dayDelegate.dayInfo.clusters

                                delegate: Column {
                                    id: clusterDelegate
                                    width: dayDelegate.width
                                    spacing: 0

                                    property var cluster: modelData
                                    property int clusterIndex: index
                                    property real clusterHeight: cluster.height

                                    // Cluster: positionnement absolu des tuiles, hauteur proportionnelle
                                    Item {
                                        id: clusterArea
                                        width: parent.width
                                        height: clusterDelegate.clusterHeight + Theme.spacingXS

                                        Repeater {
                                            model: clusterDelegate.cluster.events

                                            delegate: StyledRect {
                                                id: tileRect
                                                property var packed: modelData
                                                property var ev: packed.ev
                                                property int lane: packed.lane
                                                property int laneCount: clusterDelegate.cluster.laneCount
                                                property var evStart: new Date(ev.start)
                                                property var evEnd: ev.end ? new Date(ev.end) : evStart

                                                property real laneW: (clusterArea.width - Theme.spacingXS * Math.max(0, laneCount - 1)) / laneCount

                                                property string evState: {
                                                    if (!dayDelegate.isToday) return "future"
                                                    if (evEnd < popoutColumn.nowTick) return "past"
                                                    if (evStart <= popoutColumn.nowTick && evEnd >= popoutColumn.nowTick) return "ongoing"
                                                    return "future"
                                                }
                                                property bool focused: {
                                                    var f = popoutColumn.focusables[popoutColumn.focusedIndex]
                                                    return f && f.kind === "event" && f.evId === ev.id
                                                }

                                                x: lane * (laneW + Theme.spacingXS)
                                                y: packed.y
                                                width: laneW
                                                height: packed.height

                                                radius: Theme.cornerRadius
                                                color: tileMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                                                opacity: evState === "past" ? 0.55 : 1.0
                                                border.width: focused ? 2 : 0
                                                border.color: Theme.primary

                                                Rectangle {
                                                    id: tileAccent
                                                    width: 4
                                                    anchors.left: parent.left
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.margins: 3
                                                    radius: 2
                                                    color: {
                                                        if (tileRect.evState === "ongoing") return Theme.error
                                                        if (tileRect.evState === "past") return Theme.surfaceVariantText
                                                        return Theme.primary
                                                    }
                                                }

                                                Column {
                                                    anchors.left: tileAccent.right
                                                    anchors.leftMargin: Theme.spacingXS
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: Theme.spacingXS
                                                    anchors.top: parent.top
                                                    anchors.topMargin: tileRect.height < 40 ? 2 : 4
                                                    spacing: 0
                                                    clip: true

                                                    // Mode compact : "HH:MM Titre" sur une seule ligne
                                                    StyledText {
                                                        width: parent.width
                                                        visible: tileRect.height < 40
                                                        text: popoutColumn._fmtTime(tileRect.evStart) + "  " + (tileRect.ev.title || "(sans titre)")
                                                        font.pixelSize: Theme.fontSizeSmall - 1
                                                        font.weight: Font.Medium
                                                        color: Theme.surfaceText
                                                        elide: Text.ElideRight
                                                    }

                                                    // Mode étendu : heure puis titre
                                                    StyledText {
                                                        width: parent.width
                                                        visible: tileRect.height >= 40
                                                        text: popoutColumn._fmtTime(tileRect.evStart) + " – " + popoutColumn._fmtTime(tileRect.evEnd)
                                                        font.pixelSize: Theme.fontSizeSmall - 1
                                                        color: Theme.surfaceVariantText
                                                        elide: Text.ElideRight
                                                    }
                                                    StyledText {
                                                        width: parent.width
                                                        visible: tileRect.height >= 40
                                                        text: tileRect.ev.title || "(sans titre)"
                                                        font.pixelSize: tileRect.height < 56 ? Theme.fontSizeSmall : Theme.fontSizeMedium
                                                        font.weight: Font.Medium
                                                        color: Theme.surfaceText
                                                        wrapMode: Text.Wrap
                                                        maximumLineCount: tileRect.height < 70 ? 1 : 2
                                                        elide: Text.ElideRight
                                                    }
                                                    StyledText {
                                                        visible: tileRect.height >= 80
                                                                 && tileRect.laneCount === 1
                                                                 && tileRect.ev.location
                                                                 && tileRect.ev.location.length > 0
                                                        width: parent.width
                                                        text: "📍 " + tileRect.ev.location
                                                        font.pixelSize: Theme.fontSizeSmall - 1
                                                        color: Theme.surfaceVariantText
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                MouseArea {
                                                    id: tileMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (tileRect.ev.htmlLink) Quickshell.execDetached(["xdg-open", tileRect.ev.htmlLink])
                                                        if (popoutColumn.closePopout) popoutColumn.closePopout()
                                                    }
                                                }
                                            }
                                        }

                                        // Now-line à l'intérieur du cluster
                                        Loader {
                                            active: dayDelegate.nowPlacement.type === "in"
                                                    && dayDelegate.nowPlacement.clusterIndex === clusterDelegate.clusterIndex
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            y: active ? (dayDelegate.nowPlacement.offsetMin * popoutColumn.pxPerMin - 9) : 0
                                            height: 18
                                            sourceComponent: nowInClusterComponent
                                            z: 100
                                        }
                                    }

                                    // Now-line en gap après ce cluster
                                    Loader {
                                        width: parent.width
                                        active: dayDelegate.nowPlacement.type === "between"
                                                && dayDelegate.nowPlacement.clusterIndex === clusterDelegate.clusterIndex
                                        sourceComponent: nowSeparatorComponent
                                    }
                                }
                            }

                            // Now-line "after" tous les clusters
                            Loader {
                                width: parent.width
                                active: dayDelegate.nowPlacement.type === "after"
                                sourceComponent: nowSeparatorComponent
                            }
                        }
                    }

                    // ── FORM VIEW : nouvel événement ──────────────────────
                    Flickable {
                        id: formView
                        visible: popoutColumn.mode === "form"
                        anchors.fill: parent
                        anchors.topMargin: Theme.spacingS
                        contentWidth: width
                        contentHeight: formCol.implicitHeight
                        clip: true

                        Column {
                            id: formCol
                            width: parent.width
                            spacing: Theme.spacingM

                            // Title
                            Column {
                                width: parent.width
                                spacing: 4
                                StyledText {
                                    text: "Titre *"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                                DankTextField {
                                    id: formTitle
                                    width: parent.width
                                    height: 36
                                    placeholderText: "Réunion équipe…"
                                    text: ""
                                }
                            }

                            // Date
                            Column {
                                width: parent.width
                                spacing: 4
                                StyledText {
                                    text: "Date (AAAA-MM-JJ)"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                                DankTextField {
                                    id: formDate
                                    width: parent.width
                                    height: 36
                                    placeholderText: "2026-05-19"
                                    text: popoutColumn._formatDate(popoutColumn.anchorDate)
                                }
                            }

                            // All-day toggle
                            Rectangle {
                                id: allDayToggle
                                property bool checked: false
                                width: parent.width
                                height: 32
                                radius: Theme.cornerRadius
                                color: "transparent"
                                activeFocusOnTab: true
                                border.width: activeFocus ? 2 : 0
                                border.color: Theme.primary
                                Keys.onPressed: function (event) {
                                    if (event.key === Qt.Key_Space
                                        || event.key === Qt.Key_Return
                                        || event.key === Qt.Key_Enter) {
                                        allDayToggle.checked = !allDayToggle.checked
                                        event.accepted = true
                                    }
                                }

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingXS
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingS

                                    Rectangle {
                                        width: 20; height: 20; radius: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        border.width: 2
                                        border.color: allDayToggle.checked ? Theme.primary : Theme.surfaceVariantText
                                        color: allDayToggle.checked ? Theme.primary : "transparent"
                                        DankIcon {
                                            anchors.centerIn: parent
                                            visible: allDayToggle.checked
                                            name: "check"
                                            size: 14
                                            color: Theme.onPrimary
                                        }
                                    }
                                    StyledText {
                                        text: "Toute la journée"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: allDayToggle.checked = !allDayToggle.checked
                                }
                            }

                            // Start / End times (hidden if all-day)
                            Row {
                                width: parent.width
                                spacing: Theme.spacingM
                                visible: !allDayToggle.checked

                                Column {
                                    width: (parent.width - parent.spacing) / 2
                                    spacing: 4
                                    StyledText {
                                        text: "Début (HH:MM)"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                    DankTextField {
                                        id: formStartTime
                                        width: parent.width
                                        height: 36
                                        placeholderText: "10:00"
                                        text: "10:00"
                                    }
                                }
                                Column {
                                    width: (parent.width - parent.spacing) / 2
                                    spacing: 4
                                    StyledText {
                                        text: "Fin (HH:MM)"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                    DankTextField {
                                        id: formEndTime
                                        width: parent.width
                                        height: 36
                                        placeholderText: "11:00"
                                        text: "11:00"
                                    }
                                }
                            }

                            // Location
                            Column {
                                width: parent.width
                                spacing: 4
                                StyledText {
                                    text: "Lieu (optionnel)"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                                DankTextField {
                                    id: formLocation
                                    width: parent.width
                                    height: 36
                                    placeholderText: "Salle de réunion, adresse…"
                                    text: ""
                                }
                            }

                            // Save / Cancel
                            Item {
                                width: parent.width
                                height: 36

                                Row {
                                    anchors.right: parent.right
                                    spacing: Theme.spacingS

                                    StyledRect {
                                        id: cancelBtn
                                        width: 100; height: 36; radius: Theme.cornerRadius
                                        color: cancelMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                                        activeFocusOnTab: true
                                        border.width: activeFocus ? 2 : 0
                                        border.color: Theme.primary
                                        Keys.onPressed: function (event) {
                                            if (event.key === Qt.Key_Return
                                                || event.key === Qt.Key_Enter
                                                || event.key === Qt.Key_Space) {
                                                popoutColumn.mode = "list"
                                                event.accepted = true
                                            }
                                        }
                                        StyledText {
                                            anchors.centerIn: parent
                                            text: "Annuler"
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeSmall
                                        }
                                        MouseArea {
                                            id: cancelMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: popoutColumn.mode = "list"
                                        }
                                    }

                                    StyledRect {
                                        id: saveBtn
                                        width: 100; height: 36; radius: Theme.cornerRadius
                                        color: saveMouse.containsMouse ? Qt.lighter(Theme.primary, 1.15) : Theme.primary
                                        activeFocusOnTab: true
                                        border.width: activeFocus ? 2 : 0
                                        border.color: Theme.onPrimary
                                        function trigger() {
                                            popoutColumn.submitForm(
                                                formTitle.text, formDate.text,
                                                formStartTime.text, formEndTime.text,
                                                formLocation.text, allDayToggle.checked
                                            )
                                        }
                                        Keys.onPressed: function (event) {
                                            if (event.key === Qt.Key_Return
                                                || event.key === Qt.Key_Enter
                                                || event.key === Qt.Key_Space) {
                                                saveBtn.trigger()
                                                event.accepted = true
                                            }
                                        }
                                        StyledText {
                                            anchors.centerIn: parent
                                            text: "Créer"
                                            color: Theme.onPrimary
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                        }
                                        MouseArea {
                                            id: saveMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: saveBtn.trigger()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Composants partagés du now-indicator ──────────────────────
            Component {
                id: nowSeparatorComponent
                Item {
                    width: parent ? parent.width : 0
                    height: 18

                    StyledText {
                        id: nowLbl
                        text: popoutColumn._fmtTime(popoutColumn.nowTick)
                        color: Theme.error
                        font.pixelSize: Theme.fontSizeSmall - 1
                        font.weight: Font.Bold
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        id: nowDot
                        width: 8; height: 8; radius: 4
                        color: Theme.error
                        anchors.left: nowLbl.right
                        anchors.leftMargin: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        height: 2
                        color: Theme.error
                        opacity: 0.85
                        anchors.left: nowDot.right
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Component {
                id: nowInClusterComponent
                Item {
                    StyledRect {
                        id: nowPill
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.error
                        radius: 4
                        width: nowPillLbl.implicitWidth + 8
                        height: nowPillLbl.implicitHeight + 4
                        z: 2
                        StyledText {
                            id: nowPillLbl
                            anchors.centerIn: parent
                            text: popoutColumn._fmtTime(popoutColumn.nowTick)
                            color: Theme.onError !== undefined ? Theme.onError : "#ffffff"
                            font.pixelSize: Theme.fontSizeSmall - 1
                            font.weight: Font.Bold
                        }
                    }
                    Rectangle {
                        height: 2
                        color: Theme.error
                        opacity: 0.85
                        anchors.left: nowPill.right
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter
                        z: 1
                    }
                }
            }
        }
    }
}
