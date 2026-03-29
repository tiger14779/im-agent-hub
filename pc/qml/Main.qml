import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ImAgentHub

ApplicationWindow {
    id: root
    width: 1000
    height: 680
    minimumWidth: 600
    minimumHeight: 540
    visible: true
    title: "IM Agent Hub - \u5BA2\u670D\u7AEF"
    color: "#ebebeb"

    // 窗口关闭时停止桥接服务和 WebSocket 连接
    onClosing: function(close) {
        WxBridge.stopServer()
        WsClient.disconnect()
    }

    // ── 全局状态（登录后填充）─────────────────
    property string staffUserId: ""    // 当前客服用户ID
    property string staffNickname: ""  // 当前客服昵称
    property string authToken: ""      // JWT 认证令牌
    property string serverUrl: ""      // 服务器地址

    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: loginPage
    }

    Component {
        id: loginPage
        LoginPage {
            onLoginDone: function(userId, nickname, token, baseUrl) {
                root.staffUserId  = userId
                root.staffNickname = nickname
                root.authToken    = token
                root.serverUrl    = baseUrl
                stackView.replace(chatPage)
            }
        }
    }

    Component {
        id: chatPage
        ChatPage {
            staffUserId:  root.staffUserId
            staffNickname: root.staffNickname
            authToken:    root.authToken
            serverUrl:    root.serverUrl
        }
    }
}
