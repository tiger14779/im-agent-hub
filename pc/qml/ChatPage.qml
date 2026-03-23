import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import ImAgentHub

Page {
    id: chatRoot
    property string staffUserId: ""
    property string staffNickname: ""
    property string authToken: ""
    property string serverUrl: ""
    property string activeChatId: ""
    property string activeChatName: ""

    // Current tab: 0=chats, 1=contacts
    property int currentTab: 0

    background: Rectangle { color: "#ebebeb" }

    ChatModel { id: chatModel }
    ContactModel { id: contactModel }

    // Resolve relative URLs (/api/files/...) to absolute using server base URL
    function resolveUrl(url) {
        if (url && url.length > 0 && url.charAt(0) === '/')
            return HttpClient.baseUrl + url
        return url ?? ""
    }

    Component.onCompleted: {
        chatModel.setSelfId(staffUserId)
        HttpClient.getContacts()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Left icon sidebar (WeChat-style) ──────────────
        Rectangle {
            Layout.preferredWidth: 54
            Layout.fillHeight: true
            color: "#2e2e2e"

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 12
                spacing: 4

                // Staff avatar
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 36; height: 36; radius: 6
                    color: "#07c160"
                    Label {
                        anchors.centerIn: parent
                        text: (staffNickname || "S").charAt(0).toUpperCase()
                        color: "white"; font.pixelSize: 16; font.bold: true
                    }
                }

                Item { height: 16 }

                // Chat tab icon
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 40; height: 40; radius: 6
                    color: currentTab === 0 ? "#444" : "transparent"
                    Label {
                        anchors.centerIn: parent
                        text: "\uD83D\uDCAC"   // 💬
                        font.pixelSize: 20
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: currentTab = 0
                    }
                }

                // Contacts tab icon
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 40; height: 40; radius: 6
                    color: currentTab === 1 ? "#444" : "transparent"
                    Label {
                        anchors.centerIn: parent
                        text: "\uD83D\uDC64"   // 👤
                        font.pixelSize: 20
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: currentTab = 1
                    }
                }

                Item { Layout.fillHeight: true }

                // Settings placeholder
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 12
                    width: 40; height: 40; radius: 6
                    color: "transparent"
                    Label {
                        anchors.centerIn: parent
                        text: "\u2699"   // ⚙
                        font.pixelSize: 20
                        color: "#999"
                    }
                }
            }
        }

        // ── Middle panel (contact list / conversation list) ─
        Rectangle {
            Layout.preferredWidth: 260
            Layout.fillHeight: true
            color: "#e7e7e7"

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Panel header
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    color: "#e7e7e7"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8

                        Label {
                            text: currentTab === 0 ? "\u804A\u5929" : "\u901A\u8BAF\u5F55"
                            color: "#333"; font.pixelSize: 15; font.bold: true
                            Layout.fillWidth: true
                        }

                        // Add contact button (contacts tab only)
                        RoundButton {
                            visible: currentTab === 1
                            width: 28; height: 28; radius: 14
                            flat: true
                            contentItem: Label {
                                text: "+"
                                font.pixelSize: 18; color: "#555"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: addContactDialog.open()
                        }
                    }

                    // Bottom border
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width; height: 1; color: "#d6d6d6"
                    }
                }

                // Contact list
                ContactList {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: contactModel
                    activeUserId: activeChatId
                    onContactClicked: function(cUserId) {
                        openChat(cUserId)
                    }
                    onContactRightClicked: function(cUserId) {
                        contextUserId = cUserId
                        // Show edit dialog
                        editRemarkField.text = contactModel.getDisplayName(cUserId)
                        editAvatarField.text = contactModel.getAvatar(cUserId)
                        editContactDialog.open()
                    }
                }
            }
        }

        // ── Right chat area ──────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#f5f5f5"

            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                visible: activeChatId.length > 0

                // Chat header
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    color: "#f5f5f5"

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: activeChatName || activeChatId
                        font.pixelSize: 15; font.bold: true; color: "#333"
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width; height: 1; color: "#ddd"
                    }
                }

                // Message list
                MessageList {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: chatModel
                    selfId: staffUserId
                }

                // Chat input toolbar + text area
                ChatInput {
                    Layout.fillWidth: true
                    onSendText: function(text) {
                        sendTextMessage(text)
                    }
                    onSendFile: function(filePath) {
                        sendFileMessage(filePath)
                    }
                    onSendImage: function(filePath) {
                        sendImageMessage(filePath)
                    }
                }
            }

            // Empty state
            ColumnLayout {
                anchors.centerIn: parent
                visible: activeChatId.length === 0
                spacing: 8
                Label {
                    text: "\uD83D\uDCAC"
                    font.pixelSize: 48
                    Layout.alignment: Qt.AlignHCenter
                    opacity: 0.3
                }
                Label {
                    text: "\u9009\u62E9\u8054\u7CFB\u4EBA\u5F00\u59CB\u804A\u5929"
                    color: "#bbb"; font.pixelSize: 14
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    // ── Dialogs ──────────────────────────────────────────

    property string contextUserId: ""

    // Add Contact Dialog
    Dialog {
        id: addContactDialog
        title: "\u6DFB\u52A0\u7528\u6237"
        anchors.centerIn: parent
        modal: true; width: 320

        ColumnLayout {
            width: parent.width; spacing: 12
            TextField {
                id: newNickname
                placeholderText: "\u6635\u79F0 (\u5FC5\u586B)"
                Layout.fillWidth: true
            }
            TextField {
                id: newRemark
                placeholderText: "\u5907\u6CE8 (\u53EF\u9009)"
                Layout.fillWidth: true
            }
            TextField {
                id: newAvatar
                placeholderText: "\u5934\u50CFURL (\u53EF\u9009)"
                Layout.fillWidth: true
            }
        }

        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            if (newNickname.text.trim().length > 0) {
                HttpClient.addContact(newNickname.text.trim(),
                                       newRemark.text.trim(),
                                       newAvatar.text.trim())
            }
            newNickname.text = ""; newRemark.text = ""; newAvatar.text = ""
        }
    }

    // Edit Contact Dialog
    Dialog {
        id: editContactDialog
        title: "\u7F16\u8F91\u8054\u7CFB\u4EBA"
        anchors.centerIn: parent
        modal: true; width: 320

        ColumnLayout {
            width: parent.width; spacing: 12
            Label { text: "\u7528\u6237ID: " + contextUserId; color: "#666"; font.pixelSize: 12 }
            TextField {
                id: editRemarkField
                placeholderText: "\u5907\u6CE8"
                Layout.fillWidth: true
            }
            TextField {
                id: editAvatarField
                placeholderText: "\u5934\u50CFURL"
                Layout.fillWidth: true
            }
        }

        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            HttpClient.updateContact(contextUserId,
                                      editRemarkField.text.trim(),
                                      editAvatarField.text.trim())
        }
    }

    // ── Functions ────────────────────────────────────────

    function openChat(userId) {
        activeChatId = userId
        activeChatName = contactModel.getDisplayName(userId)
        chatModel.clear()
        contactModel.clearUnread(userId)
        // Load history from OpenIM via our backend WS
        WsClient.loadHistory(userId)
    }

    function sendTextMessage(text) {
        var content = JSON.stringify({"text": text})
        var msgId = chatModel.addPendingMessage(activeChatId, 101, text)
        WsClient.sendMessage(activeChatId, 101, content, msgId)
        contactModel.updateLastMessage(activeChatId, text, Date.now())
    }

    function sendImageMessage(filePath) {
        // Upload file first, then send image message
        HttpClient.uploadFile(filePath)
        // The result will come back via uploadSuccess signal
    }

    function sendFileMessage(filePath) {
        HttpClient.uploadFile(filePath)
    }

    // ── Signal handlers ─────────────────────────────────

    Connections {
        target: HttpClient

        function onContactsLoaded(contacts) {
            contactModel.loadFromJson(contacts)
        }
        function onContactAdded(contact) {
            contactModel.addOrUpdate(
                contact["userId"], contact["nickname"],
                contact["remark"] ?? "", contact["avatar"] ?? ""
            )
        }
        function onContactUpdated(contact) {
            var uid = contact["userId"]
            contactModel.updateRemark(uid, contact["remark"] ?? "")
            contactModel.updateAvatar(uid, contact["avatar"] ?? "")
            if (uid === activeChatId) {
                activeChatName = contactModel.getDisplayName(uid)
            }
        }
        function onUploadSuccess(url) {
            if (activeChatId.length === 0) return
            // Determine type by extension
            var lower = url.toLowerCase()
            if (lower.endsWith(".png") || lower.endsWith(".jpg") ||
                lower.endsWith(".jpeg") || lower.endsWith(".gif") ||
                lower.endsWith(".webp") || lower.endsWith(".bmp")) {
                // Image message
                var imgContent = JSON.stringify({
                    "sourcePicture": {"url": url, "width": 0, "height": 0, "size": 0, "type": "image/png"},
                    "bigPicture":    {"url": url, "width": 0, "height": 0, "size": 0, "type": "image/png"},
                    "snapshotPicture": {"url": url, "width": 0, "height": 0, "size": 0, "type": "image/png"}
                })
                var imgMsgId = chatModel.addPendingMessage(activeChatId, 102, "", resolveUrl(url))
                WsClient.sendMessage(activeChatId, 102, imgContent, imgMsgId)
                contactModel.updateLastMessage(activeChatId, "[\u56FE\u7247]", Date.now())
            } else {
                // File message
                var fileName = url.split("/").pop()
                var fileContent = JSON.stringify({
                    "fileName": fileName, "sourceUrl": url, "fileSize": 0
                })
                var fileMsgId = chatModel.addPendingMessage(activeChatId, 105, "", "", fileName, 0)
                WsClient.sendMessage(activeChatId, 105, fileContent, fileMsgId)
                contactModel.updateLastMessage(activeChatId, "[\u6587\u4EF6]", Date.now())
            }
        }
    }

    Connections {
        target: WsClient

        function onNewMessage(msg) {
            var sendID = msg["sendID"] ?? ""
            var recvID = msg["recvID"] ?? ""
            var contentType = msg["contentType"] ?? 101
            var contentStr = msg["content"] ?? ""

            // Parse content JSON
            var parsed = {}
            try { parsed = JSON.parse(contentStr) } catch(e) { parsed = {"content": contentStr} }

            // Build a ChatModel-compatible object
            var chatMsg = {
                "clientMsgID": msg["clientMsgID"] ?? msg["serverMsgID"] ?? "",
                "sendID": sendID,
                "recvID": recvID,
                "contentType": contentType,
                "sendTime": msg["sendTime"] ?? Date.now(),
                "status": 2,
                "textElem": contentType === 101 ? parsed : undefined,
                "content": contentType === 101 ? (parsed["text"] ?? parsed["content"] ?? contentStr) : undefined,
                "pictureElem": contentType === 102 ? (function() {
                    var sp = parsed["sourcePicture"] ?? {"url": parsed["url"] ?? ""}
                    var bp = parsed["bigPicture"] ?? {"url": parsed["url"] ?? ""}
                    sp["url"] = resolveUrl(sp["url"] ?? "")
                    bp["url"] = resolveUrl(bp["url"] ?? "")
                    return {"sourcePicture": sp, "bigPicture": bp}
                })() : undefined,
                "fileElem": contentType === 105 ? {
                    "fileName": parsed["fileName"] ?? parsed["name"] ?? "",
                    "sourceUrl": resolveUrl(parsed["sourceUrl"] ?? parsed["url"] ?? ""),
                    "fileSize": parsed["fileSize"] ?? parsed["size"] ?? 0
                } : undefined,
                "voiceElem": contentType === 103 ? {
                    "sourceUrl": resolveUrl(parsed["url"] ?? parsed["sourceUrl"] ?? ""),
                    "duration": parsed["duration"] ?? 0
                } : undefined
            }

            // If this message is for the active chat, add to model
            var peerID = sendID === staffUserId ? recvID : sendID
            if (peerID === activeChatId) {
                chatModel.appendMessage(chatMsg)
            }

            // Update contact list
            var preview = ""
            if (contentType === 101) preview = parsed["text"] ?? parsed["content"] ?? contentStr
            else if (contentType === 102) preview = "[\u56FE\u7247]"
            else if (contentType === 103) preview = "[\u8BED\u97F3]"
            else if (contentType === 105) preview = "[\u6587\u4EF6]"

            if (peerID.length > 0) {
                contactModel.updateLastMessage(peerID, preview, msg["sendTime"] ?? Date.now())
                if (peerID !== activeChatId) {
                    contactModel.incrementUnread(peerID)
                }
            }
        }

        function onMessageAck(clientMsgId, status, serverMsgId, sendTime) {
            chatModel.updateStatus(clientMsgId, status)
        }

        function onHistoryLoaded(peerUserId, messages) {
            if (peerUserId !== activeChatId) return
            chatModel.clear()
            for (var i = 0; i < messages.length; i++) {
                var m = messages[i]
                var ct = m["contentType"] ?? 101
                var contentStr = m["content"] ?? ""
                var parsed = {}
                try { parsed = JSON.parse(contentStr) } catch(e) { parsed = {"content": contentStr} }

                var obj = {
                    "clientMsgID": m["clientMsgID"] ?? m["serverMsgID"] ?? "",
                    "sendID": m["sendID"] ?? "",
                    "recvID": m["recvID"] ?? "",
                    "contentType": ct,
                    "sendTime": m["sendTime"] ?? 0,
                    "status": 2,
                    "textElem": ct === 101 ? parsed : undefined,
                    "content": ct === 101 ? (parsed["text"] ?? parsed["content"] ?? contentStr) : undefined,
                    "pictureElem": ct === 102 ? (function() {
                        var sp = parsed["sourcePicture"] ?? {"url": parsed["url"] ?? ""}
                        var bp = parsed["bigPicture"] ?? {"url": parsed["url"] ?? ""}
                        sp["url"] = resolveUrl(sp["url"] ?? "")
                        bp["url"] = resolveUrl(bp["url"] ?? "")
                        return {"sourcePicture": sp, "bigPicture": bp}
                    })() : undefined,
                    "fileElem": ct === 105 ? {
                        "fileName": parsed["fileName"] ?? parsed["name"] ?? "",
                        "sourceUrl": resolveUrl(parsed["sourceUrl"] ?? parsed["url"] ?? ""),
                        "fileSize": parsed["fileSize"] ?? parsed["size"] ?? 0
                    } : undefined,
                    "voiceElem": ct === 103 ? {
                        "sourceUrl": resolveUrl(parsed["url"] ?? parsed["sourceUrl"] ?? ""),
                        "duration": parsed["duration"] ?? 0
                    } : undefined
                }
                chatModel.appendMessage(obj)
            }
        }
    }
}
