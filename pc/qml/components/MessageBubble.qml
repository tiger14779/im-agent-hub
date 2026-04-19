import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import ImAgentHub

// 消息气泡组件 —— 支持文本/图片/文件/语音多种消息类型的显示
Item {
    id: bubble
    height: bubbleRow.height + 8

    property bool isSelf: false        // 是否为自己发送的消息
    property int contentType: 101      // 消息类型: 101=文本, 102=图片, 103=语音, 105=文件
    property string textContent: ""    // 文本内容
    property string imageUrl: ""       // 图片/文件/语音URL
    // 稳定的图片URL：初次赋值后锁定，图片渲染完成后不再响应 URL 变更
    // 防止 onMediaDownloaded 把网络URL换成本地路径时导致图片重新加载闪烁
    property string _stableImageUrl: ""
    property bool _imageHasRendered: false   // 图片是否已成功渲染过一次
    onImageUrlChanged: {
        // 仅在图片尚未渲染时才更新稳定URL（已渲染则保留当前画面，避免闪烁）
        if (imageUrl.length > 0 && !_imageHasRendered)
            _stableImageUrl = imageUrl
    }
    property string fileName: ""       // 文件名
    property real fileSize: 0          // 文件大小（字节）
    property int voiceDuration: 0      // 语音时长（秒）
    property int msgStatus: 2          // 发送状态: 1=发送中, 2=已发送, 3=失败
    property real sendTime: 0          // 发送时间戳
    property string avatarUrl: ""      // 头像URL（对方或自己）
    property string serverMsgId: ""    // 服务器消息ID（用于删除）
    property string clientMsgId: ""    // 客户端消息ID
    property string senderName: ""     // 发送者昵称（群消息使用）
    property bool isGroup: false        // 是否为群消息

    signal imageLoaded()               // 图片加载完成信号（用于通知列表补偿滚动）
    signal deleteRequested(string serverMsgId, string clientMsgId)  // 请求删除消息
    signal imageViewRequested(string url)  // 请求查看大图

    RowLayout {
        id: bubbleRow
        anchors {
            top: parent.top
            topMargin: 4
            left: isSelf ? undefined : parent.left
            leftMargin: isSelf ? undefined : 12
            right: isSelf ? parent.right : undefined
            rightMargin: isSelf ? 12 : undefined
        }
        spacing: 8
        layoutDirection: isSelf ? Qt.RightToLeft : Qt.LeftToRight

        // 头像
        Rectangle {
            width: 36; height: 36; radius: 4
            color: isSelf ? "#07c160" : "#4a90d9"
            Layout.alignment: Qt.AlignTop
            clip: true

            Image {
                id: avatarImg
                anchors.fill: parent
                source: avatarUrl
                visible: status === Image.Ready
                fillMode: Image.PreserveAspectCrop
            }

            Label {
                anchors.centerIn: parent
                text: isSelf ? "\u6211" : (isGroup && senderName.length > 0 ? senderName.charAt(0).toUpperCase() : "\u4ED6")
                color: "white"
                font.pixelSize: 14
                visible: avatarImg.status !== Image.Ready
            }
        }

        // 气泡容器
        ColumnLayout {
            spacing: 2
            Layout.maximumWidth: bubble.width * 0.55

            // 群消息发送者名称
            Label {
                text: senderName
                font.pixelSize: 11
                color: "#888"
                bottomPadding: 2
                visible: isGroup && !isSelf && senderName.length > 0
            }

            Rectangle {
                id: msgBubble
                radius: 6
                color: isSelf ? "#95ec69" : "white"
                border.color: isSelf ? "#85d85a" : "#e8e8e8"
                border.width: isSelf ? 0 : 1

                implicitWidth: contentLoader.width + 20
                implicitHeight: contentLoader.height + 14
                Layout.maximumWidth: bubble.width * 0.55

                Loader {
                    id: contentLoader
                    x: 10; y: 7

                    sourceComponent: {
                        if (contentType === 102) return imageComponent
                        if (contentType === 105) return fileComponent
                        if (contentType === 103) return voiceComponent
                        return textComponent
                    }
                }

                Component {
                    id: textComponent
                    TextEdit {
                        text: textContent
                        wrapMode: Text.Wrap
                        width: Math.min(implicitWidth, bubble.width * 0.55 - 40)
                        color: "#333"
                        font.pixelSize: 14
                        readOnly: true
                        selectByMouse: true
                        selectedTextColor: "#fff"
                        selectionColor: "#07c160"
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: function(mouse) {
                                contextMenu.popup()
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    visible: contentType !== 101
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                            contextMenu.popup()
                        }
                    }
                }

                Menu {
                    id: contextMenu
                    MenuItem {
                        text: "\u590D\u5236"
                        visible: contentType === 101
                        height: visible ? implicitHeight : 0
                        onTriggered: {
                            if (textContent.length > 0)
                                HttpClient.copyToClipboard(textContent)
                        }
                    }
                    MenuItem {
                        text: "\u590D\u5236\u56FE\u7247"
                        visible: contentType === 102 && imageUrl.length > 0
                        height: visible ? implicitHeight : 0
                        onTriggered: {
                            HttpClient.copyFileToClipboard(imageUrl, "image." + imageUrl.split(".").pop())
                        }
                    }
                    MenuItem {
                        text: "\u53E6\u5B58\u4E3A..."
                        visible: contentType === 102 && imageUrl.length > 0
                        height: visible ? implicitHeight : 0
                        onTriggered: {
                            globalSaveDialog.downloadUrl = imageUrl
                            var ext = imageUrl.split(".").pop()
                            globalSaveDialog.currentFile = "file:///image." + ext
                            globalSaveDialog.open()
                        }
                    }
                    MenuItem {
                        text: "\u6253\u5F00"
                        visible: contentType === 105 && imageUrl.length > 0
                        height: visible ? implicitHeight : 0
                        onTriggered: {
                            HttpClient.downloadAndOpen(imageUrl, fileName || "download")
                        }
                    }
                    MenuItem {
                        text: "\u590D\u5236\u6587\u4EF6"
                        visible: contentType === 105 && imageUrl.length > 0
                        height: visible ? implicitHeight : 0
                        onTriggered: {
                            HttpClient.copyFileToClipboard(imageUrl, fileName || "download")
                        }
                    }
                    MenuItem {
                        text: "\u53E6\u5B58\u4E3A..."
                        visible: contentType === 105 && imageUrl.length > 0
                        height: visible ? implicitHeight : 0
                        onTriggered: {
                            globalSaveDialog.downloadUrl = imageUrl
                            globalSaveDialog.currentFile = fileName ? ("file:///" + fileName) : ""
                            globalSaveDialog.open()
                        }
                    }
                    MenuSeparator { visible: (isSelf || isGroup) && serverMsgId.length > 0 }
                    MenuItem {
                        text: "\u5220\u9664"
                        visible: (isSelf || isGroup) && serverMsgId.length > 0
                        height: visible ? implicitHeight : 0
                        onTriggered: {
                            bubble.deleteRequested(serverMsgId, clientMsgId)
                        }
                    }
                }

                FileDialog {
                    id: globalSaveDialog
                    title: contentType === 102 ? "\u4FDD\u5B58\u56FE\u7247" : "\u4FDD\u5B58\u6587\u4EF6"
                    fileMode: FileDialog.SaveFile
                    property string downloadUrl: ""
                    onAccepted: {
                        var savePath = selectedFile.toString()
                        if (savePath.startsWith("file:///"))
                            savePath = savePath.substring(8)
                        HttpClient.downloadToPath(downloadUrl, savePath)
                    }
                }

                Component {
                    id: imageComponent
                    Image {
                        source: bubble._stableImageUrl
                        fillMode: Image.PreserveAspectFit
                        width: Math.min(Math.max(sourceSize.width, 60), 220)
                        height: sourceSize.width > 0
                                ? width / (sourceSize.width / sourceSize.height)
                                : 120

                        onStatusChanged: {
                            if (status === Image.Ready) {
                                bubble._imageHasRendered = true  // 锁定：后续 URL 变更不再触发重加载
                                bubble.imageLoaded()
                            }
                        }

                        // 双击放大查看 / 拖拽保存到电脑
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            property point pressPos: Qt.point(0, 0)
                            property bool dragging: false

                            onPressed: function(mouse) {
                                pressPos = Qt.point(mouse.x, mouse.y)
                                dragging = false
                            }
                            onPositionChanged: function(mouse) {
                                if (!dragging && (mouse.buttons & Qt.LeftButton)) {
                                    var dx = mouse.x - pressPos.x
                                    var dy = mouse.y - pressPos.y
                                    if (Math.sqrt(dx*dx + dy*dy) > 10) {
                                        dragging = true
                                        if (imageUrl.length > 0) {
                                            var ext = imageUrl.split(".").pop()
                                            HttpClient.startFileDrag(imageUrl, "image." + ext)
                                        }
                                    }
                                }
                            }
                            onDoubleClicked: {
                                if (imageUrl.length > 0)
                                    bubble.imageViewRequested(imageUrl)
                            }
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton)
                                    contextMenu.popup()
                            }
                        }

                        // 加载中指示器
                        BusyIndicator {
                            anchors.centerIn: parent
                            running: parent.status === Image.Loading
                            visible: running
                            width: 24; height: 24
                        }

                        // 加载失败占位图
                        Rectangle {
                            anchors.fill: parent
                            color: "#f0f0f0"
                            visible: parent.status === Image.Error
                            Label {
                                anchors.centerIn: parent
                                text: "\u56FE\u7247\u52A0\u8F7D\u5931\u8D25"
                                color: "#999"; font.pixelSize: 11
                            }
                        }
                    }
                }

                Component {
                    id: fileComponent
                    Item {
                        width: fileRow.width
                        height: fileRow.height

                        RowLayout {
                            id: fileRow
                            spacing: 8
                            width: Math.min(implicitWidth, bubble.width * 0.55 - 40)

                            Rectangle {
                                width: 40; height: 40; radius: 4
                                color: {
                                    var ext = (fileName || "").toLowerCase()
                                    if (ext.endsWith(".doc") || ext.endsWith(".docx"))
                                        return fileMouseArea.containsMouse ? "#1a5bb5" : "#2b6cb0"
                                    if (ext.endsWith(".xls") || ext.endsWith(".xlsx"))
                                        return fileMouseArea.containsMouse ? "#1a7a3a" : "#217346"
                                    if (ext.endsWith(".ppt") || ext.endsWith(".pptx"))
                                        return fileMouseArea.containsMouse ? "#c43e1c" : "#d04423"
                                    if (ext.endsWith(".pdf"))
                                        return fileMouseArea.containsMouse ? "#c12b2b" : "#e2574c"
                                    return fileMouseArea.containsMouse ? "#e0e0e0" : "#f0f0f0"
                                }
                                Label {
                                    anchors.centerIn: parent
                                    text: {
                                        var ext = (fileName || "").toLowerCase()
                                        if (ext.endsWith(".doc") || ext.endsWith(".docx")) return "W"
                                        if (ext.endsWith(".xls") || ext.endsWith(".xlsx")) return "X"
                                        if (ext.endsWith(".ppt") || ext.endsWith(".pptx")) return "P"
                                        if (ext.endsWith(".pdf")) return "PDF"
                                        return "\uD83D\uDCC4"
                                    }
                                    color: {
                                        var ext = (fileName || "").toLowerCase()
                                        if (ext.endsWith(".doc") || ext.endsWith(".docx") ||
                                            ext.endsWith(".xls") || ext.endsWith(".xlsx") ||
                                            ext.endsWith(".ppt") || ext.endsWith(".pptx") ||
                                            ext.endsWith(".pdf"))
                                            return "white"
                                        return "#333"
                                    }
                                    font.pixelSize: 18
                                    font.bold: true
                                }
                            }

                            ColumnLayout {
                                spacing: 2
                                Layout.fillWidth: true
                                Label {
                                    text: fileName || "\u672A\u77E5\u6587\u4EF6"
                                    color: "#333"
                                    font.pixelSize: 13
                                    elide: Text.ElideMiddle
                                    Layout.maximumWidth: 160
                                }
                                Label {
                                    text: formatSize(fileSize)
                                    color: "#999"
                                    font.pixelSize: 11
                                }
                            }
                        }

                        MouseArea {
                            id: fileMouseArea
                            anchors.fill: fileRow
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            property point pressPos: Qt.point(0, 0)
                            property bool dragging: false

                            onPressed: function(mouse) {
                                pressPos = Qt.point(mouse.x, mouse.y)
                                dragging = false
                            }
                            onPositionChanged: function(mouse) {
                                if (!dragging && (mouse.buttons & Qt.LeftButton)) {
                                    var dx = mouse.x - pressPos.x
                                    var dy = mouse.y - pressPos.y
                                    if (Math.sqrt(dx*dx + dy*dy) > 10) {
                                        dragging = true
                                        if (imageUrl && imageUrl.length > 0) {
                                            HttpClient.startFileDrag(imageUrl, fileName || "download")
                                        }
                                    }
                                }
                            }
                            onDoubleClicked: {
                                if (imageUrl && imageUrl.length > 0) {
                                    HttpClient.downloadAndOpen(imageUrl, fileName || "download")
                                }
                            }
                        }
                    }
                }

                Component {
                    id: voiceComponent
                    Item {
                        width: voiceRow.width
                        height: voiceRow.height

                        MediaPlayer {
                            id: voicePlayer
                            source: imageUrl
                            audioOutput: AudioOutput {}
                            onPlaybackStateChanged: {
                                if (playbackState === MediaPlayer.StoppedState) {
                                    playTimer.stop()
                                }
                            }
                        }

                        // 播放时动态音频条动画
                        Timer {
                            id: playTimer
                            interval: 300
                            repeat: true
                            running: voicePlayer.playbackState === MediaPlayer.PlayingState
                            onTriggered: {
                                for (var i = 0; i < barsRepeater.count; i++) {
                                    barsRepeater.itemAt(i).height = 4 + Math.random() * 12
                                }
                            }
                        }

                        RowLayout {
                            id: voiceRow
                            spacing: 6
                            width: Math.max(80, Math.min(voiceDuration * 8 + 60, bubble.width * 0.4))

                            Label {
                                text: voicePlayer.playbackState === MediaPlayer.PlayingState ? "\u23F8" : "\u25B6"
                                font.pixelSize: 18
                                color: isSelf ? "#2e7d32" : "#1976d2"
                            }

                            Row {
                                spacing: 2
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                Repeater {
                                    id: barsRepeater
                                    model: 4
                                    Rectangle {
                                        width: 3
                                        height: 6 + index * 2
                                        radius: 1.5
                                        color: isSelf ? "#2e7d32" : "#1976d2"
                                        opacity: 0.5 + index * 0.15
                                        Behavior on height { NumberAnimation { duration: 150 } }
                                    }
                                }
                            }

                            Label {
                                text: voiceDuration > 0 ? voiceDuration + "''" : ""
                                color: "#666"
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            anchors.fill: voiceRow
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (voicePlayer.playbackState === MediaPlayer.PlayingState) {
                                    voicePlayer.pause()
                                } else {
                                    voicePlayer.play()
                                }
                            }
                        }
                    }
                }
            }

            // 时间 + 发送状态
            RowLayout {
                spacing: 4
                layoutDirection: isSelf ? Qt.RightToLeft : Qt.LeftToRight

                Label {
                    text: sendTime > 0 ? formatMsgTime(sendTime) : ""
                    color: "#bbb"
                    font.pixelSize: 10
                    visible: text.length > 0
                }

                Label {
                    text: msgStatus === 1 ? "\u23F3" : (msgStatus === 3 ? "\u274C" : "")
                    font.pixelSize: 10
                    visible: text.length > 0
                    color: msgStatus === 3 ? "#e74c3c" : "#bbb"
                }
            }
        }
    }

    // 格式化文件大小（B/KB/MB）
    function formatSize(bytes) {
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
        return (bytes / 1024 / 1024).toFixed(1) + " MB"
    }

    // 格式化消息时间：完整日期+时间，格式 M/D HH:mm
    function formatMsgTime(ts) {
        var d = new Date(ts)
        var dateStr = (d.getMonth() + 1) + "/" + d.getDate()
        var timeStr = d.getHours().toString().padStart(2, '0') + ":" +
                      d.getMinutes().toString().padStart(2, '0')
        return dateStr + " " + timeStr
    }
}
