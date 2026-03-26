import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 消息列表组件 —— 显示聊天消息气泡列表，支持向上滚动加载更多
ListView {
    id: msgList
    clip: true
    spacing: 4
    verticalLayoutDirection: ListView.TopToBottom

    property string selfId: ""          // 当前用户ID，用于判断消息方向
    property bool loadingMore: false    // 是否正在加载更多历史消息
    property bool hasMore: true         // 是否还有更多历史消息

    signal requestLoadMore()            // 向上滚动到顶部时触发

    // 加载更多前记录的 contentHeight，用于恢复滚动位置
    property real _prevContentHeight: 0
    // 上次 count，用于区分 prepend（头部加载）和 append（新消息）
    property int _prevCount: 0

    // 实时计算是否在底部附近（150px 余量），不再用 flag 追踪
    function _isNearBottom() {
        return contentHeight <= height ||
               (contentY + height + 150) >= contentHeight
    }

    onCountChanged: {
        var added = count - _prevCount
        _prevCount = count

        if (added <= 0) {
            // clear() 或 model reset
            _prevContentHeight = 0
            Qt.callLater(function() { msgList.positionViewAtEnd() })
        } else if (_prevContentHeight > 0) {
            // 在头部插入旧消息后，恢复滚动位置
            Qt.callLater(function() {
                var delta = contentHeight - _prevContentHeight
                if (delta > 0) contentY += delta
                _prevContentHeight = 0
            })
        } else {
            // 新消息追加到尾部：直接检查当前位置，在底部附近则自动滚到底
            if (_isNearBottom()) {
                Qt.callLater(function() { msgList.positionViewAtEnd() })
            }
        }
    }

    // delegate 延迟渲染可能导致 positionViewAtEnd 后高度再次增长，
    // 在底部附近时二次补偿滚动
    onContentHeightChanged: {
        if (_prevContentHeight === 0 && contentHeight > height && _isNearBottom()) {
            Qt.callLater(function() { msgList.positionViewAtEnd() })
        }
    }

    onContentYChanged: {
        // 滚动到顶部附近时触发加载更多
        if (contentY < 50 && hasMore && !loadingMore && count > 0) {
            _prevContentHeight = contentHeight
            requestLoadMore()
        }
    }

    header: Column {
        width: msgList.width
        // 加载更多提示
        Text {
            visible: msgList.loadingMore
            text: "加载中..."
            color: "#999"
            font.pixelSize: 12
            anchors.horizontalCenter: parent.horizontalCenter
            padding: 8
        }
        Text {
            visible: !msgList.hasMore && !msgList.loadingMore
            text: "没有更多消息了"
            color: "#ccc"
            font.pixelSize: 12
            anchors.horizontalCenter: parent.horizontalCenter
            padding: 8
        }
        Item { height: 8; width: 1 }
    }

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
