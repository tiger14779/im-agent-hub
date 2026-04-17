import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import ImAgentHub

// 聊天输入栏组件 —— 包含工具栏（表情/图片/文件）、预览区和文本输入区
Rectangle {
    id: chatInput
    property real inputHeight: 140     // 当前输入区高度（可拖拽调整）
    readonly property real minInputHeight: 80
    readonly property real maxInputHeight: 400
    implicitHeight: inputHeight
    color: "#f5f5f5"

    signal sendText(string text)       // 发送文本消息
    signal sendFile(string filePath)   // 发送文件
    signal sendImage(string filePath)  // 发送图片
    signal sendAudio(string filePath, int duration)  // 发送语音

    // 录音状态
    property int _recSeconds: 0
    property bool _recActive: false

    // 待发送的附件列表: [{path, type, name}]  type: "image" | "file"

    // 录音组件
    CaptureSession {
        id: captureSession
        audioInput: AudioInput {}
        recorder: MediaRecorder {
            id: audioRecorder
            mediaFormat {
                fileType: MediaFormat.Wave
            }
            onRecorderStateChanged: {
                if (recorderState === MediaRecorder.StoppedState && chatInput._recActive) {
                    chatInput._recActive = false
                    var dur = chatInput._recSeconds
                    chatInput._recSeconds = 0
                    var path = audioRecorder.actualLocation.toString()
                    if (path.startsWith("file:///"))
                        path = path.substring(8)
                    // Windows: file:///C:/... → C:/...
                    path = path.replace(/\//g, "\\")
                    if (dur > 0 && path.length > 4)
                        chatInput.sendAudio(path, dur)
                }
            }
        }
    }

    Timer {
        id: recTimer
        interval: 1000
        repeat: true
        onTriggered: chatInput._recSeconds++
    }

    // ── 拖入文件/图片到聊天框 ──
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: function(drop) {
            if (drop.hasUrls) {
                for (var i = 0; i < drop.urls.length; i++) {
                    var path = drop.urls[i].toString()
                    if (path.startsWith("file:///"))
                        path = path.substring(8)
                    addPendingFile(path, isImageFile(path) ? "image" : "file")
                }
                drop.accept()
            }
        }

        // 拖入时的视觉反馈矩形
        Rectangle {
            anchors.fill: parent
            color: "#07c16020"
            border.color: "#07c160"
            border.width: 2
            radius: 6
            visible: parent.containsDrag
            z: 100

            Label {
                anchors.centerIn: parent
                text: "松开以添加文件"
                color: "#07c160"
                font.pixelSize: 16
                font.bold: true
            }
        }
    }
    property var pendingFiles: []

    function addPendingFile(path, type) {
        var name = path.replace(/\\/g, "/").split("/").pop()
        var list = pendingFiles.slice()
        // 去重
        for (var i = 0; i < list.length; i++) {
            if (list[i].path === path) return
        }
        list.push({path: path, type: type, name: name})
        pendingFiles = list
    }

    function removePendingFile(index) {
        var list = pendingFiles.slice()
        list.splice(index, 1)
        pendingFiles = list
    }

    function clearPending() {
        pendingFiles = []
    }

    function isImageFile(path) {
        var lower = path.toLowerCase()
        return lower.endsWith(".png") || lower.endsWith(".jpg") ||
               lower.endsWith(".jpeg") || lower.endsWith(".gif") ||
               lower.endsWith(".bmp") || lower.endsWith(".webp")
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // 顶部拖拽手柄 —— 鼠标上下拖动可调整输入区高度
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#ddd"

            MouseArea {
                id: dragArea
                anchors.fill: parent
                anchors.topMargin: -4
                anchors.bottomMargin: -4
                hoverEnabled: true
                cursorShape: Qt.SizeVerCursor
                property real startY: 0
                property real startHeight: 0

                onPressed: function(mouse) {
                    startY = mapToGlobal(mouse.x, mouse.y).y
                    startHeight = chatInput.inputHeight
                }
                onPositionChanged: function(mouse) {
                    if (!pressed) return
                    var currentY = mapToGlobal(mouse.x, mouse.y).y
                    var delta = startY - currentY
                    var newH = Math.max(chatInput.minInputHeight,
                                        Math.min(chatInput.maxInputHeight, startHeight + delta))
                    chatInput.inputHeight = newH
                }
            }
        }

        // 工具栏
        RowLayout {
            id: toolBar
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            Layout.topMargin: 4
            spacing: 2

            // 发送图片按钮
            ToolButton {
                width: 28; height: 28
                contentItem: Label {
                    text: "\uD83D\uDDBC"   // 🖼
                    font.pixelSize: 18
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                ToolTip.text: "\u53D1\u9001\u56FE\u7247"
                ToolTip.visible: hovered
                onClicked: imageDialog.open()
            }

            // 发送文件按钮
            ToolButton {
                width: 28; height: 28
                contentItem: Label {
                    text: "\uD83D\uDCC1"   // 📁
                    font.pixelSize: 18
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                ToolTip.text: "\u53D1\u9001\u6587\u4EF6"
                ToolTip.visible: hovered
                onClicked: fileDialog.open()
            }

            // 录音按钮
            ToolButton {
                id: micBtn
                width: 28; height: 28
                contentItem: Label {
                    text: chatInput._recActive ? "\u23F9" : "\uD83C\uDFA4"  // ⏹ / 🎤
                    font.pixelSize: chatInput._recActive ? 16 : 18
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: chatInput._recActive ? "#fa5151" : "black"
                }
                ToolTip.text: chatInput._recActive
                              ? ("\u505C\u6B62\u5F55\u97F3 (" + chatInput._recSeconds + "\u79D2)")
                              : "\u5F55\u5236\u8BED\u97F3"
                ToolTip.visible: hovered
                ToolTip.delay: 0
                onClicked: {
                    if (!chatInput._recActive) {
                        // 开始录音
                        var tmpFile = HttpClient.tempDir() + "/voice_" + Date.now() + ".wav"
                        tmpFile = tmpFile.replace(/\\/g, "/")
                        audioRecorder.outputLocation = Qt.url("file:///" + tmpFile)
                        chatInput._recSeconds = 0
                        chatInput._recActive = true
                        audioRecorder.record()
                        recTimer.start()
                    } else {
                        // 停止录音 → 触发 onRecorderStateChanged
                        recTimer.stop()
                        audioRecorder.stop()
                    }
                }
            }

            // 录音时长指示
            Label {
                visible: chatInput._recActive
                text: "\uD83D\uDD34 " + chatInput._recSeconds + "''"  // 🔴 N''
                font.pixelSize: 12
                color: "#fa5151"
            }

            Item { Layout.fillWidth: true }
        }

        // 附件预览区（有待发送文件时显示）
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: pendingFiles.length > 0 ? previewFlow.height + 12 : 0
            visible: pendingFiles.length > 0
            color: "#f5f5f5"

            Flow {
                id: previewFlow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 4
                spacing: 8

                Repeater {
                    model: pendingFiles.length
                    delegate: Rectangle {
                        width: pendingFiles[index].type === "image" ? 68 : Math.min(fileNameLabel.implicitWidth + 36, 180)
                        height: pendingFiles[index].type === "image" ? 68 : 32
                        radius: 4
                        color: "#fff"
                        border.color: "#e0e0e0"

                        // 图片预览缩略图
                        Image {
                            anchors.fill: parent
                            anchors.margins: 2
                            source: pendingFiles[index].type === "image" ? "file:///" + pendingFiles[index].path : ""
                            visible: pendingFiles[index].type === "image"
                            fillMode: Image.PreserveAspectCrop
                        }

                        // 文件名标签（文件类型）
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 20
                            visible: pendingFiles[index].type === "file"
                            spacing: 4

                            Label {
                                text: "\uD83D\uDCC4"
                                font.pixelSize: 14
                            }
                            Label {
                                id: fileNameLabel
                                text: pendingFiles[index].name
                                font.pixelSize: 11
                                color: "#555"
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                                maximumLineCount: 1
                            }
                        }

                        // 关闭按钮
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: -4
                            anchors.topMargin: -4
                            width: 16; height: 16; radius: 8
                            color: closeBtnArea.containsMouse ? "#ff4d4f" : "#ccc"

                            Label {
                                anchors.centerIn: parent
                                text: "\u2715"
                                font.pixelSize: 9
                                color: "white"
                            }

                            MouseArea {
                                id: closeBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: removePendingFile(index)
                            }
                        }
                    }
                }
            }
        }

        // 文本输入区 + 发送按钮
        RowLayout {
            id: inputRow
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.bottomMargin: 6
            spacing: 6

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                TextArea {
                    id: msgInput
                    placeholderText: "\u8F93\u5165\u6D88\u606F..."
                    wrapMode: TextArea.Wrap
                    font.pixelSize: 14
                    background: Rectangle {
                        radius: 4
                        color: "white"
                        border.color: msgInput.activeFocus ? "#07c160" : "#e0e0e0"
                    }

                    // 右键菜单
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        cursorShape: Qt.IBeamCursor
                        onClicked: function(mouse) {
                            contextMenu.popup()
                        }
                    }

                    Menu {
                        id: contextMenu
                        MenuItem {
                            text: "\u526A\u5207"
                            enabled: msgInput.selectedText.length > 0
                            onTriggered: msgInput.cut()
                        }
                        MenuItem {
                            text: "\u590D\u5236"
                            enabled: msgInput.selectedText.length > 0
                            onTriggered: msgInput.copy()
                        }
                        MenuItem {
                            text: "\u7C98\u8D34"
                            onTriggered: {
                                var clip = HttpClient.getClipboardContent()
                                if (clip.type === "image") {
                                    var imgPath = HttpClient.saveClipboardImage()
                                    if (imgPath.length > 0)
                                        addPendingFile(imgPath, "image")
                                } else if (clip.type === "file") {
                                    var paths = clip.paths
                                    for (var i = 0; i < paths.length; i++) {
                                        var p = paths[i]
                                        addPendingFile(p, isImageFile(p) ? "image" : "file")
                                    }
                                } else if (clip.type === "text") {
                                    msgInput.insert(msgInput.cursorPosition, clip.text)
                                }
                            }
                        }
                        MenuItem {
                            text: "\u5168\u9009"
                            enabled: msgInput.text.length > 0
                            onTriggered: msgInput.selectAll()
                        }
                    }

                    Keys.onPressed: function(event) {
                        // Ctrl+V: 粘贴图片/文件到预览区
                        if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                            var clip = HttpClient.getClipboardContent()
                            if (clip.type === "image") {
                                var imgPath = HttpClient.saveClipboardImage()
                                if (imgPath.length > 0) {
                                    event.accepted = true
                                    addPendingFile(imgPath, "image")
                                    return
                                }
                            } else if (clip.type === "file") {
                                event.accepted = true
                                var paths = clip.paths
                                for (var i = 0; i < paths.length; i++) {
                                    var p = paths[i]
                                    if (isImageFile(p))
                                        addPendingFile(p, "image")
                                    else
                                        addPendingFile(p, "file")
                                }
                                return
                            }
                            // type === "text" 走默认粘贴行为，不拦截
                        }

                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (event.modifiers & Qt.ShiftModifier) {
                                // Shift+Enter: 插入换行
                                event.accepted = false
                            } else {
                                // Enter: 发送消息
                                event.accepted = true
                                doSend()
                            }
                        }
                    }
                }
            }

            Button {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 34
                text: "\u53D1\u9001"
                font.pixelSize: 13
                enabled: msgInput.text.trim().length > 0 || pendingFiles.length > 0

                background: Rectangle {
                    radius: 4
                    color: parent.enabled ? (parent.pressed ? "#059c4d" : "#07c160") : "#ccc"
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font: parent.font
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: doSend()
            }
        }
    }

    function doSend() {
        // 先发送待发附件
        for (var i = 0; i < pendingFiles.length; i++) {
            var f = pendingFiles[i]
            if (f.type === "image")
                sendImage(f.path)
            else
                sendFile(f.path)
        }
        clearPending()

        // 再发送文本
        var text = msgInput.text.trim()
        if (text.length > 0) {
            sendText(text)
        }
        msgInput.text = ""
    }

    FileDialog {
        id: fileDialog
        title: "\u9009\u62E9\u6587\u4EF6"
        onAccepted: {
            var path = selectedFile.toString()
            if (path.startsWith("file:///")) path = path.substring(8)
            addPendingFile(path, isImageFile(path) ? "image" : "file")
        }
    }

    FileDialog {
        id: imageDialog
        title: "\u9009\u62E9\u56FE\u7247"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.gif *.bmp *.webp)"]
        onAccepted: {
            var path = selectedFile.toString()
            if (path.startsWith("file:///")) path = path.substring(8)
            addPendingFile(path, "image")
        }
    }
}
