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
    property string peerAvatarUrl: ""   // 对方头像URL
    property string selfAvatarUrl: ""   // 自己的头像URL
    property string serverUrl: ""       // 服务器地址（用于拼接头像URL）
    property bool loadingMore: false    // 是否正在加载更多历史消息
    property bool hasMore: true         // 是否还有更多历史消息

    signal requestLoadMore()            // 向上滚动到顶部时触发
    signal deleteRequested(string serverMsgId, string clientMsgId)  // 请求删除消息
    signal imageViewRequested(string url)  // 请求查看大图

    // 抑制自动滚动（合并同步期间设为 true，避免干扰用户浏览）
    property bool suppressAutoScroll: false

    // 记录是否用户主动向上滚动（用来决定新消息是否自动滚到底部）
    property bool _userScrolledUp: false
    // 加载更多前记录的 contentHeight，用于恢复滚动位置
    property real _prevContentHeight: 0
    // 上次 count，用于区分 prepend（头部加载）和 append（新消息）
    property int _prevCount: 0
    // 需要滚到底部的标志（跨越 clear→append 两步操作）
    property bool _needScrollToEnd: false

    // 补偿定时器：delegate 异步渲染后多次确认滚到底部
    // 最多重试6次（共 ~500ms），到底后立即停止
    Timer {
        id: _scrollFixTimer
        interval: 80
        repeat: true
        property int _retries: 0
        onTriggered: {
            _retries++
            if (_retries > 6 || _userScrolledUp || suppressAutoScroll) {
                stop()
                return
            }
            msgList.positionViewAtEnd()
            // 已到底则停止
            if (contentHeight > 0 && contentHeight <= height + 10) {
                stop()
            } else if (contentHeight > height && (contentY + height + 5) >= contentHeight) {
                stop()
            }
        }
        function begin() {
            _retries = 0
            restart()
        }
    }

    onCountChanged: {
        var added = count - _prevCount
        _prevCount = count

        if (added <= 0) {
            // clear() 或 model reset —— 重置所有滚动状态，标记需要滚底
            _prevContentHeight = 0
            _userScrolledUp = false
            _needScrollToEnd = true
        } else if (_needScrollToEnd) {
            // clear 后紧接而来的 append/prepend —— 初次加载，滚到底部
            _needScrollToEnd = false
            _prevContentHeight = 0
            Qt.callLater(function() {
                msgList.positionViewAtEnd()
                _scrollFixTimer.begin()
            })
        } else if (_prevContentHeight > 0) {
            // 在头部插入旧消息后，恢复滚动位置
            Qt.callLater(function() {
                var delta = contentHeight - _prevContentHeight
                if (delta > 0) contentY += delta
                _prevContentHeight = 0
            })
        } else {
            // 新消息追加到尾部：除非用户明确上滚过或合并同步中，否则自动滚到底部
            if (!_userScrolledUp && !suppressAutoScroll) {
                Qt.callLater(function() {
                    msgList.positionViewAtEnd()
                    _scrollFixTimer.begin()
                })
            }
        }
    }

    // 仅在用户手势（拖拽/滑动）停止后判断是否上滚，
    // 程序触发的 positionViewAtEnd() 不会触发此信号，彻底避免误判
    onMovementEnded: {
        if (contentHeight <= height) {
            _userScrolledUp = false
        } else {
            var atBottom = (contentY + height + 120) >= contentHeight
            _userScrolledUp = !atBottom
        }
    }

    onContentYChanged: {
        // 单向重置：到达底部时重置为 false（覆盖鼠标滚轮回到底部的场景）
        // 注意：永远不在此处设为 true，避免内容高度增长时的布局调整被误判为用户上滚
        if (contentHeight > height) {
            var atBottom = (contentY + height + 120) >= contentHeight
            if (atBottom) _userScrolledUp = false
        } else {
            _userScrolledUp = false
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
        serverMsgId: model.serverMsgID || ""
        clientMsgId: model.clientMsgID || ""
        senderName: model.senderName || ""
        isGroup: model.isGroup || false
        avatarUrl: model.isSelf ? (function() {
            var url = msgList.selfAvatarUrl || ""
            if (url.length > 0 && url.charAt(0) === '/')
                return msgList.serverUrl + url
            return url
        })() : (function() {
            // 群消息：使用每条消息的发送者头像；私聊：使用全局 peerAvatarUrl
            var url = (model.isGroup && model.senderAvatar) ? model.senderAvatar : (msgList.peerAvatarUrl || "")
            if (url.length > 0 && url.charAt(0) === '/')
                return msgList.serverUrl + url
            return url
        })()

        onImageLoaded: {
            if (!msgList._userScrolledUp && !msgList.suppressAutoScroll)
                _scrollFixTimer.begin()
        }
        onDeleteRequested: function(sMsgId, cMsgId) {
            msgList.deleteRequested(sMsgId, cMsgId)
        }
        onImageViewRequested: function(url) {
            msgList.imageViewRequested(url)
        }
    }

    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
    }
}
