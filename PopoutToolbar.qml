import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Barre d'outils du popout : ◀ Aujourd'hui ▶ | 1j 3j | refresh +
Item {
    id: root
    property var popout: null

    height: 44

    function _focusedKind() {
        var f = popout && popout.focusables[popout.focusedIndex]
        return f ? f.kind : ""
    }

    function _focusedScope() {
        var f = popout && popout.focusables[popout.focusedIndex]
        return (f && f.kind === "scope") ? f.value : -1
    }

    // ── Group gauche : prev / today / next ──────────────────────────────
    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS

        StyledRect {
            width: 32; height: 32; radius: 16
            color: prevMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
            border.width: root._focusedKind() === "prev" ? 2 : 0
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
                onClicked: popout.shiftAnchor(-popout.scopeDays)
            }
        }

        // "Aujourd'hui" — primary style quand la vue inclut today
        StyledRect {
            width: todayLabel.implicitWidth + Theme.spacingM * 2
            height: 32
            radius: Theme.cornerRadius
            color: popout.viewIncludesToday
                ? (todayMouse.containsMouse ? Qt.lighter(Theme.primary, 1.15) : Theme.primary)
                : (todayMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
            border.width: root._focusedKind() === "today" ? 2 : 0
            border.color: popout.viewIncludesToday ? Theme.onPrimary : Theme.primary
            StyledText {
                id: todayLabel
                anchors.centerIn: parent
                text: "Aujourd'hui"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: popout.viewIncludesToday ? Theme.onPrimary : Theme.surfaceText
            }
            MouseArea {
                id: todayMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: popout.resetToToday()
            }
        }

        StyledRect {
            width: 32; height: 32; radius: 16
            color: nextMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
            border.width: root._focusedKind() === "next" ? 2 : 0
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
                onClicked: popout.shiftAnchor(popout.scopeDays)
            }
        }
    }

    // ── Group droite : 1j 3j | refresh + ────────────────────────────────
    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS

        StyledRect {
            width: 44; height: 32
            radius: Theme.cornerRadius
            color: popout.scopeDays === 1
                ? Theme.primary
                : (scope1Mouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
            border.width: root._focusedScope() === 1 ? 2 : 0
            border.color: Theme.primary
            StyledText {
                anchors.centerIn: parent
                text: "1j"
                color: popout.scopeDays === 1 ? Theme.onPrimary : Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
            }
            MouseArea {
                id: scope1Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: popout.scopeDays = 1
            }
        }

        StyledRect {
            width: 44; height: 32
            radius: Theme.cornerRadius
            color: popout.scopeDays === 3
                ? Theme.primary
                : (scope3Mouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
            border.width: root._focusedScope() === 3 ? 2 : 0
            border.color: Theme.primary
            StyledText {
                anchors.centerIn: parent
                text: "3j"
                color: popout.scopeDays === 3 ? Theme.onPrimary : Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
            }
            MouseArea {
                id: scope3Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: popout.scopeDays = 3
            }
        }

        Item { width: Theme.spacingM; height: 1 }

        // Refresh
        StyledRect {
            width: 32; height: 32; radius: 16
            color: refreshMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
            border.width: root._focusedKind() === "refresh" ? 2 : 0
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
                    popout.plugin.refreshEvents()
                    ToastService.showInfo("Google Calendar: rafraîchissement…")
                    refreshSpin.start()
                }
            }
        }

        // + nouvel event
        StyledRect {
            width: 32; height: 32; radius: 16
            color: addMouse.containsMouse ? Qt.lighter(Theme.primary, 1.15) : Theme.primary
            border.width: root._focusedKind() === "add" ? 2 : 0
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
                onClicked: popout.mode = "form"
            }
        }
    }
}
