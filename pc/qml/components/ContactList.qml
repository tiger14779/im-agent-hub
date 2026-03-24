import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ListView {
    id: contactList
    clip: true

    property string activeUserId: ""
    property string serverUrl: ""
    signal contactClicked(string cUserId)
    signal contactRightClicked(string cUserId)

    delegate: Rectangle {
        width: contactList.width
        height: 62
        color: model.userId === contactList.activeUserId ? "#c4c4c4"
               : (hoverArea.containsMouse ? "#d9d9d9" : "transparent")

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton)
                    contactList.contactRightClicked(model.userId)
                else
                    contactList.contactClicked(model.userId)
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            // Avatar
            Rectangle {
                width: 40; height: 40; radius: 4
                color: "#07c160"
                Layout.alignment: Qt.AlignVCenter

                // If avatar URL available, show image; else show initial
                Image {
                    id: avatarImg
                    anchors.fill: parent
                    source: {
                        var url = model.avatarUrl || ""
                        if (url.length > 0 && url.charAt(0) === '/')
                            return contactList.serverUrl + url
                        return url
                    }
                    visible: status === Image.Ready
                    fillMode: Image.PreserveAspectCrop
                    layer.enabled: true
                    layer.effect: null
                }

                Label {
                    anchors.centerIn: parent
                    text: (model.nickname || model.userId || "?").charAt(0).toUpperCase()
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                    visible: avatarImg.status !== Image.Ready
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        text: model.nickname || model.userId
                        color: "#333"
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Time label (if has last message)
                    Label {
                        text: model.lastTime > 0 ? formatTime(model.lastTime) : ""
                        color: "#b0b0b0"
                        font.pixelSize: 11
                        visible: text.length > 0
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        text: model.lastMessage || ""
                        color: "#999"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: text.length > 0
                    }

                    // Unread badge
                    Rectangle {
                        width: Math.max(18, unreadLabel.implicitWidth + 8)
                        height: 18; radius: 9
                        color: "#fa5151"
                        visible: model.unreadCount > 0

                        Label {
                            id: unreadLabel
                            anchors.centerIn: parent
                            text: model.unreadCount > 99 ? "99+" : String(model.unreadCount)
                            color: "white"
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }
                }
            }
        }

        // Bottom separator
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.leftMargin: 62
            anchors.right: parent.right
            height: 1
            color: "#e0e0e0"
        }
    }

    function formatTime(ts) {
        var d = new Date(ts)
        var now = new Date()
        if (d.toDateString() === now.toDateString()) {
            return d.getHours().toString().padStart(2, '0') + ":" +
                   d.getMinutes().toString().padStart(2, '0')
        }
        return (d.getMonth() + 1) + "/" + d.getDate()
    }
}
