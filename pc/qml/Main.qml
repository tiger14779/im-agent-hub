import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ImAgentHub

ApplicationWindow {
    id: root
    width: 1000
    height: 680
    minimumWidth: 860
    minimumHeight: 540
    visible: true
    title: "IM Agent Hub - \u5BA2\u670D\u7AEF"
    color: "#ebebeb"

    onClosing: function(close) {
        WxBridge.stopServer()
        WsClient.disconnect()
    }

    // ── Global state ───────────────────────────────────
    property string staffUserId: ""
    property string staffNickname: ""
    property string authToken: ""
    property string serverUrl: ""

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
