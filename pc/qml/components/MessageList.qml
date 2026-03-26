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

    // 记录是否用户主动向上滚动（用来决定新消息是否自动滚到底部）
    property bool _userScrolledUp: false
    // 加载更多前记录的 contentHeight，用于恢复滚动位置
    property real _prevContentHeight: 0
    // 上次 count，用于区分 prepend（头部加载）和 append（新消息）
    property int _prevCount: 0

    onCountChanged: {
        var added = count - _prevCount
        _prevCount = count

        if (added <= 0) {
            // clear() 或 model reset —— 重置所有滚动状态
            _prevContentHeight = 0
            _userScrolledUp = false
            Qt.callLater(function() { msgList.positionViewAtEnd() })
        } else if (_prevContentHeight > 0) {
            // 在头部插入旧消息后，恢复滚动位置
            Qt.callLater(function() {
                var delta = contentHeight - _prevContentHeight
                if (delta > 0) contentY += delta
                _prevContentHeight = 0
            })
        } else {
            // 新消息追加到尾部：除非用户明确上滚过，否则自动滚到底部
            if (!_userScrolledUp) {
                Qt.callLater(function() {
                    msgList.positionViewAtEnd()
                    _userScrolledUp = false   // 防止 positionViewAtEnd 后因布局延迟误判为上滚
                })
            }
        }
    }

    // 内容高度变化时：delegate 延迟渲染可能导致 positionViewAtEnd 后高度再次增长，
    // 此时需要二次滚到底部，否则 _userScrolledUp 会被误判为 true
    onContentHeightChanged: {
        if (_prevContentHeight === 0 && !_userScrolledUp && contentHeight > height) {
            Qt.callLater(function() { msgList.positionViewAtEnd() })
        }
    }

    onContentYChanged: {
        // 判断用户是否在底部（留 120px 余量）
        if (contentHeight <= height) {
            _userScrolledUp = false
        } else {
            var atBottom = (contentY + height + 120) >= contentHeight
            _userScrolledUp = !atBottom
        }

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
