import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ImAgentHub

// 邀请成员对话框 —— 从联系人列表中多选，批量邀请进群
Dialog {
    id: inviteMemberDialog
    title: "邀请成员到「" + groupName + "」"
    anchors.centerIn: parent
    modal: true
    width: 340
    height: 480
    closePolicy: Popup.CloseOnEscape

    // ── 外部属性 ─────────────────────────────────────────────────────────────
    property string groupId: ""
    property string groupName: ""
    property var existingMemberIds: []   // 已在群中的用户ID数组，用于过滤
    property var contactsList: []        // 原始联系人数组 [{userId, nickname, avatar}]

    // ── 内部状态 ─────────────────────────────────────────────────────────────
    property var selectedIds: []         // 已勾选的用户ID数组
    property string filterText: ""

    // 打开时重置状态
    onOpened: {
        selectedIds = []
        filterText = ""
        filterField.text = ""
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // 搜索栏
        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: 4
            color: "#f5f5f5"
            border.color: filterField.activeFocus ? "#07c160" : "#e0e0e0"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 6
                spacing: 4

                Label {
                    text: "\uD83D\uDD0D"
                    font.pixelSize: 13; color: "#999"
                    Layout.alignment: Qt.AlignVCenter
                }

                TextField {
                    id: filterField
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    placeholderText: "搜索联系人"
                    placeholderTextColor: "#bbb"
                    font.pixelSize: 13; color: "#333"
                    background: Item {}
                    verticalAlignment: Text.AlignVCenter
                    onTextChanged: inviteMemberDialog.filterText = text
                }

                Label {
                    text: "✕"
                    font.pixelSize: 12; color: "#999"
                    visible: filterField.text.length > 0
                    Layout.alignment: Qt.AlignVCenter
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: filterField.text = ""
                    }
                }
            }
        }

        // 联系人列表（排除已在群中的成员）
        ListView {
            id: candidateList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            model: {
                var result = []
                for (var i = 0; i < inviteMemberDialog.contactsList.length; i++) {
                    var item = inviteMemberDialog.contactsList[i]
                    var uid = item["userId"] || item["id"] || ""
                    if (!uid || uid.length === 0) continue
                    if (inviteMemberDialog.existingMemberIds.indexOf(uid) >= 0) continue
                    var nick = item["nickname"] || item["nick"] || ""
                    if (inviteMemberDialog.filterText.length > 0) {
                        var ft = inviteMemberDialog.filterText.toLowerCase()
                        if (nick.toLowerCase().indexOf(ft) < 0 && uid.toLowerCase().indexOf(ft) < 0)
                            continue
                    }
                    result.push({ userId: uid, nickname: nick,
                                  avatar: item["avatar"] || item["avatarUrl"] || "" })
                }
                return result
            }

            delegate: Rectangle {
                id: candidateDelegate
                width: candidateList.width
                height: 50
                color: checkHover.containsMouse ? "#f5f5f5" : "white"

                required property var modelData
                property bool checked: inviteMemberDialog.selectedIds.indexOf(modelData.userId) >= 0

                MouseArea {
                    id: checkHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var uid = candidateDelegate.modelData.userId
                        var ids = inviteMemberDialog.selectedIds.slice()
                        var idx = ids.indexOf(uid)
                        if (idx >= 0)
                            ids.splice(idx, 1)
                        else
                            ids.push(uid)
                        inviteMemberDialog.selectedIds = ids
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    // 复选框
                    Rectangle {
                        width: 18; height: 18; radius: 9
                        border.color: candidateDelegate.checked ? "#07c160" : "#ccc"
                        border.width: 2
                        color: candidateDelegate.checked ? "#07c160" : "white"

                        Label {
                            anchors.centerIn: parent
                            text: "✓"
                            font.pixelSize: 11; color: "white"
                            visible: candidateDelegate.checked
                        }
                    }

                    // 头像
                    Rectangle {
                        width: 32; height: 32; radius: 4
                        color: "#07c160"

                        Image {
                            anchors.fill: parent
                            source: {
                                var u = candidateDelegate.modelData.avatar || ""
                                if (u.length > 0 && u.charAt(0) === '/')
                                    return HttpClient.baseUrl + u
                                return u
                            }
                            visible: status === Image.Ready
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(64, 64)
                            asynchronous: true
                            cache: true
                        }
                        Label {
                            anchors.centerIn: parent
                            text: (candidateDelegate.modelData.nickname || "?").charAt(0).toUpperCase()
                            color: "white"; font.pixelSize: 12; font.bold: true
                            visible: parent.children[0].status !== Image.Ready
                        }
                    }

                    Label {
                        text: candidateDelegate.modelData.nickname || candidateDelegate.modelData.userId
                        font.pixelSize: 13; color: "#333"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left; anchors.leftMargin: 52
                    anchors.right: parent.right
                    height: 1; color: "#f0f0f0"
                }
            }

            // 无可邀请联系人时的空状态
            Label {
                anchors.centerIn: parent
                text: "没有可邀请的联系人"
                color: "#bbb"; font.pixelSize: 13
                visible: candidateList.count === 0
            }
        }

        // 底部：已选人数 + 操作按钮
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: inviteMemberDialog.selectedIds.length > 0
                      ? "已选 " + inviteMemberDialog.selectedIds.length + " 人"
                      : ""
                font.pixelSize: 12; color: "#666"
                Layout.fillWidth: true
            }

            Button {
                text: "取消"
                onClicked: inviteMemberDialog.reject()
            }

            Button {
                text: "确认邀请"
                enabled: inviteMemberDialog.selectedIds.length > 0
                highlighted: inviteMemberDialog.selectedIds.length > 0
                onClicked: inviteMemberDialog.accept()
            }
        }
    }

    // 确认后逐一邀请
    onAccepted: {
        var ids = selectedIds.slice()
        for (var i = 0; i < ids.length; i++) {
            HttpClient.inviteToGroup(groupId, ids[i])
        }
    }
}
