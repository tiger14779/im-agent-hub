import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 联系人列表组件 —— 显示联系人/会话列表，支持头像、昵称、最后消息、未读角标
ListView {
    id: contactList
    clip: true

    property string activeUserId: ""   // 当前选中的联系人ID
    property string serverUrl: ""      // 服务器地址（用于拼接头像URL）
    signal contactClicked(string cUserId)       // 左键点击联系人
    signal contactRightClicked(string cUserId)  // 右键点击联系人（打开编辑）

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

            // 头像区域
            Rectangle {
                width: 40; height: 40; radius: 4
                color: "#07c160"
                Layout.alignment: Qt.AlignVCenter

                // 有头像URL则显示图片，否则显示昵称首字母
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
                    spacing: 6

                    Label {
                        text: model.nickname || model.userId
                        color: "#333"
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        implicitWidth: statusLabel.implicitWidth + 8
                        implicitHeight: 16
                        radius: 8
                        color: statusBackgroundColor(model.onlineStatus)
                        visible: statusLabel.text.length > 0
                        Layout.alignment: Qt.AlignVCenter

                        Label {
                            id: statusLabel
                            anchors.centerIn: parent
                            text: statusText(model.onlineStatus)
                            color: statusTextColor(model.onlineStatus)
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }

                    Rectangle {
                        implicitWidth: unreadPillLabel.implicitWidth + 10
                        implicitHeight: 16
                        radius: 8
                        color: "#fa5151"
                        visible: model.unreadCount > 0
                        Layout.alignment: Qt.AlignVCenter

                        Label {
                            id: unreadPillLabel
                            anchors.centerIn: parent
                            text: model.unreadCount > 99 ? "99+" : String(model.unreadCount)
                            color: "white"
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }

                    Label {
                        text: model.lastTime > 0 ? formatTime(model.lastTime) : ""
                        color: "#b0b0b0"
                        font.pixelSize: 10
                        visible: text.length > 0
                    }
                }

                Label {
                    text: model.lastMessage || ""
                    color: "#999"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Layout.fillWidth: true
                    visible: text.length > 0
                }
            }
        }

        // 底部分隔线
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.leftMargin: 62
            anchors.right: parent.right
            height: 1
            color: "#e0e0e0"
        }
    }

    // 格式化时间：今天显示 HH:mm，其他显示 M/D
    function formatTime(ts) {
        var d = new Date(ts)
        var now = new Date()
        if (d.toDateString() === now.toDateString()) {
            return d.getHours().toString().padStart(2, '0') + ":" +
                   d.getMinutes().toString().padStart(2, '0')
        }
        return (d.getMonth() + 1) + "/" + d.getDate()
    }

    function statusText(status) {
        var text = "离线"
        if (status === "online") {
            text = "在线"
        } else if (status === "background") {
            text = "后台"
        }
        return text
    }

    function statusBackgroundColor(status) {
        if (status === "online") {
            return "#e8f7ee"
        }
        if (status === "background") {
            return "#fff4db"
        }
        return "#f1f3f5"
    }

    function statusTextColor(status) {
        if (status === "online") {
            return "#1f9d55"
        }
        if (status === "background") {
            return "#b7791f"
        }
        return "#6b7280"
    }
}
