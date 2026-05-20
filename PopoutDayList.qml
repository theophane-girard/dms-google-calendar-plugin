import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Liste verticale des jours visibles (header + all-day banners + clusters horaires).
DankListView {
    id: dayList
    property var popout: null

    clip: true
    spacing: Theme.spacingM
    model: popout ? popout.groupedDays : []

    // ── Now-indicator (séparateur entre clusters / au-dessus / dessous) ────
    Component {
        id: nowSeparatorComponent
        Item {
            width: parent ? parent.width : 0
            height: 18

            StyledText {
                id: nowLbl
                text: popout._fmtTime(popout.nowTick)
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
                    text: popout._fmtTime(popout.nowTick)
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

    // ── Day delegate ───────────────────────────────────────────────────────
    delegate: Column {
        id: dayDelegate
        width: dayList.width
        spacing: Theme.spacingXS

        property var dayInfo: modelData
        property bool isToday: popout._sameDay(dayInfo.date, popout.nowTick)
        property int totalCount: dayInfo.allDay.length + dayInfo.timed.length

        property var nowPlacement: {
            if (!isToday) return { type: "none" }
            var c = dayInfo.clusters
            if (c.length === 0) return { type: "none" }
            var now = popout.nowTick.getTime()
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

        Row {
            width: parent.width
            spacing: Theme.spacingS
            StyledText {
                text: popout._fmtDayHeader(dayDelegate.dayInfo.date)
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

        // Placeholder pour jour vide
        StyledText {
            visible: dayDelegate.totalCount === 0
            text: "Rien de prévu"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            opacity: 0.7
            leftPadding: Theme.spacingS
            topPadding: Theme.spacingXS
            bottomPadding: Theme.spacingXS
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
                    var f = popout.focusables[popout.focusedIndex]
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

                StyledText {
                    visible: !!modelData.calendarSummary
                    text: popout._fmtSourceLabel(modelData.calendarSummary)
                    color: Theme.onPrimary
                    opacity: 0.65
                    font.pixelSize: Theme.fontSizeSmall - 2
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: Theme.spacingS
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                    width: Math.min(implicitWidth, parent.width * 0.3)
                }

                MouseArea {
                    id: allDayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: popout.openEventDetails(modelData)
                }
            }
        }

        // Now-line "before"
        Loader {
            width: parent.width
            active: dayDelegate.nowPlacement.type === "before"
            sourceComponent: nowSeparatorComponent
        }

        // Clusters horaires
        Repeater {
            model: dayDelegate.dayInfo.clusters

            delegate: Column {
                id: clusterDelegate
                width: dayDelegate.width
                spacing: 0

                property var cluster: modelData
                property int clusterIndex: index
                property real clusterHeight: cluster.height

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
                                if (evEnd < popout.nowTick) return "past"
                                if (evStart <= popout.nowTick && evEnd >= popout.nowTick) return "ongoing"
                                return "future"
                            }
                            property bool focused: {
                                var f = popout.focusables[popout.focusedIndex]
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
                                    if (tileRect.ev.calendarColor) return tileRect.ev.calendarColor
                                    return Theme.primary
                                }
                            }

                            StyledText {
                                id: tileHint
                                visible: tileRect.height >= 30 && tileRect.ev.calendarSummary
                                text: popout._fmtSourceLabel(tileRect.ev.calendarSummary)
                                color: tileRect.ev.calendarColor || Theme.surfaceVariantText
                                opacity: 0.75
                                font.pixelSize: Theme.fontSizeSmall - 2
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.rightMargin: 6
                                anchors.topMargin: 4
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignRight
                                width: Math.min(implicitWidth, tileRect.width * 0.4)
                                z: 2
                            }

                            Column {
                                anchors.left: tileAccent.right
                                anchors.leftMargin: Theme.spacingXS
                                anchors.right: tileHint.visible ? tileHint.left : parent.right
                                anchors.rightMargin: Theme.spacingXS
                                anchors.top: parent.top
                                anchors.topMargin: tileRect.height < 40 ? 2 : 4
                                spacing: 0
                                clip: true

                                StyledText {
                                    width: parent.width
                                    visible: tileRect.height < 40
                                    text: popout._fmtTime(tileRect.evStart) + "  " + (tileRect.ev.title || "(sans titre)")
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    width: parent.width
                                    visible: tileRect.height >= 40
                                    text: popout._fmtTime(tileRect.evStart) + " – " + popout._fmtTime(tileRect.evEnd)
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
                                onClicked: popout.openEventDetails(tileRect.ev)
                            }
                        }
                    }

                    // Now-line à l'intérieur du cluster
                    Loader {
                        active: dayDelegate.nowPlacement.type === "in"
                                && dayDelegate.nowPlacement.clusterIndex === clusterDelegate.clusterIndex
                        anchors.left: parent.left
                        anchors.right: parent.right
                        y: active ? (dayDelegate.nowPlacement.offsetMin * popout.pxPerMin - 9) : 0
                        height: 18
                        sourceComponent: nowInClusterComponent
                        z: 100
                    }
                }

                Loader {
                    width: parent.width
                    active: dayDelegate.nowPlacement.type === "between"
                            && dayDelegate.nowPlacement.clusterIndex === clusterDelegate.clusterIndex
                    sourceComponent: nowSeparatorComponent
                }
            }
        }

        Loader {
            width: parent.width
            active: dayDelegate.nowPlacement.type === "after"
            sourceComponent: nowSeparatorComponent
        }
    }
}
