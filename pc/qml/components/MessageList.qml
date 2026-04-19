import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 消息列表组件 —— 显示聊天消息气泡列表，支持向上滚动加载更多
ListView {
    id: msgList
    clip: true
    spacing: 4
    verticalLayoutDirection: ListView.TopToBottom

    // 初始化期间隐藏列表，防止会话切换时用户看到从顶跳到底的闪烁
    property bool _initializing: false
    opacity: _initializing ? 0 : 1

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

    // ── 滚动状态（Telegram 风格）───────────────────────────
    // 用户是否在列表底部附近（决定收到对方新消息时是否自动滚底）
    property bool _atBottom: true
    // 防止向上滚动时重复触发 loadMore
    property bool _loadMoreTriggered: false
    // load more 触发前记录的第一个可见 item 的 index（用于 positionViewAtIndex 恢复位置）
    property int  _anchorIndex: 0
    // load more 触发前的 count（用于计算插入了多少条，进而计算新的 anchorIndex）
    property int  _countBeforeLoad: -1
    // scrollToBottomAndReveal 重试计数（逐帧重试，等 delegate 渲染完成）
    property int _revealAttempts: 0

    // ── 公开方法：供 ChatPage 调用 ─────────────────────────

    // 会话打开/切换时调用：隐藏列表，定位到底部后显示
    function scrollToBottomAndReveal() {
        _atBottom = true
        if (count === 0) {
            _initializing = false
            return
        }
        _initializing = true
        _revealAttempts = 5
        _doReveal()
    }

    // 逐帧重试定位到底部，直到真正到达底部或重试耗尽
    function _doReveal() {
        msgList.positionViewAtEnd()
        _initializing = false
    }

    // 收到对方消息时调用：若用户在底部则跟随，已上滑则不打扰
    // （完全等同 Telegram：在底部时自动跟随新消息，不在底部时静默追加）
    function scrollDownOneItem() {
        if (!_atBottom) return   // 用户已上滑阅读历史，完全不动
        // 等 delegate 渲染完（contentHeight 更新后）再滚底，避免用旧高度计算偏移
        Qt.callLater(function() { msgList.positionViewAtEnd() })
    }

    // 自己发送消息后调用：强制跳到底部
    function scrollToBottomForSelf() {
        Qt.callLater(function() { msgList.positionViewAtEnd() })
    }

    // ── 核心：count 变化时的滚动决策 ──────────────────────
    onCountChanged: {
        if (count === 0) {
            // 模型被清空 —— 重置所有状态
            _atBottom = true
            _loadMoreTriggered = false
            _anchorIndex = 0
            _countBeforeLoad = -1
            _initializing = true
            return
        }

        if (_countBeforeLoad >= 0 && count > _countBeforeLoad) {
            // 头部插入了历史消息（load more 完成）
            // positionViewAtIndex 精确恢复位置，不依赖 contentHeight 估算
            var insertedCount = count - _countBeforeLoad
            var targetIndex = _anchorIndex + insertedCount
            var captured = targetIndex
            _countBeforeLoad = -1
            Qt.callLater(function() {
                if (captured < msgList.count)
                    msgList.positionViewAtIndex(captured, ListView.Beginning)
                _loadMoreTriggered = false
            })
        }
        // 尾部追加新消息的滚动由 ChatPage 显式调用:
        //   对方消息 → scrollDownOneItem()
        //   自己消息 → scrollToBottomForSelf()
    }

    // loadingMore（服务器请求）变为 false 时解锁 loadMore 触发器
    onLoadingMoreChanged: {
        if (!loadingMore) {
            _countBeforeLoad = -1   // 清理快照（空结果时 onCountChanged 不会触发）
            _loadMoreTriggered = false
        }
    }

    // hasMore 变为 false 时同步清理状态
    onHasMoreChanged: {
        if (!hasMore) {
            _loadMoreTriggered = false
            _countBeforeLoad = -1
        }
    }

    onContentYChanged: {
        // 实时更新 _atBottom
        // 阈值改为 20px：用户只要上滑超过 20px，就视为离开底部，不再自动跟随
        // （旧阈值 120px 导致用户稍微上滑就被弹回底部）
        if (contentHeight <= height) {
            _atBottom = true
        } else {
            _atBottom = (contentY + height + 20) >= contentHeight
        }

        // 向上滚到顶部附近 —— 触发加载更多历史消息
        // 阈值 200px：滚到顶部 2-3 条消息位置就提前加载，不需要滑到绝对顶部
        if (!_loadMoreTriggered && !loadingMore && hasMore && count > 0 && contentY < 200) {
            var idx = msgList.indexAt(0, contentY + 1)
            _anchorIndex = (idx < 0) ? 0 : idx
            _countBeforeLoad = count
            _loadMoreTriggered = true
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
            // 图片加载完成不再触发任何滚动，避免历史图片加载时把用户弹回底部
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
