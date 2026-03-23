import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ListView {
    id: msgList
    clip: true
    spacing: 4
    verticalLayoutDirection: ListView.TopToBottom

    property string selfId: ""

    // Auto-scroll to bottom on new message
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
