import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ImAgentHub

Page {
    id: loginRoot
    signal loginDone(string userId, string nickname, string token, string baseUrl)

    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#2c2c2c" }
            GradientStop { position: 1.0; color: "#1a1a2e" }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 20
        width: 340

        // Logo / Title
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 72; height: 72
            radius: 36
            color: "#07c160"

            Label {
                anchors.centerIn: parent
                text: "\u2709"
                font.pixelSize: 36
                color: "white"
            }
        }

        Label {
            text: "IM Agent Hub"
            font.pixelSize: 26
            font.bold: true
            color: "white"
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            text: "\u5BA2\u670D\u7AEF"  // 客服端
            font.pixelSize: 13
            color: "#aaa"
            Layout.alignment: Qt.AlignHCenter
        }

        Item { height: 8 }

        // Staff User ID
        TextField {
            id: userIdField
            placeholderText: "\u8BF7\u8F93\u5165\u5BA2\u670DID"  // 请输入客服ID
            font.pixelSize: 14
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            color: "white"
            placeholderTextColor: "#777"
            horizontalAlignment: Text.AlignHCenter
            background: Rectangle {
                radius: 8
                color: "#3a3a3a"
                border.color: userIdField.activeFocus ? "#07c160" : "#555"
                border.width: 1
            }
            Keys.onReturnPressed: doLogin()
        }

        // Server URL
        TextField {
            id: serverField
            text: "http://localhost:8080"
            placeholderText: "\u670D\u52A1\u5668\u5730\u5740"  // 服务器地址
            font.pixelSize: 14
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            color: "white"
            placeholderTextColor: "#777"
            horizontalAlignment: Text.AlignHCenter
            background: Rectangle {
                radius: 8
                color: "#3a3a3a"
                border.color: serverField.activeFocus ? "#07c160" : "#555"
                border.width: 1
            }
            Keys.onReturnPressed: doLogin()
        }

        // Login button
        Button {
            id: loginBtn
            text: loginBusy ? "\u767B\u5F55\u4E2D..." : "\u767B \u5F55"
            enabled: userIdField.text.length > 0 && !loginBusy
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            font.pixelSize: 16

            property bool loginBusy: false

            background: Rectangle {
                radius: 8
                color: loginBtn.enabled ? (loginBtn.pressed ? "#059c4d" : "#07c160") : "#555"
            }
            contentItem: Text {
                text: loginBtn.text
                color: "white"
                font: loginBtn.font
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: doLogin()
        }

        // Error label
        Label {
            id: errorLabel
            color: "#e74c3c"
            font.pixelSize: 12
            Layout.alignment: Qt.AlignHCenter
            visible: text.length > 0
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Component.onCompleted: {
        var cfg = HttpClient.loadLoginConfig()
        if (cfg["userId"] && cfg["userId"].length > 0)
            userIdField.text = cfg["userId"]
        if (cfg["serverUrl"] && cfg["serverUrl"].length > 0)
            serverField.text = cfg["serverUrl"]
    }

    function doLogin() {
        if (userIdField.text.trim().length === 0) return
        loginBtn.loginBusy = true
        errorLabel.text = ""
        HttpClient.baseUrl = serverField.text.trim()
        HttpClient.login(userIdField.text.trim())
    }

    Connections {
        target: HttpClient
        function onLoginSuccess(data) {
            loginBtn.loginBusy = false
            var userId   = data["userId"]   ?? userIdField.text.trim()
            var nickname = data["nickname"] ?? userId
            var token    = data["token"]    ?? ""
            var baseUrl  = serverField.text.trim()

            HttpClient.token = token
            HttpClient.serviceUserId = userId

            // Save login config for next launch
            HttpClient.saveLoginConfig(userId, baseUrl)

            // Connect WS to our Go backend (not OpenIM directly)
            WsClient.connectToServer(baseUrl, userId, token)

            loginRoot.loginDone(userId, nickname, token, baseUrl)
        }
        function onLoginFailed(err) {
            loginBtn.loginBusy = false
            errorLabel.text = err
        }
    }
}
