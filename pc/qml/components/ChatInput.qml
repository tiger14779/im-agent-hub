import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// 聊天输入栏组件 —— 包含工具栏（表情/图片/文件）和文本输入区
Rectangle {
    id: chatInput
    implicitHeight: toolBar.height + inputRow.height + 12
    color: "#f5f5f5"

    signal sendText(string text)       // 发送文本消息
    signal sendFile(string filePath)   // 发送文件
    signal sendImage(string filePath)  // 发送图片

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // 顶部分割线
        Rectangle { Layout.fillWidth: true; height: 1; color: "#ddd" }

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

            Item { Layout.fillWidth: true }
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
                Layout.minimumHeight: 36
                Layout.maximumHeight: 100

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

                    Keys.onPressed: function(event) {
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
                enabled: msgInput.text.trim().length > 0

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
        var text = msgInput.text.trim()
        if (text.length === 0) return
        sendText(text)
        msgInput.text = ""
    }

    FileDialog {
        id: fileDialog
        title: "\u9009\u62E9\u6587\u4EF6"
        onAccepted: {
            var path = selectedFile.toString()
            if (path.startsWith("file:///")) path = path.substring(8)
            chatInput.sendFile(path)
        }
    }

    FileDialog {
        id: imageDialog
        title: "\u9009\u62E9\u56FE\u7247"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.gif *.bmp *.webp)"]
        onAccepted: {
            var path = selectedFile.toString()
            if (path.startsWith("file:///")) path = path.substring(8)
            chatInput.sendImage(path)
        }
    }
}
