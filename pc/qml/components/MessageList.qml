import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 消息列表组件 —— 显示聊天消息气泡列表
ListView {
    id: msgList
    clip: true
    spacing: 4
    verticalLayoutDirection: ListView.TopToBottom

    property string selfId: ""  // 当前用户ID，用于判断消息方向

    // 新消息时自动滚动到底部
    onCountChanged: {
        Qt.callLater(function() {
            msgList.positionViewAtEnd()
        })
    }

    header: Item { height: 8 }
    footer: Item { height: 8 }

    delegate: MessageBubble {
        width: msgList.width
        isSelf: model.isSelf
        contentType: model.contentType
        textContent: model.textContent
        imageUrl: model.imageUrl
        fileName: model.fileName
        fileSize: model.fileSize
        voiceDuration: model.voiceDuration
        msgStatus: model.status
        sendTime: model.sendTime
    }

    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
    }
}
