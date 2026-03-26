import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import ImAgentHub

// 聊天主页 —— 包含左侧导航栏、中间联系人列表、右侧聊天区域
Page {
    id: chatRoot
    property string staffUserId: ""     // 当前客服用户ID
    property string staffNickname: ""   // 当前客服昵称
    property string authToken: ""       // 认证令牌
    property string serverUrl: ""       // 服务器地址
    property string activeChatId: ""    // 当前打开的会话用户ID
    property string activeChatName: ""  // 当前会话用户昵称

    // 分页状态
    property int oldestSeq: 0            // 当前最旧消息的 seq（用于向上加载更多）
    property bool hasMoreHistory: true  // 是否还有更多历史消息
    property bool loadingMore: false    // 是否正在加载更多

    // 当前 Tab页: 0=聊天列表, 1=通讯录
    property int currentTab: 0

    background: Rectangle { color: "#ebebeb" }

    ChatModel { id: chatModel }
    ContactModel { id: contactModel }

    // 将相对URL（/api/files/...）拼接为绝对URL
    function resolveUrl(url) {
        if (url && url.length > 0 && url.charAt(0) === '/')
            return HttpClient.baseUrl + url
        return url ?? ""
    }

    // 页面初始化：设置自己的ID、加载联系人、启动桥接服务
    Component.onCompleted: {
        chatModel.setSelfId(staffUserId)
        HttpClient.getContacts()
        WxBridge.startServer()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── 左侧图标导航栏（微信风格）─────────
        Rectangle {
            Layout.preferredWidth: 54
            Layout.fillHeight: true
            color: "#2e2e2e"

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 12
                spacing: 4

                // 客服头像（取昵称首字母）
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

                // 聊天Tab图标
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 40; height: 40; radius: 6
                    color: currentTab === 0 ? "#444" : "transparent"
                    Label {
                        anchors.centerIn: parent
                        text: "\uD83D\uDCAC"   // 💬
                        font.pixelSize: 20
                    }
                    // 总未读角标
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: -4
                        anchors.topMargin: -4
                        width: Math.max(18, totalUnreadLabel.implicitWidth + 8)
                        height: 18; radius: 9
                        color: "#fa5151"
                        visible: contactModel.totalUnread > 0
                        Label {
                            id: totalUnreadLabel
                            anchors.centerIn: parent
                            text: contactModel.totalUnread > 99 ? "99+" : String(contactModel.totalUnread)
                            color: "white"
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: currentTab = 0
                    }
                }

                // 通讯录Tab图标
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
            }
        }

        // ── 中间面板（联系人列表 / 会话列表）─────
        Rectangle {
            Layout.preferredWidth: 260
            Layout.fillHeight: true
            color: "#e7e7e7"

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // 面板标题栏
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

                        // 添加联系人按钮（仅在通讯录Tab显示）
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

                    // 底部分割线
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width; height: 1; color: "#d6d6d6"
                    }
                }

                // 搜索栏
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    color: "#e7e7e7"

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.topMargin: 4
                        anchors.bottomMargin: 6
                        radius: 4
                        color: "#fff"
                        border.color: searchField.activeFocus ? "#07c160" : "#ddd"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 4
                            spacing: 4

                            // 搜索图标
                            Label {
                                text: "\uD83D\uDD0D"
                                font.pixelSize: 13
                                color: "#999"
                                Layout.alignment: Qt.AlignVCenter
                            }

                            TextField {
                                id: searchField
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                placeholderText: "搜索"
                                placeholderTextColor: "#bbb"
                                font.pixelSize: 13
                                color: "#333"
                                background: Item {}
                                verticalAlignment: Text.AlignVCenter
                                onTextChanged: contactModel.filterText = text
                            }

                            // 清除按钮
                            Label {
                                text: "✕"
                                font.pixelSize: 12
                                color: "#999"
                                visible: searchField.text.length > 0
                                Layout.alignment: Qt.AlignVCenter
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: searchField.text = ""
                                }
                            }
                        }
                    }
                }

                // 联系人列表组件
                ContactList {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: contactModel
                    activeUserId: activeChatId
                    serverUrl: HttpClient.baseUrl
                    onContactClicked: function(cUserId) {
                        openChat(cUserId)
                    }
                    onContactRightClicked: function(cUserId) {
                        contextUserId = cUserId
                        // Show edit dialog
                        editRemarkField.text = contactModel.getNickname(cUserId)
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

                // 聊天头部（显示当前会话名称）
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

                // 消息列表
                MessageList {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: chatModel
                    selfId: staffUserId
                    loadingMore: chatRoot.loadingMore
                    hasMore: chatRoot.hasMoreHistory
                    onRequestLoadMore: chatRoot.loadMoreHistory()
                }

                // 聊天输入栏（工具条 + 文本输入区）
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

            // 空状态（未选择联系人时显示）
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

    // ── 对话框 ───────────────────────────────────

    property string contextUserId: ""         // 右键菜单选中的用户ID
    property string pendingAvatarUrl: ""      // 添加对话框的待上传头像URL
    property string editPendingAvatarUrl: ""  // 编辑对话框的待上传头像URL

    // 头像文件选择器（添加/编辑共用）
    FileDialog {
        id: avatarFileDialog
        title: "\u9009\u62E9\u5934\u50CF"
        nameFilters: ["Image files (*.png *.jpg *.jpeg *.gif *.webp *.bmp)"]
        property string target: ""  // "add" or "edit"
        onAccepted: {
            HttpClient.uploadAvatar(selectedFile)
        }
    }

    Connections {
        target: HttpClient
        function onAvatarUploaded(url) {
            if (avatarFileDialog.target === "add") {
                pendingAvatarUrl = url
            } else {
                editPendingAvatarUrl = url
            }
        }
    }

    // ── 添加联系人对话框 ────────────────────
    Dialog {
        id: addContactDialog
        title: "\u6DFB\u52A0\u7528\u6237"
        anchors.centerIn: parent
        modal: true; width: 320

        ColumnLayout {
            width: parent.width; spacing: 12

            // 头像预览 + 上传按钮
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12
                Rectangle {
                    width: 56; height: 56; radius: 28
                    color: "#07c160"
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: pendingAvatarUrl.length > 0
                                ? (HttpClient.baseUrl + pendingAvatarUrl) : ""
                        visible: status === Image.Ready
                        fillMode: Image.PreserveAspectCrop
                    }
                    Label {
                        anchors.centerIn: parent
                        text: (newNickname.text || "?").charAt(0).toUpperCase()
                        color: "white"; font.pixelSize: 20; font.bold: true
                        visible: pendingAvatarUrl.length === 0
                    }
                }
                Button {
                    text: "\u4E0A\u4F20\u5934\u50CF"
                    onClicked: {
                        avatarFileDialog.target = "add"
                        avatarFileDialog.open()
                    }
                }
            }

            TextField {
                id: newNickname
                placeholderText: "\u6635\u79F0 (\u5FC5\u586B)"
                Layout.fillWidth: true
            }
        }

        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            if (newNickname.text.trim().length > 0) {
                HttpClient.addContact(newNickname.text.trim(),
                                       pendingAvatarUrl)
            }
            newNickname.text = ""; pendingAvatarUrl = ""
        }
        onRejected: {
            newNickname.text = ""; pendingAvatarUrl = ""
        }
    }

    // ── 编辑联系人对话框 ────────────────────
    Dialog {
        id: editContactDialog
        title: "\u7F16\u8F91\u8054\u7CFB\u4EBA"
        anchors.centerIn: parent
        modal: true; width: 320

        ColumnLayout {
            width: parent.width; spacing: 12
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    text: contextUserId
                    readOnly: true
                    selectByMouse: true
                    color: "#666"; font.pixelSize: 12
                    Layout.fillWidth: true
                    background: Rectangle { color: "transparent" }
                }
                Label {
                    text: "\u590D\u5236\u5BF9\u8BDD\u94FE\u63A5"
                    color: "#1a73e8"; font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var link = HttpClient.baseUrl + "/chat?id=" + contextUserId
                            clipHelper.text = link
                            clipHelper.selectAll()
                            clipHelper.copy()
                            copiedTip.visible = true
                            copiedTimer.restart()
                        }
                    }
                }
                Label {
                    id: copiedTip
                    text: "\u2713 \u5DF2\u590D\u5236"
                    color: "#07c160"; font.pixelSize: 11
                    visible: false
                }
                Timer {
                    id: copiedTimer
                    interval: 1500
                    onTriggered: copiedTip.visible = false
                }
                // 隐藏的剪贴板辅助元素
                TextEdit {
                    id: clipHelper
                    visible: false
                }
            }

            // 头像预览 + 上传按钮
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12
                Rectangle {
                    width: 56; height: 56; radius: 28
                    color: "#07c160"
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: {
                            var url = editPendingAvatarUrl.length > 0
                                      ? editPendingAvatarUrl
                                      : editAvatarField.text
                            return url.length > 0 ? (url.charAt(0) === '/' ? HttpClient.baseUrl + url : url) : ""
                        }
                        visible: status === Image.Ready
                        fillMode: Image.PreserveAspectCrop
                    }
                    Label {
                        anchors.centerIn: parent
                        text: (editRemarkField.text || contextUserId || "?").charAt(0).toUpperCase()
                        color: "white"; font.pixelSize: 20; font.bold: true
                        visible: editPendingAvatarUrl.length === 0 && editAvatarField.text.length === 0
                    }
                }
                Button {
                    text: "\u4E0A\u4F20\u5934\u50CF"
                    onClicked: {
                        avatarFileDialog.target = "edit"
                        avatarFileDialog.open()
                    }
                }
            }

            TextField {
                id: editRemarkField
                placeholderText: "\u6635\u79F0"
                Layout.fillWidth: true
            }
            // 隐藏字段：保存原始头像URL供引用
            TextField {
                id: editAvatarField
                visible: false
            }
        }

        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            var avatar = editPendingAvatarUrl.length > 0 ? editPendingAvatarUrl : editAvatarField.text.trim()
            HttpClient.updateContact(contextUserId,
                                      editRemarkField.text.trim(),
                                      avatar)
            editPendingAvatarUrl = ""
        }
        onRejected: {
            editPendingAvatarUrl = ""
        }
    }

    // ── Functions ────────────────────────────────────────

    function openChat(userId) {
        console.log("[ChatPage] openChat:", userId, "wsConnected:", WsClient.connected)
        activeChatId = userId
        activeChatName = contactModel.getNickname(userId)
        chatModel.clear()
        contactModel.clearUnread(userId)
        oldestSeq = 0
        hasMoreHistory = true
        loadingMore = false
        // Load history from OpenIM via our backend WS
        WsClient.loadHistory(userId)
    }

    function sendTextMessage(text) {
        var content = JSON.stringify({"text": text})
        var msgId = chatModel.addPendingMessage(activeChatId, 101, text)
        WsClient.sendMessage(activeChatId, 101, content, msgId)
        contactModel.updateLastMessage(activeChatId, text, Date.now())
        // Push self-sent event to accounting software
        WxBridge.pushMessageEvent(staffUserId, activeChatId, text, true, 1)
    }

    // 加载更多历史消息（向上滚动触发）
    function loadMoreHistory() {
        if (loadingMore || !hasMoreHistory || !activeChatId) return
        loadingMore = true
        WsClient.loadHistory(activeChatId, oldestSeq, 50)
    }

    function sendImageMessage(filePath) {
        // Upload file first, then send image message
        HttpClient.uploadFile(filePath)
        // The result will come back via uploadSuccess signal
    }

    function sendFileMessage(filePath) {
        HttpClient.uploadFile(filePath)
    }

    // ── HttpClient 信号处理 ─────────────────────

    Connections {
        target: HttpClient

        // 联系人列表加载完成
        function onContactsLoaded(contacts) {
            contactModel.loadFromJson(contacts)
        }
        // 新增联系人成功
        function onContactAdded(contact) {
            contactModel.addOrUpdate(
                contact["userId"], contact["nickname"],
                contact["avatar"] ?? ""
            )
        }
        // 更新联系人成功
        function onContactUpdated(contact) {
            var uid = contact["userId"]
            contactModel.updateNickname(uid, contact["nickname"] ?? "")
            contactModel.updateAvatar(uid, contact["avatar"] ?? "")
            if (uid === activeChatId) {
                activeChatName = contactModel.getNickname(uid)
            }
        }
        // 文件上传成功回调 —— 根据上下文判断是普通发送还是桥接器发送
        function onUploadSuccess(url, origName, origSize) {
            console.log("[上传] 成功 url=" + url + " origName=" + origName + " origSize=" + origSize)
            // 检查是否是 WxBridge API 触发的上传
            var bridgeTarget = chatRoot._pendingBridgeTarget
            var bridgeType   = chatRoot._pendingBridgeType
            console.log("[上传] bridgeTarget=" + bridgeTarget + " bridgeType=" + bridgeType)
            if (bridgeTarget.length > 0) {
                chatRoot._pendingBridgeTarget = ""
                chatRoot._pendingBridgeType = ""

                // 根据桥接器指定的类型发送：
                //   "image" (Q0011) → 始终作为图片发送 (contentType=102)
                //   "file"  (Q0030) → 始终作为文件发送 (contentType=105)
                if (bridgeType === "image") {
                    console.log("[上传] 桥接器 → 图片发送 (contentType=102)")
                    var bImgContent = JSON.stringify({
                        "sourcePicture": {"url": url, "width": 0, "height": 0, "size": 0, "type": "image/png"},
                        "bigPicture":    {"url": url, "width": 0, "height": 0, "size": 0, "type": "image/png"},
                        "snapshotPicture": {"url": url, "width": 0, "height": 0, "size": 0, "type": "image/png"}
                    })
                    var bImgMsgId = chatModel.addPendingMessage(bridgeTarget, 102, "", resolveUrl(url))
                    WsClient.sendMessage(bridgeTarget, 102, bImgContent, bImgMsgId)
                    contactModel.updateLastMessage(bridgeTarget, "[\u56FE\u7247]", Date.now())
                    WxBridge.pushMessageEvent(staffUserId, bridgeTarget, "[\u56FE\u7247]", true, 3)
                } else {
                    console.log("[上传] 桥接器 → 文件发送 (contentType=105)")
                    var bFileContent = JSON.stringify({
                        "url": url, "name": origName, "size": origSize
                    })
                    var bFileMsgId = chatModel.addPendingMessage(bridgeTarget, 105, "", "", origName, origSize)
                    WsClient.sendMessage(bridgeTarget, 105, bFileContent, bFileMsgId)
                    contactModel.updateLastMessage(bridgeTarget, "[\u6587\u4EF6]", Date.now())
                    WxBridge.pushMessageEvent(staffUserId, bridgeTarget, "[\u6587\u4EF6]", true, 49)
                }
                return
            }

            if (activeChatId.length === 0) return
            // 根据文件扩展名判断发送类型
            var lower = origName.toLowerCase()
            if (lower.endsWith(".png") || lower.endsWith(".jpg") ||
                lower.endsWith(".jpeg") || lower.endsWith(".gif") ||
                lower.endsWith(".webp") || lower.endsWith(".bmp")) {
                // 图片消息
                var imgContent = JSON.stringify({
                    "sourcePicture": {"url": url, "width": 0, "height": 0, "size": 0, "type": "image/png"},
                    "bigPicture":    {"url": url, "width": 0, "height": 0, "size": 0, "type": "image/png"},
                    "snapshotPicture": {"url": url, "width": 0, "height": 0, "size": 0, "type": "image/png"}
                })
                var imgMsgId = chatModel.addPendingMessage(activeChatId, 102, "", resolveUrl(url))
                WsClient.sendMessage(activeChatId, 102, imgContent, imgMsgId)
                contactModel.updateLastMessage(activeChatId, "[\u56FE\u7247]", Date.now())
            } else {
                // 文件消息 —— 使用 H5 兼容格式 {url, name, size}
                var fileContent = JSON.stringify({
                    "url": url, "name": origName, "size": origSize
                })
                var fileMsgId = chatModel.addPendingMessage(activeChatId, 105, "", "", origName, origSize)
                WsClient.sendMessage(activeChatId, 105, fileContent, fileMsgId)
                contactModel.updateLastMessage(activeChatId, "[\u6587\u4EF6]", Date.now())
            }
        }
    }

    // ── WsClient 信号处理 ─────────────────────

    Connections {
        target: WsClient

        // 收到新消息
        function onNewMessage(msg) {
            var sendID = msg["sendID"] ?? ""
            var recvID = msg["recvID"] ?? ""
            var contentType = msg["contentType"] ?? 101
            var contentStr = msg["content"] ?? ""

            console.log("[ChatPage] onNewMessage: sendID=" + sendID + " recvID=" + recvID
                        + " type=" + contentType + " staffUserId=" + staffUserId
                        + " activeChatId=" + activeChatId)

            // 解析消息内容 JSON
            var parsed = {}
            try { parsed = JSON.parse(contentStr) } catch(e) { parsed = {"content": contentStr} }

            // 构造 ChatModel 兼容的消息对象
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

            // 若此消息属于当前打开的会话，添加到消息列表
            var peerID = sendID === staffUserId ? recvID : sendID
            console.log("[ChatPage] onNewMessage peerID=" + peerID + " activeChatId=" + activeChatId
                        + " match=" + (peerID === activeChatId) + " modelCount=" + chatModel.count)
            if (peerID === activeChatId) {
                chatModel.appendMessage(chatMsg)
                console.log("[ChatPage] appendMessage done, new count=" + chatModel.count)
            }

            // 更新联系人列表的最后消息预览
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

                // 通过 WxBridge 推送消息事件给财务软件（端口 7888）
                var isSelf = (sendID === staffUserId)
                var wxType = 1 // text
                if (contentType === 102) wxType = 3       // image
                else if (contentType === 105) wxType = 49  // file
                var msgText = preview
                if (contentType === 101) msgText = parsed["text"] ?? parsed["content"] ?? contentStr
                WxBridge.pushMessageEvent(sendID, recvID, msgText, isSelf, wxType)
            }
        }

        // 发送消息应答：更新发送状态
        function onMessageAck(clientMsgId, status, serverMsgId, sendTime) {
            chatModel.updateStatus(clientMsgId, status)
        }

        // 历史消息加载完成
        function onHistoryLoaded(peerUserId, messages, hasMore) {
            console.log("[ChatPage] onHistoryLoaded peer:", peerUserId,
                        "active:", activeChatId, "msgCount:", messages.length, "hasMore:", hasMore)
            if (peerUserId !== activeChatId) return
            hasMoreHistory = hasMore

            // 将服务器消息转换为 chatModel 可用的 JSON 对象数组
            var parsed = []
            for (var i = 0; i < messages.length; i++) {
                var m = messages[i]
                var ct = m["contentType"] ?? 101
                var contentStr = m["content"] ?? ""
                var p = {}
                try { p = JSON.parse(contentStr) } catch(e) { p = {"content": contentStr} }

                var obj = {
                    "clientMsgID": m["clientMsgID"] ?? m["serverMsgID"] ?? "",
                    "sendID": m["sendID"] ?? "",
                    "recvID": m["recvID"] ?? "",
                    "contentType": ct,
                    "sendTime": m["sendTime"] ?? 0,
                    "status": 2,
                    "textElem": ct === 101 ? p : undefined,
                    "content": ct === 101 ? (p["text"] ?? p["content"] ?? contentStr) : undefined,
                    "pictureElem": ct === 102 ? (function() {
                        var sp = p["sourcePicture"] ?? {"url": p["url"] ?? ""}
                        var bp = p["bigPicture"] ?? {"url": p["url"] ?? ""}
                        sp["url"] = resolveUrl(sp["url"] ?? "")
                        bp["url"] = resolveUrl(bp["url"] ?? "")
                        return {"sourcePicture": sp, "bigPicture": bp}
                    })() : undefined,
                    "fileElem": ct === 105 ? {
                        "fileName": p["fileName"] ?? p["name"] ?? "",
                        "sourceUrl": resolveUrl(p["sourceUrl"] ?? p["url"] ?? ""),
                        "fileSize": p["fileSize"] ?? p["size"] ?? 0
                    } : undefined,
                    "voiceElem": ct === 103 ? {
                        "sourceUrl": resolveUrl(p["url"] ?? p["sourceUrl"] ?? ""),
                        "duration": p["duration"] ?? 0
                    } : undefined
                }
                parsed.push(obj)

                // 跟踪最小 seq 用于分页
                var seq = m["seq"] ?? 0
                if (seq > 0 && (oldestSeq === 0 || seq < oldestSeq))
                    oldestSeq = seq
            }

            if (loadingMore) {
                // 向上加载更多：批量插入到列表头部
                chatModel.prependMessages(parsed)
                loadingMore = false
            } else {
                // 初次加载：清空后批量插入
                chatModel.clear()
                chatModel.prependMessages(parsed)
            }
        }

        // WS 重连后：如果当前有打开的会话且消息为空，重新加载历史
        function onConnectedChanged() {
            if (WsClient.connected && activeChatId && chatModel.count === 0) {
                console.log("[ChatPage] WS reconnected, reloading history for", activeChatId)
                oldestSeq = 0
                hasMoreHistory = true
                loadingMore = false
                WsClient.loadHistory(activeChatId)
            }
        }

        // 服务器通知联系人列表变化，重新加载
        function onContactsUpdated() {
            HttpClient.getContacts()
        }
    }

    // ── WxBridge 桥接器信号处理 ─────────────────

    Connections {
        target: WxBridge

        // 财务软件指令：发送文本消息
        function onApiSendText(wxid, msg) {
            console.log("[桥接器] 发送文本到", wxid, ":", msg)
            var content = JSON.stringify({"text": msg})
            var msgId = chatModel.addPendingMessage(wxid, 101, msg)
            WsClient.sendMessage(wxid, 101, content, msgId)
            contactModel.updateLastMessage(wxid, msg, Date.now())
            // 推送自发消息事件回给财务软件
            WxBridge.pushMessageEvent(staffUserId, wxid, msg, true, 1)
        }

        // 财务软件指令：发送图片
        function onApiSendImage(wxid, path) {
            console.log("[桥接器] 发送图片到", wxid, ":", path)
            // 先上传图片文件，上传成功后通过 WS 发送
            chatRoot._pendingBridgeTarget = wxid
            chatRoot._pendingBridgeType = "image"
            HttpClient.uploadFile(path)
        }

        // 财务软件指令：发送文件
        function onApiSendFile(wxid, path) {
            console.log("[桥接器] 发送文件到", wxid, ":", path)
            chatRoot._pendingBridgeTarget = wxid
            chatRoot._pendingBridgeType = "file"
            HttpClient.uploadFile(path)
        }

        // 财务软件指令：获取好友列表
        function onApiGetFriendList() {
            console.log("[桥接器] 获取好友列表")
            WxBridge.pushFriendList(contactModel.toJsonArray())
        }

        function onBridgeError(error) {
            console.warn("[桥接器] 错误:", error)
        }
    }

    // 桥接器待处理上传状态（记录财务软件触发的上传目标）
    property string _pendingBridgeTarget: ""
    property string _pendingBridgeType: ""
}
