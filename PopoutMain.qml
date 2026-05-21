import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import "i18n.js" as I18n

// Conteneur racine du popout : état + clavier + layout (header/toolbar/body).
// Reçoit `plugin` (le PluginComponent racine) pour accéder à events / refresh
// / createEvent / etc. closePopout & parentPopout sont injectés par DMS.
FocusScope {
    id: popoutMain

    property var plugin: null
    property var closePopout: null
    property var parentPopout: null

    readonly property int headerHeight: 40
    implicitHeight: bodyColumn.implicitHeight

    focus: true

    // ── i18n ───────────────────────────────────────────────────────────────
    readonly property string locale: Qt.locale().name.startsWith("fr") ? "fr" : "en"
    function tr(key, params) { return I18n.tr(locale, key, params) }

    // ── State ──────────────────────────────────────────────────────────────
    property var anchorDate: { var d = new Date(); d.setHours(0, 0, 0, 0); return d }
    property int scopeDays: 1
    property var nowTick: new Date()

    // mode = "list" | "form" | "details"
    property string mode: "list"
    property var selectedEvent: null

    // Densité verticale (px par minute) pour les tuiles horaires
    readonly property real pxPerMin: 1.5
    readonly property real minTileHeight: 44

    readonly property bool viewIncludesToday: {
        for (var i = 0; i < scopeDays; ++i) {
            var d = new Date(anchorDate)
            d.setDate(d.getDate() + i)
            if (_sameDay(d, nowTick)) return true
        }
        return false
    }

    Timer {
        interval: 60 * 1000
        repeat: true
        running: true
        onTriggered: popoutMain.nowTick = new Date()
    }

    onParentPopoutChanged: {
        if (parentPopout) {
            parentPopout.contentHandlesKeys = true
            Qt.callLater(function () { popoutMain.forceActiveFocus() })
        }
    }

    Connections {
        target: plugin
        function onEventCreated() { popoutMain.mode = "list" }
    }

    // ── Focusables (toolbar + events) ──────────────────────────────────────
    property int focusedIndex: 0

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
            for (var j = 0; j < d.allDay.length; ++j)
                list.push({ kind: "event", evId: d.allDay[j].id })
            for (var k = 0; k < d.clusters.length; ++k) {
                var packed = d.clusters[k].events
                for (var l = 0; l < packed.length; ++l)
                    list.push({ kind: "event", evId: packed[l].ev.id })
            }
        }
        return list
    }

    onFocusablesChanged: {
        if (focusedIndex >= focusables.length) focusedIndex = focusables.length - 1
        if (focusedIndex < 0) focusedIndex = 0
    }

    function findEventById(id) {
        var ev = plugin ? plugin.events : []
        for (var i = 0; i < ev.length; ++i)
            if (ev[i].id === id) return ev[i]
        return null
    }

    function openEventDetails(ev) {
        if (!ev) return
        selectedEvent = ev
        mode = "details"
        Qt.callLater(function () {
            if (detailsView && detailsView.backBtn) detailsView.backBtn.forceActiveFocus()
        })
    }

    function _detailsFocusables() {
        var list = []
        if (detailsView.backBtn) list.push(detailsView.backBtn)
        if (detailsView.meetBtn && detailsView.meetBtn.visible) list.push(detailsView.meetBtn)
        if (detailsView.openBtn && detailsView.openBtn.visible) list.push(detailsView.openBtn)
        return list
    }

    function _detailsMoveFocus(delta) {
        var items = _detailsFocusables()
        if (items.length === 0) return
        var idx = 0
        for (var i = 0; i < items.length; ++i) {
            if (items[i].activeFocus) { idx = i; break }
        }
        var next = Math.max(0, Math.min(items.length - 1, idx + delta))
        items[next].forceActiveFocus()
    }

    function findFirstUpcomingTodayIndex() {
        var now = nowTick
        for (var i = 0; i < focusables.length; ++i) {
            var f = focusables[i]
            if (f.kind !== "event") continue
            var ev = findEventById(f.evId)
            if (!ev || !ev.start) continue
            var s = new Date(ev.start)
            var e = ev.end ? new Date(ev.end) : s
            if (!_sameDay(s, now)) continue
            if (e <= now) continue
            return i
        }
        return -1
    }

    function activateFocused() {
        var f = focusables[focusedIndex]
        if (!f) return
        if (f.kind === "prev") shiftAnchor(-scopeDays)
        else if (f.kind === "next") shiftAnchor(scopeDays)
        else if (f.kind === "today") resetToToday()
        else if (f.kind === "scope") scopeDays = f.value
        else if (f.kind === "refresh") {
            if (plugin) plugin.refreshEvents()
            ToastService.showInfo("Google Calendar: rafraîchissement…")
        }
        else if (f.kind === "add") mode = "form"
        else if (f.kind === "event") {
            var ev = findEventById(f.evId)
            if (ev) openEventDetails(ev)
        }
    }

    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
            if (mode === "form" || mode === "details") { mode = "list" }
            else if (closePopout) closePopout()
            event.accepted = true
            return
        }
        if (mode === "form") return
        if (mode === "details") {
            if (event.key === Qt.Key_J || event.key === Qt.Key_L) {
                _detailsMoveFocus(1); event.accepted = true
            } else if (event.key === Qt.Key_K || event.key === Qt.Key_H) {
                _detailsMoveFocus(-1); event.accepted = true
            } else if (event.key === Qt.Key_Space
                       || event.key === Qt.Key_Return
                       || event.key === Qt.Key_Enter) {
                if (selectedEvent && selectedEvent.meetLink) {
                    Quickshell.execDetached(["xdg-open", selectedEvent.meetLink])
                    if (closePopout) closePopout()
                } else if (selectedEvent && selectedEvent.htmlLink) {
                    Quickshell.execDetached(["xdg-open", selectedEvent.htmlLink])
                    if (closePopout) closePopout()
                }
                event.accepted = true
            }
            return
        }
        if (event.key === Qt.Key_H) {
            shiftAnchor(-scopeDays); event.accepted = true
        } else if (event.key === Qt.Key_L) {
            shiftAnchor(scopeDays); event.accepted = true
        } else if (event.key === Qt.Key_J || event.key === Qt.Key_Tab) {
            if (focusedIndex < focusables.length - 1) focusedIndex++
            event.accepted = true
        } else if (event.key === Qt.Key_K || event.key === Qt.Key_Backtab) {
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

    Component.onCompleted: {
        forceActiveFocus()
        Qt.callLater(function () {
            var idx = findFirstUpcomingTodayIndex()
            if (idx >= 0) focusedIndex = idx
        })
    }

    // ── Helpers (utilisés par les sous-composants via popout._xxx) ─────────
    function shiftAnchor(deltaDays) {
        var d = new Date(anchorDate); d.setDate(d.getDate() + deltaDays)
        anchorDate = d
    }

    function resetToToday() {
        var d = new Date(); d.setHours(0, 0, 0, 0); anchorDate = d
    }

    function _sameDay(a, b) {
        return a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate()
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
        if (_sameDay(d, now)) return tr("today")
        if (_sameDay(d, tomorrow)) return tr("tomorrow")
        if (_sameDay(d, yesterday)) return tr("yesterday")
        var days = I18n.days(locale)
        var months = I18n.months(locale)
        return days[d.getDay()] + " " + d.getDate() + " " + months[d.getMonth()]
    }

    function _fmtSourceLabel(s) {
        if (!s) return ""
        s = s.toString().trim()
        var m
        if ((m = s.match(/^https?:\/\/([^\/]+)/))) return m[1].replace(/^www\./, "")
        if ((m = s.match(/^([^@\s]+)@/))) { if (m[1].length <= 24) return m[1] }
        if (s.length > 20) return s.substring(0, 18) + "…"
        return s
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

        if (!title) { ToastService.showWarning(tr("toast_title_required")); return }
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || isNaN(new Date(date).getTime())) {
            ToastService.showWarning(tr("toast_invalid_date"))
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
                ToastService.showWarning(tr("toast_invalid_time"))
                return
            }
            if (startT.length === 4) startT = "0" + startT
            if (endT.length === 4) endT = "0" + endT
            var tz = _tzOffsetString()
            payload.start = { dateTime: date + "T" + startT + ":00" + tz }
            payload.end = { dateTime: date + "T" + endT + ":00" + tz }
        }

        plugin.createEvent(JSON.stringify(payload))
    }

    // Sweep-line + lane packing + sequential-Y, retourne
    //   { events: [{ev, lane, y, height}], laneCount, start, end, height }
    function _packCluster(events) {
        var px = pxPerMin
        var minH = minTileHeight
        var sorted = events.slice().sort(function (a, b) {
            return new Date(a.start).getTime() - new Date(b.start).getTime()
        })
        var clusterStart = new Date(sorted[0].start)
        var clusterEnd = new Date(sorted[0].end || sorted[0].start)
        var lanes = []
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
            events: packed, laneCount: lanes.length,
            start: clusterStart, end: clusterEnd, height: clusterHeight
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
        for (var i = 0; i < scopeDays; ++i) {
            var d = new Date(anchorDate)
            d.setHours(0, 0, 0, 0)
            d.setDate(d.getDate() + i)
            days.push({ date: d, allDay: [], timed: [] })
        }
        var events = plugin ? plugin.events : []
        for (var j = 0; j < events.length; ++j) {
            var ev = events[j]
            if (!ev.start) continue
            if (ev.allDay) {
                var sAll = new Date(ev.start); sAll.setHours(0, 0, 0, 0)
                var eAll = ev.end ? new Date(ev.end) : new Date(sAll.getTime() + 86400000)
                eAll.setHours(0, 0, 0, 0)
                for (var k = 0; k < days.length; ++k) {
                    if (days[k].date.getTime() >= sAll.getTime()
                        && days[k].date.getTime() < eAll.getTime()) {
                        days[k].allDay.push(ev)
                    }
                }
            } else {
                var sT = new Date(ev.start)
                for (var kt = 0; kt < days.length; ++kt) {
                    if (_sameDay(sT, days[kt].date)) {
                        days[kt].timed.push(ev)
                        break
                    }
                }
            }
        }
        for (var m = 0; m < days.length; ++m)
            days[m].clusters = _buildClusters(days[m].timed)
        return days
    }

    readonly property int totalVisibleEvents: {
        var n = 0
        for (var i = 0; i < groupedDays.length; ++i)
            n += groupedDays[i].allDay.length + groupedDays[i].timed.length
        return n
    }

    // ── UI ─────────────────────────────────────────────────────────────────
    Column {
        id: bodyColumn
        width: parent.width
        spacing: 0

        Item {
            id: header
            width: parent.width
            height: 40

            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: tr("google_calendar")
                font.pixelSize: Theme.fontSizeLarge + 4
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                StyledText {
                    text: tr("keyboard_hint")
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
                        onClicked: { if (popoutMain.closePopout) popoutMain.closePopout() }
                    }
                }
            }
        }

        PopoutToolbar {
            id: toolbar
            width: parent.width
            popout: popoutMain
        }

        // Body : 3 vues mutuellement exclusives (list / form / details)
        Item {
            id: body
            width: parent.width
            height: (plugin ? plugin.popoutHeight : 600) - header.height - toolbar.height - Theme.spacingM

            StyledText {
                visible: popoutMain.mode === "list" && plugin && !plugin.authenticated
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: tr("not_authenticated")
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.surfaceVariantText
            }

            PopoutDayList {
                id: dayList
                visible: popoutMain.mode === "list" && plugin && plugin.authenticated
                anchors.fill: parent
                anchors.topMargin: Theme.spacingS
                popout: popoutMain
            }

            PopoutForm {
                id: formView
                visible: popoutMain.mode === "form"
                anchors.fill: parent
                anchors.topMargin: Theme.spacingS
                popout: popoutMain
            }

            PopoutDetails {
                id: detailsView
                visible: popoutMain.mode === "details" && popoutMain.selectedEvent
                anchors.fill: parent
                anchors.topMargin: Theme.spacingS
                popout: popoutMain
            }
        }
    }
}
