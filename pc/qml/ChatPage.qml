import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import ImAgentHub

// 聊天主页 —— 包含左侧导航栏、中间联系人列表、右侧聊天区域
Page {
    id: chatRoot
    property string staffUserId: ""     // 当前客服用户ID
    property string staffNickname: ""   // 当前客服昵称
    property string staffAvatarUrl: ""  // 当前客服头像URL
    property string authToken: ""       // 认证令牌
    property string serverUrl: ""       // 服务器地址
    property string activeChatId: ""    // 当前打开的会话用户ID
    property string activeChatName: ""  // 当前会话用户昵称
    property string activeChatOnlineStatus: "" // 当前会话用户在线状态

    // 分页状态
    property int oldestSeq: 0            // 当前最旧消息的 seq（用于向上加载更多）
    property bool hasMoreHistory: true  // 是否还有更多历史消息
    property bool loadingMore: false    // 是否正在加载更多
    property bool _mergeMode: false     // 历史消息合并模式（重连/定时同步时使用）

    // 当前 Tab页: 0=聊天列表, 1=通讯录
    property int currentTab: 0

    // 消息提示音开关（持久化到 QSettings）
    property bool notifySoundEnabled: true

    // 消息提示音播放器
    MediaPlayer {
        id: notifyPlayer
        source: "qrc:/ImAgentHub/resources/notify.wav"
        audioOutput: AudioOutput { volume: 0.6 }
    }

    // 定时同步：每30秒检查当前会话是否有遗漏的消息
    Timer {
        id: syncTimer
        interval: 30000
        running: WsClient.connected && activeChatId.length > 0
        repeat: true
        onTriggered: {
            if (!loadingMore && !_mergeMode) {
                console.log("[ChatPage] periodic sync for", activeChatId)
                _mergeMode = true
                WsClient.loadHistory(activeChatId, 0, 20)
            }
        }
    }

    background: Rectangle { color: "#ebebeb" }

    ChatModel { id: chatModel }
    ContactModel { id: contactModel }

    // 将相对URL（/api/files/...）拼接为绝对URL
    function resolveUrl(url) {
        if (url && url.length > 0 && url.charAt(0) === '/')
            return HttpClient.baseUrl + url
        return url ?? ""
    }

    // 页面初始化
    Component.onCompleted: {
        // 从 QSettings 读取提示音开关状态
        var saved = HttpClient.getSetting("notify/soundEnabled", "true")
        notifySoundEnabled = (saved === "true")

        chatModel.setSelfId(staffUserId)
        MessageCache.init(staffUserId)
        HttpClient.getContacts()
        HttpClient.getProfile()
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

                // 客服头像（点击可编辑个人资料）
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 36; height: 36; radius: 6
                    color: "#07c160"
                    clip: true

                    Image {
                        id: staffAvatarImg
                        anchors.fill: parent
                        source: staffAvatarUrl.length > 0
                                ? (staffAvatarUrl.charAt(0) === '/' ? HttpClient.baseUrl + staffAvatarUrl : staffAvatarUrl)
                                : ""
                        visible: status === Image.Ready
                        fillMode: Image.PreserveAspectCrop
                    }

                    Label {
                        anchors.centerIn: parent
                        text: (staffNickname || "S").charAt(0).toUpperCase()
                        color: "white"; font.pixelSize: 16; font.bold: true
                        visible: staffAvatarImg.status !== Image.Ready
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: profileEditDialog.open()
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

                // 消息提示音开关按钮
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 12
                    width: 40; height: 40; radius: 6
                    color: soundBtnHovered ? "#444" : "transparent"
                    property bool soundBtnHovered: false

                    // 自绘扬声器图标
                    Canvas {
                        anchors.centerIn: parent
                        width: 22; height: 22
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = notifySoundEnabled ? "#07c160" : "#888"
                            ctx.fillStyle = notifySoundEnabled ? "#07c160" : "#888"
                            ctx.lineWidth = 1.5
                            ctx.lineCap = "round"

                            // 喇叭主体
                            ctx.beginPath()
                            ctx.moveTo(3, 8)
                            ctx.lineTo(7, 8)
                            ctx.lineTo(12, 4)
                            ctx.lineTo(12, 18)
                            ctx.lineTo(7, 14)
                            ctx.lineTo(3, 14)
                            ctx.closePath()
                            ctx.fill()

                            if (notifySoundEnabled) {
                                // 声波弧线
                                ctx.beginPath()
                                ctx.arc(12, 11, 4, -0.7, 0.7)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.arc(12, 11, 7.5, -0.6, 0.6)
                                ctx.stroke()
                            } else {
                                // 静音斜线
                                ctx.strokeStyle = "#ff4d4f"
                                ctx.lineWidth = 2
                                ctx.beginPath()
                                ctx.moveTo(15, 5)
                                ctx.lineTo(5, 17)
                                ctx.stroke()
                            }
                        }
                        // 状态变化时重绘
                        Connections {
                            target: chatRoot
                            function onNotifySoundEnabledChanged() { parent.requestPaint() }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: parent.soundBtnHovered = true
                        onExited: parent.soundBtnHovered = false
                        onClicked: {
                            notifySoundEnabled = !notifySoundEnabled
                            HttpClient.setSetting("notify/soundEnabled", notifySoundEnabled ? "true" : "false")
                        }
                    }
                    ToolTip.visible: soundBtnHovered
                    ToolTip.text: notifySoundEnabled ? "提示音: 开" : "提示音: 关"
                }
            }
        }

        // ── 中间面板（联系人列表 / 会话列表）─────
        Rectangle {
            id: contactPanel
            property real panelWidth: 260
            readonly property real minPanelWidth: 160
            readonly property real maxPanelWidth: 400
            Layout.preferredWidth: panelWidth
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

        // 侧边栏右侧拖拽手柄 —— 拖动可调整联系人面板宽度
        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: "#d6d6d6"

            MouseArea {
                anchors.fill: parent
                anchors.leftMargin: -3
                anchors.rightMargin: -3
                hoverEnabled: true
                cursorShape: Qt.SizeHorCursor
                property real startX: 0
                property real startWidth: 0

                onPressed: function(mouse) {
                    startX = mapToGlobal(mouse.x, mouse.y).x
                    startWidth = contactPanel.panelWidth
                }
                onPositionChanged: function(mouse) {
                    if (!pressed) return
                    var currentX = mapToGlobal(mouse.x, mouse.y).x
                    var delta = currentX - startX
                    var newW = Math.max(contactPanel.minPanelWidth,
                                        Math.min(contactPanel.maxPanelWidth, startWidth + delta))
                    contactPanel.panelWidth = newW
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

                // 聊天头部（显示当前会话名称 + 在线状态）
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    color: "#f5f5f5"

                    RowLayout {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        spacing: 8

                        Label {
                            text: activeChatName || activeChatId
                            font.pixelSize: 15; font.bold: true; color: "#333"
                        }

                        // 在线状态指示器
                        Rectangle {
                            width: statusRow.implicitWidth + 12
                            height: 20
                            radius: 10
                            visible: activeChatOnlineStatus.length > 0
                            color: activeChatOnlineStatus === "online" ? "#e8f5e9"
                                 : activeChatOnlineStatus === "background" ? "#fff3e0" : "#f5f5f5"

                            Row {
                                id: statusRow
                                anchors.centerIn: parent
                                spacing: 4

                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: activeChatOnlineStatus === "online" ? "#4caf50"
                                         : activeChatOnlineStatus === "background" ? "#ff9800" : "#bdbdbd"
                                }

                                Label {
                                    text: activeChatOnlineStatus === "online" ? "在线"
                                        : activeChatOnlineStatus === "background" ? "后台" : "离线"
                                    font.pixelSize: 11
                                    color: activeChatOnlineStatus === "online" ? "#2e7d32"
                                         : activeChatOnlineStatus === "background" ? "#e65100" : "#757575"
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width; height: 1; color: "#ddd"
                    }
                }

                // 消息列表
                MessageList {
                    id: messageListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: chatModel
                    selfId: staffUserId
                    peerAvatarUrl: contactModel.getAvatar(activeChatId)
                    selfAvatarUrl: chatRoot.staffAvatarUrl
                    serverUrl: HttpClient.baseUrl
                    loadingMore: chatRoot.loadingMore
                    hasMore: chatRoot.hasMoreHistory
                    suppressAutoScroll: chatRoot._mergeMode
                    onRequestLoadMore: chatRoot.loadMoreHistory()
                    onDeleteRequested: function(serverMsgId, clientMsgId) {
                        WsClient.deleteMessage(serverMsgId)
                        chatModel.removeMessageByServerMsgID(serverMsgId)
                        MessageCache.removeMessage(serverMsgId)
                    }
                    onImageViewRequested: function(url) {
                        imageViewer.imageSource = url
                        imageViewer.open()
                    }
                }

                // 聊天输入栏（工具条 + 文本输入区）
                ChatInput {
                    Layout.fillWidth: true
                    Layout.preferredHeight: inputHeight
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
    property string pendingProfileAvatarUrl: ""  // 个人资料对话框的待上传头像URL

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
            } else if (avatarFileDialog.target === "profile") {
                pendingProfileAvatarUrl = url
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

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    cursorShape: Qt.IBeamCursor
                    onClicked: function(mouse) {
                        newNicknameMenu.popup()
                    }
                }

                Menu {
                    id: newNicknameMenu
                    MenuItem {
                        text: "\u7C98\u8D34"
                        onTriggered: newNickname.paste()
                    }
                }
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

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    cursorShape: Qt.IBeamCursor
                    onClicked: function(mouse) {
                        editRemarkMenu.popup()
                    }
                }

                Menu {
                    id: editRemarkMenu
                    MenuItem {
                        text: "\u7C98\u8D34"
                        onTriggered: editRemarkField.paste()
                    }
                }
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

    // ── 个人资料编辑对话框 ────────────────────
    Dialog {
        id: profileEditDialog
        title: "编辑个人资料"
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
                        source: {
                            var url = pendingProfileAvatarUrl.length > 0
                                      ? pendingProfileAvatarUrl
                                      : staffAvatarUrl
                            return url.length > 0 ? (url.charAt(0) === '/' ? HttpClient.baseUrl + url : url) : ""
                        }
                        visible: status === Image.Ready
                        fillMode: Image.PreserveAspectCrop
                    }
                    Label {
                        anchors.centerIn: parent
                        text: (profileNicknameField.text || staffNickname || "S").charAt(0).toUpperCase()
                        color: "white"; font.pixelSize: 20; font.bold: true
                        visible: pendingProfileAvatarUrl.length === 0 && staffAvatarUrl.length === 0
                    }
                }
                Button {
                    text: "上传头像"
                    onClicked: {
                        avatarFileDialog.target = "profile"
                        avatarFileDialog.open()
                    }
                }
            }

            TextField {
                id: profileNicknameField
                placeholderText: "客服昵称"
                text: staffNickname
                Layout.fillWidth: true

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    cursorShape: Qt.IBeamCursor
                    onClicked: function(mouse) {
                        profileNicknameMenu.popup()
                    }
                }

                Menu {
                    id: profileNicknameMenu
                    MenuItem {
                        text: "\u7C98\u8D34"
                        onTriggered: profileNicknameField.paste()
                    }
                }
            }
        }

        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            var avatar = pendingProfileAvatarUrl.length > 0 ? pendingProfileAvatarUrl : staffAvatarUrl
            HttpClient.updateProfile(profileNicknameField.text.trim(), avatar)
            pendingProfileAvatarUrl = ""
        }
        onRejected: {
            pendingProfileAvatarUrl = ""
            profileNicknameField.text = staffNickname
        }
    }

    // ── Functions ────────────────────────────────────────

    function openChat(userId) {
        console.log("[ChatPage] openChat:", userId, "wsConnected:", WsClient.connected)
        activeChatId = userId
        activeChatName = contactModel.getNickname(userId)
        activeChatOnlineStatus = contactModel.getOnlineStatus(userId)
        chatModel.clear()
        contactModel.clearUnread(userId)
        oldestSeq = 0
        hasMoreHistory = true
        loadingMore = false

        // 1) 先从本地 SQLite 缓存加载消息，立即显示（闪现，提升感知速度）
        var cached = MessageCache.loadMessages(userId, 50)
        if (cached.length > 0) {
            console.log("[ChatPage] 从本地缓存加载", cached.length, "条消息")
            chatModel.prependMessages(cached)
        }

        // 2) 从服务器拉取完整数据，到达后替换缓存数据（保证顺序正确）
        _mergeMode = false
        WsClient.loadHistory(userId)
    }

    function sendTextMessage(text) {
        var content = JSON.stringify({"text": text})
        var msgId = chatModel.addPendingMessage(activeChatId, 101, text)
        WsClient.sendMessage(activeChatId, 101, content, msgId)
        contactModel.updateLastMessage(activeChatId, text, Date.now())
        // 保存发送的消息到本地缓存
        MessageCache.saveMessage({
            "clientMsgID": msgId, "sendID": staffUserId, "recvID": activeChatId,
            "contentType": 101, "sendTime": Date.now(), "status": 1,
            "textElem": {"text": text}, "content": text
        })
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
        // 个人资料更新成功
        function onProfileUpdated(data) {
            staffNickname = data["nickname"] ?? staffNickname
            staffAvatarUrl = data["avatar"] ?? staffAvatarUrl
        }
        // 文件上传成功回调 —— 根据上下文判断是普通发送还是桥接器发送
        function onUploadSuccess(url, origName, origSize) {
            console.log("[上传] 成功 url=" + url + " origName=" + origName + " origSize=" + origSize)
            // 检查是否有桥接器待处理的上传（FIFO 队列）
            if (chatRoot._pendingBridgeQueue.length > 0) {
                var q = chatRoot._pendingBridgeQueue
                var entry = q.shift()
                chatRoot._pendingBridgeQueue = q

                var bridgeTarget = entry.target
                var bridgeType = entry.type
                console.log("[上传] 桥接器出队: target=" + bridgeTarget + " type=" + bridgeType
                            + " 剩余队列=" + q.length)

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
                    // 只有目标是当前聊天对象时才插入消息列表，否则仅发送
                    var bImgMsgId = ""
                    if (bridgeTarget === activeChatId) {
                        bImgMsgId = chatModel.addPendingMessage(bridgeTarget, 102, "", resolveUrl(url))
                    } else {
                        bImgMsgId = chatModel.generateMsgId()
                    }
                    WsClient.sendMessage(bridgeTarget, 102, bImgContent, bImgMsgId)
                    contactModel.updateLastMessage(bridgeTarget, "[\u56FE\u7247]", Date.now())
                    WxBridge.pushMessageEvent(staffUserId, bridgeTarget, "[\u56FE\u7247]", true, 3)
                } else {
                    console.log("[上传] 桥接器 → 文件发送 (contentType=105)")
                    var bFileContent = JSON.stringify({
                        "url": url, "name": origName, "size": origSize
                    })
                    // 只有目标是当前聊天对象时才插入消息列表，否则仅发送
                    var bFileMsgId = ""
                    if (bridgeTarget === activeChatId) {
                        bFileMsgId = chatModel.addPendingMessage(bridgeTarget, 105, "", resolveUrl(url), origName, origSize)
                    } else {
                        bFileMsgId = chatModel.generateMsgId()
                    }
                    WsClient.sendMessage(bridgeTarget, 105, bFileContent, bFileMsgId)
                    contactModel.updateLastMessage(bridgeTarget, "[\u6587\u4EF6]", Date.now())
                    WxBridge.pushMessageEvent(staffUserId, bridgeTarget, "[\u6587\u4EF6]", true, 49)
                }
                // 串行队列：处理完当前条目后，启动下一个上传
                if (chatRoot._pendingBridgeQueue.length > 0) {
                    var nextPath = chatRoot._pendingBridgeQueue[0].path
                    console.log("[上传] 启动下一个桥接器上传: " + nextPath)
                    HttpClient.uploadFile(nextPath)
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
                MessageCache.saveMessage({
                    "clientMsgID": imgMsgId, "sendID": staffUserId, "recvID": activeChatId,
                    "contentType": 102, "sendTime": Date.now(), "status": 1,
                    "pictureElem": {"sourcePicture": {"url": resolveUrl(url)}, "bigPicture": {"url": resolveUrl(url)}}
                })
            } else {
                // 文件消息 —— 使用 H5 兼容格式 {url, name, size}
                var fileContent = JSON.stringify({
                    "url": url, "name": origName, "size": origSize
                })
                var fileMsgId = chatModel.addPendingMessage(activeChatId, 105, "", resolveUrl(url), origName, origSize)
                WsClient.sendMessage(activeChatId, 105, fileContent, fileMsgId)
                contactModel.updateLastMessage(activeChatId, "[\u6587\u4EF6]", Date.now())
                MessageCache.saveMessage({
                    "clientMsgID": fileMsgId, "sendID": staffUserId, "recvID": activeChatId,
                    "contentType": 105, "sendTime": Date.now(), "status": 1,
                    "fileElem": {"fileName": origName, "sourceUrl": resolveUrl(url), "fileSize": origSize}
                })
            }
        }

        // 文件上传失败 —— 跳过当前桥接器条目，继续处理队列
        function onUploadFailed(error) {
            console.warn("[上传] 失败:", error)
            if (chatRoot._pendingBridgeQueue.length > 0) {
                var q = chatRoot._pendingBridgeQueue
                var skipped = q.shift()
                chatRoot._pendingBridgeQueue = q
                console.warn("[上传] 跳过桥接器条目: target=" + skipped.target + " path=" + skipped.path)
                // 继续处理队列中的下一个
                if (q.length > 0) {
                    HttpClient.uploadFile(q[0].path)
                }
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
                "serverMsgID": msg["serverMsgID"] ?? "",
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
            var msgId = chatMsg["clientMsgID"]
            // 去重检查：如果当前会话已经有该消息，跳过所有副作用（声音、未读、推送）
            var isDuplicate = (peerID === activeChatId && msgId.length > 0 && chatModel.hasMessage(msgId))
            console.log("[ChatPage] onNewMessage peerID=" + peerID + " activeChatId=" + activeChatId
                        + " match=" + (peerID === activeChatId) + " dup=" + isDuplicate
                        + " modelCount=" + chatModel.count)
            if (isDuplicate) return

            if (peerID === activeChatId) {
                chatModel.appendMessage(chatMsg)
                console.log("[ChatPage] appendMessage done, new count=" + chatModel.count)
            }

            // 保存到本地缓存
            MessageCache.saveMessage(chatMsg)

            // 播放消息提示音（仅收到别人的消息时）
            if (sendID !== staffUserId && chatRoot.notifySoundEnabled) {
                notifyPlayer.stop()
                notifyPlayer.play()
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
            chatModel.updateStatus(clientMsgId, status, serverMsgId)
            // 仅更新缓存中的状态字段，保留完整的消息内容
            MessageCache.updateMessageStatus(clientMsgId, status, serverMsgId, sendTime)
        }

        // 历史消息加载完成
        function onHistoryLoaded(peerUserId, messages, hasMore) {
            console.log("[ChatPage] onHistoryLoaded peer:", peerUserId,
                        "active:", activeChatId, "msgCount:", messages.length,
                        "hasMore:", hasMore, "merge:", _mergeMode)
            if (peerUserId !== activeChatId) {
                _mergeMode = false
                return
            }

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
                    "serverMsgID": m["serverMsgID"] ?? "",
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

            // 将服务器返回的消息批量保存到本地缓存
            MessageCache.saveMessages(parsed)

            if (_mergeMode) {
                // 合并模式（重连/定时同步）：仅追加新消息，appendMessage 内置去重
                // _mergeMode 保持 true 直到操作完成，suppressAutoScroll 绑定此值
                var mergedCount = 0
                var beforeCount = chatModel.count
                for (var j = 0; j < parsed.length; j++) {
                    chatModel.appendMessage(parsed[j])
                }
                mergedCount = chatModel.count - beforeCount
                _mergeMode = false  // 所有追加完成后才重置
                if (mergedCount > 0) {
                    console.log("[ChatPage] sync merged", mergedCount, "new messages")
                }
                return
            }

            hasMoreHistory = hasMore
            if (loadingMore) {
                // 向上加载更多：批量插入到列表头部
                chatModel.prependMessages(parsed)
                loadingMore = false
            } else {
                // 初次加载：智能替换（相同结构只更新数据不动布局，不同结构才清空重建）
                chatModel.replaceAll(parsed)
            }
        }

        // WS 重连后：同步当前会话的最新消息（合并模式，不清空已有消息）
        function onConnectedChanged() {
            if (WsClient.connected) {
                // 查询所有H5客户端的在线状态
                WsClient.queryOnline()
                if (activeChatId) {
                    console.log("[ChatPage] WS reconnected, syncing history for", activeChatId)
                    _mergeMode = true
                    WsClient.loadHistory(activeChatId, 0, 50)
                }
            }
        }

        // 服务器通知联系人列表变化，重新加载
        function onContactsUpdated() {
            HttpClient.getContacts()
        }

        // 消息被删除（自己或对方删除）
        function onMessageDeleted(serverMsgId) {
            chatModel.removeMessageByServerMsgID(serverMsgId)
            MessageCache.removeMessage(serverMsgId)
        }

        // H5客户端在线状态变化
        function onClientOnlineStatus(userId, status) {
            console.log("[ChatPage] clientOnlineStatus:", userId, status)
            contactModel.setOnlineStatus(userId, status)
            if (userId === activeChatId) {
                activeChatOnlineStatus = status
            }
        }

        // 在线客户端列表响应
        function onOnlineListReceived(clients) {
            console.log("[ChatPage] onlineList received:", clients.length, "clients")
            for (var i = 0; i < clients.length; i++) {
                var c = clients[i]
                contactModel.setOnlineStatus(c["userId"], c["status"])
            }
            // 更新当前聊天对象的在线状态
            if (activeChatId.length > 0) {
                activeChatOnlineStatus = contactModel.getOnlineStatus(activeChatId)
            }
        }
    }

    // ── WxBridge 桥接器信号处理 ─────────────────

    Connections {
        target: WxBridge

        // 财务软件指令：发送文本消息
        function onApiSendText(wxid, msg) {
            console.log("[桥接器] 发送文本到", wxid, ":", msg)
            var content = JSON.stringify({"text": msg})
            // 只有目标是当前聊天对象时才插入消息列表，否则仅发送
            var msgId = ""
            if (wxid === activeChatId) {
                msgId = chatModel.addPendingMessage(wxid, 101, msg)
            } else {
                msgId = chatModel.generateMsgId()
            }
            WsClient.sendMessage(wxid, 101, content, msgId)
            contactModel.updateLastMessage(wxid, msg, Date.now())
            // 推送自发消息事件回给财务软件
            WxBridge.pushMessageEvent(staffUserId, wxid, msg, true, 1)
        }

        // 财务软件指令：发送图片
        function onApiSendImage(wxid, path) {
            console.log("[桥接器] 发送图片到", wxid, ":", path)
            // 入队后上传，串行处理：队列中只有一个时立即上传，否则等待前面完成
            var q = chatRoot._pendingBridgeQueue
            q.push({target: wxid, type: "image", path: path})
            chatRoot._pendingBridgeQueue = q
            if (q.length === 1) {
                HttpClient.uploadFile(path)
            }
        }

        // 财务软件指令：发送文件
        function onApiSendFile(wxid, path) {
            console.log("[桥接器] 发送文件到", wxid, ":", path)
            var q = chatRoot._pendingBridgeQueue
            q.push({target: wxid, type: "file", path: path})
            chatRoot._pendingBridgeQueue = q
            if (q.length === 1) {
                HttpClient.uploadFile(path)
            }
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

    // 桥接器待处理上传队列（FIFO，每个上传对应一个条目）
    property var _pendingBridgeQueue: []

    // 图片查看器
    ImageViewer {
        id: imageViewer
        parent: Overlay.overlay
    }
}
