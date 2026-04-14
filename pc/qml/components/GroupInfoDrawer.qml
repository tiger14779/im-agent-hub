import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ImAgentHub

// 群组信息抽屉 —— 从聊天区域右侧滑入，展示群成员列表，支持邀请/踢出
Drawer {
    id: groupInfoDrawer
    edge: Qt.RightEdge
    width: 240
    modal: false
    interactive: false   // 不允许手势拖动关闭，由代码控制

    // ── 外部属性 ───────────────────────────────────────────────────────────────
    property string groupId: ""
    property string groupName: ""
    property string ownerStaffId: ""        // 群主 staffID，用于判断是否可踢出
    property var members: []                // [{userId, nickname, avatarUrl, role}]

    // 当 members 属性改变时，同步到 ListModel
    onMembersChanged: {
        memberListModel.clear()
        for (var i = 0; i < members.length; i++) {
            var m = members[i]
            memberListModel.append({
                mUserId: m["userId"] || m.userId || "",
                mNickname: m["nickname"] || m.nickname || "",
                mAvatarUrl: m["avatarUrl"] || m.avatarUrl || "",
                mRole: m["role"] || m.role || "member"
            })
        }
    }

    // 内部 ListModel，确保 ListView 正确渲染
    ListModel { id: memberListModel }

    // 显式填充函数 —— 比 onMembersChanged 更可靠，由 ChatPage.openGroupInfoDrawer 调用
    function initMembers(arr) {
        memberListModel.clear()
        for (var i = 0; i < arr.length; i++) {
            var m = arr[i]
            memberListModel.append({
                mUserId:    String(m.userId    || m["userId"]    || ""),
                mNickname:  String(m.nickname  || m["nickname"]  || ""),
                mAvatarUrl: String(m.avatarUrl || m["avatarUrl"] || ""),
                mRole:      String(m.role      || m["role"]      || "member")
            })
        }
    }

    // ── 信号 ──────────────────────────────────────────────────────────────────
    signal inviteMembersClicked()           // 点击「邀请成员」按钮

    // ── 主体 ──────────────────────────────────────────────────────────────────
    // 使用锚点布局代替 ColumnLayout+fillHeight，避免 Drawer 在 Page 内时高度循环依赖
    Item {
        anchors.fill: parent

        // 标题栏
        Rectangle {
            id: titleBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 50
            color: "#f5f5f5"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12

                Label {
                    text: groupName + (memberListModel.count > 0 ? "(" + memberListModel.count + ")" : "")
                    font.pixelSize: 14; font.bold: true; color: "#333"
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Label {
                    text: "✕"
                    font.pixelSize: 14; color: "#666"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: groupInfoDrawer.close()
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 1; color: "#e0e0e0"
            }
        }

        // 邀请成员按钮
        Rectangle {
            id: inviteBar
            anchors.top: titleBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 44
            color: "white"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 12
                spacing: 8

                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: "#e8f7ee"
                    Label {
                        anchors.centerIn: parent
                        text: "+"
                        font.pixelSize: 18; color: "#07c160"; font.bold: true
                    }
                }

                Label {
                    text: "邀请成员"
                    font.pixelSize: 13; color: "#07c160"
                    Layout.fillWidth: true
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: groupInfoDrawer.inviteMembersClicked()
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 1; color: "#f0f0f0"
            }
        }

        // 成员数量标签
        Rectangle {
            id: countBar
            anchors.top: inviteBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28
            color: "#f8f8f8"

            Label {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                text: "群成员  " + memberListModel.count + " 人"
                font.pixelSize: 11; color: "#999"
            }
        }

        // 解散群按钮（仅群主可见，锚到底部）
        Rectangle {
            id: dissolveBar
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: visible ? 48 : 0
            color: "white"
            visible: groupInfoDrawer.ownerStaffId === HttpClient.serviceUserId

            Rectangle {
                anchors.top: parent.top
                width: parent.width; height: 1; color: "#f0f0f0"
            }

            Label {
                anchors.centerIn: parent
                text: "解散群组"
                font.pixelSize: 14; color: "#e74c3c"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: dissolveConfirmDialog.open()
            }
        }

        // 成员列表 —— 锚定在 countBar 和 dissolveBar 之间，充满剩余高度
        ListView {
            id: memberListView
            anchors.top: countBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: dissolveBar.top
            clip: true
            model: memberListModel

            delegate: Rectangle {
                id: memberDelegate
                width: memberListView.width
                height: 50
                color: memberHover.containsMouse ? "#f0f0f0" : "white"

                // 右键菜单（仅非群主可踢出）
                MouseArea {
                    id: memberHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.RightButton
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton
                                && model.mRole !== "owner") {
                            kickMenu.targetId   = model.mUserId
                            kickMenu.targetNick = model.mNickname
                            kickMenu.popup()
                        }
                    }
                }

                Menu {
                    id: kickMenu
                    property string targetId: ""
                    property string targetNick: ""
                    MenuItem {
                        text: "踢出群聊"
                        onTriggered: {
                            kickConfirmDialog.targetId   = kickMenu.targetId
                            kickConfirmDialog.targetNick = kickMenu.targetNick
                            kickConfirmDialog.open()
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 12
                    spacing: 10

                    // 小头像
                    Rectangle {
                        width: 30; height: 30; radius: 4
                        color: "#07c160"

                        Image {
                            anchors.fill: parent
                            source: {
                                var u = model.mAvatarUrl || ""
                                if (u.length > 0 && u.charAt(0) === '/')
                                    return HttpClient.baseUrl + u
                                return u
                            }
                            visible: status === Image.Ready
                            fillMode: Image.PreserveAspectCrop
                        }
                        Label {
                            anchors.centerIn: parent
                            text: (model.mNickname || "?").charAt(0).toUpperCase()
                            color: "white"; font.pixelSize: 12; font.bold: true
                            visible: parent.children[0].status !== Image.Ready
                        }
                    }

                    Label {
                        text: model.mNickname || model.mUserId
                        font.pixelSize: 13; color: "#333"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // 群主徽章
                    Rectangle {
                        width: 28; height: 16; radius: 3
                        color: "#fff3cd"
                        visible: model.mRole === "owner"
                        Label {
                            anchors.centerIn: parent
                            text: "群主"
                            font.pixelSize: 9; color: "#856404"
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left; anchors.leftMargin: 54
                    anchors.right: parent.right
                    height: 1; color: "#f0f0f0"
                }
            }
        }
    }

    // 踢出确认对话框
    Dialog {
        id: kickConfirmDialog
        title: "确认踢出"
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true

        property string targetId: ""
        property string targetNick: ""

        Label {
            text: "确定将「" + kickConfirmDialog.targetNick + "」踢出群聊吗？"
            wrapMode: Text.Wrap
            width: 220
        }

        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            HttpClient.kickFromGroup(groupInfoDrawer.groupId, kickConfirmDialog.targetId)
        }
    }

    // 解散群确认对话框
    Dialog {
        id: dissolveConfirmDialog
        title: "确认解散群组"
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true

        Label {
            text: "解散后群组将无法恢复，所有成员将被移出。\n确定要解散「" + groupInfoDrawer.groupName + "」吗？"
            wrapMode: Text.Wrap
            width: 240
        }

        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            HttpClient.dissolveGroup(groupInfoDrawer.groupId)
            groupInfoDrawer.close()
        }
    }
}
