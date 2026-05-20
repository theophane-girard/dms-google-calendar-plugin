import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Vue détail d'un événement
Flickable {
    id: root
    property var popout: null
    readonly property var ev: (popout && popout.selectedEvent) || ({})

    // Aliases pour que PopoutMain puisse forcer le focus / itérer
    property alias backBtn: detailsBackBtn
    property alias meetBtn: detailsMeetBtn
    property alias openBtn: detailsOpenBtn

    property var evStart: ev.start ? new Date(ev.start) : null
    property var evEnd: ev.end ? new Date(ev.end) : evStart

    contentWidth: width
    contentHeight: detailsCol.implicitHeight
    clip: true

    Column {
        id: detailsCol
        width: parent.width
        spacing: Theme.spacingM

        // Back row
        Row {
            spacing: Theme.spacingS

            StyledRect {
                id: detailsBackBtn
                width: 32; height: 32; radius: 16
                color: backMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                activeFocusOnTab: true
                border.width: activeFocus ? 2 : 0
                border.color: Theme.primary
                Keys.onPressed: function (event) {
                    if (event.key === Qt.Key_Space
                        || event.key === Qt.Key_Return
                        || event.key === Qt.Key_Enter) {
                        popout.mode = "list"
                        event.accepted = true
                    }
                }
                DankIcon {
                    anchors.centerIn: parent
                    name: "arrow_back"
                    size: Theme.iconSize - 2
                    color: Theme.surfaceText
                }
                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: popout.mode = "list"
                }
            }
            StyledText {
                text: root.evStart ? popout._fmtDayHeader(root.evStart) : ""
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Title
        StyledText {
            width: parent.width
            text: root.ev.title || "(sans titre)"
            font.pixelSize: Theme.fontSizeLarge + 2
            font.weight: Font.Bold
            color: Theme.surfaceText
            wrapMode: Text.Wrap
        }

        // Source calendrier
        Row {
            spacing: Theme.spacingXS
            visible: !!root.ev.calendarSummary
            Rectangle {
                width: 12; height: 12; radius: 6
                color: root.ev.calendarColor || Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.ev.calendarSummary || ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                elide: Text.ElideRight
                width: detailsCol.width - 20
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Time
        Row {
            spacing: Theme.spacingS
            DankIcon {
                name: "schedule"
                size: Theme.iconSize - 4
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: {
                    if (root.ev.allDay) return "Toute la journée"
                    if (!root.evStart) return ""
                    return popout._fmtTime(root.evStart) + " – " + popout._fmtTime(root.evEnd)
                }
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Location
        Row {
            spacing: Theme.spacingS
            visible: !!root.ev.location
            DankIcon {
                name: "place"
                size: Theme.iconSize - 4
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.ev.location || ""
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                width: detailsCol.width - 32
                wrapMode: Text.Wrap
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Meet
        StyledRect {
            id: detailsMeetBtn
            visible: !!root.ev.meetLink
            width: parent.width
            height: 48
            radius: Theme.cornerRadius
            color: meetMouse.containsMouse ? Qt.lighter(Theme.primary, 1.15) : Theme.primary
            activeFocusOnTab: visible
            border.width: activeFocus ? 2 : 0
            border.color: Theme.onPrimary
            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Space
                    || event.key === Qt.Key_Return
                    || event.key === Qt.Key_Enter) {
                    if (root.ev.meetLink) {
                        Quickshell.execDetached(["xdg-open", root.ev.meetLink])
                        if (popout.closePopout) popout.closePopout()
                    }
                    event.accepted = true
                }
            }
            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingS
                DankIcon {
                    name: "videocam"
                    size: Theme.iconSize - 2
                    color: Theme.onPrimary
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: "Rejoindre Google Meet"
                    color: Theme.onPrimary
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                id: meetMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.ev.meetLink) {
                        Quickshell.execDetached(["xdg-open", root.ev.meetLink])
                        if (popout.closePopout) popout.closePopout()
                    }
                }
            }
        }

        // Attendees
        Row {
            spacing: Theme.spacingS
            visible: root.ev.attendees && root.ev.attendees.length > 0
            DankIcon {
                name: "group"
                size: Theme.iconSize - 4
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: {
                    var n = (root.ev.attendees || []).length
                    var acc = 0
                    var dec = 0
                    for (var i = 0; i < n; ++i) {
                        var s = root.ev.attendees[i].responseStatus
                        if (s === "accepted") acc++
                        else if (s === "declined") dec++
                    }
                    return n + " participant" + (n > 1 ? "s" : "")
                        + "  ·  " + acc + " ✓  " + dec + " ✗"
                }
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Description (HTML stripped)
        StyledText {
            visible: !!root.ev.description
            width: parent.width
            text: (root.ev.description || "").replace(/<[^>]+>/g, "").trim()
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
            wrapMode: Text.Wrap
            topPadding: Theme.spacingS
        }

        // Open in Google Calendar
        StyledRect {
            id: detailsOpenBtn
            visible: !!root.ev.htmlLink
            width: parent.width
            height: 40
            radius: Theme.cornerRadius
            color: openMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
            activeFocusOnTab: visible
            border.width: activeFocus ? 2 : 0
            border.color: Theme.primary
            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Space
                    || event.key === Qt.Key_Return
                    || event.key === Qt.Key_Enter) {
                    Quickshell.execDetached(["xdg-open", root.ev.htmlLink])
                    if (popout.closePopout) popout.closePopout()
                    event.accepted = true
                }
            }
            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingS
                DankIcon {
                    name: "open_in_new"
                    size: Theme.iconSize - 4
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: "Ouvrir dans Google Calendar"
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                id: openMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Quickshell.execDetached(["xdg-open", root.ev.htmlLink])
                    if (popout.closePopout) popout.closePopout()
                }
            }
        }
    }
}
