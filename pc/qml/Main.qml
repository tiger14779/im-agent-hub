import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root
    width: 1000
    height: 680
    minimumWidth: 860
    minimumHeight: 540
    visible: true
    title: "IM Agent Hub - 客服端"
    color: "#ebebeb"

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
