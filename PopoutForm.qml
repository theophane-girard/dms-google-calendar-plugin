import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Formulaire de création d'événement
Flickable {
    id: root
    property var popout: null

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
                text: popout._formatDate(popout.anchorDate)
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

        // Times
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

        // Buttons
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
                            popout.mode = "list"
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
                        onClicked: popout.mode = "list"
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
                        popout.submitForm(
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
