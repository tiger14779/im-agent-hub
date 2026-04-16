import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import ImAgentHub

// VoiceCallWindow — pure-QML UI, uses AudioCallEngine for native PCM audio
// Phase lifecycle: idle -> outgoing/incoming -> active -> idle
Item {
    id: root

    // ── Public API (used by ChatPage.qml) ─────────────────────────────
    property string phase:       "idle"    // idle | incoming | connecting | outgoing | active
    property string peerId:      ""
    property string peerName:    ""
    property string roomId:      ""
    property string audioToken:  ""
    property string audioWsBase: ""
    property string myId:        ""
    property string myName:      ""
    property string statusMsg:   ""        // shown in popup before auto-close

    signal callEnded()
    signal callAccepted()
    signal callRejected()

    // ── Internal state ────────────────────────────────────────────────
    property bool   _muted:    false
    property bool   _speaking: false
    property int    _secs:     0
    property string _timerStr: "00:00"

    // AudioCallEngine 对端说话状态
    Connections {
        target: AudioCallEngine
        function onPeerSpeaking(speaking) { root._speaking = speaking }
    }
    // ── 来电铃声（由 AudioCallEngine C++ 合成，仅来电时播放）────────────────────
    onPhaseChanged: {
        if (phase === "incoming") {
            AudioCallEngine.playRingtone()
        } else {
            AudioCallEngine.stopRingtone()
        }
    }

    // ── Timers ────────────────────────────────────────────────────────

    // Auto-close popup after reject/busy hint
    Timer {
        id: autoCloseTimer
        interval: 2500; repeat: false
        onTriggered: {
            outgoingTimeoutTimer.stop()  // 确保呼出计时器不会再触发
            root.reset()
        }
    }

    // 暴露给外部使用（ChatPage 可将其 stop）
    property alias outgoingTimeoutTimer: outgoingTimeoutTimer

    // No-answer timeout for outgoing calls (30s)
    Timer {
        id: outgoingTimeoutTimer
        interval: 30000; repeat: false
        running: root.phase === "outgoing"
        onTriggered: {
            root.statusMsg = "\u65e0\u4eba\u63a5\u542c"
            autoCloseTimer.start()
            root.callEnded()
        }
    }

    // Call duration counter
    Timer {
        id: durationTimer
        interval: 1000; repeat: true
        running: root.phase === "active"
        onTriggered: {
            root._secs++
            var m = Math.floor(root._secs / 60)
            var s = root._secs % 60
            root._timerStr = (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
        }
    }

    // ── Incoming / Outgoing popup (independent non-modal window) ─────

    Window {
        id: callDialog
        width: 300; height: 390
        flags:    Qt.Window | Qt.WindowStaysOnTopHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        modality: Qt.NonModal
        color: "#0f0f1c"
        visible: root.phase === "incoming" || root.phase === "connecting" || root.phase === "outgoing" || root.statusMsg.length > 0
        title:  root.phase === "incoming"   ? ("\u6765\u7535 \u00b7 " + root.peerName)
              : root.phase === "connecting" ? ("\u8fde\u63a5\u4e2d \u00b7 " + root.peerName)
              : root.phase === "outgoing"   ? ("\u547c\u53eb\u4e2d \u00b7 " + root.peerName)
              : "\u901a\u8bdd\u63d0\u793a"
        onClosing: { autoCloseTimer.stop(); root.reset() }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0
            width: parent.width - 56

            // Avatar with pulsing ring (incoming) or static (outgoing/status)
            Item {
                Layout.alignment: Qt.AlignHCenter
                width: 92; height: 92

                Rectangle {
                    id: pulseRing
                    anchors.centerIn: parent
                    width: 92; height: 92; radius: 46
                    color: "transparent"
                    border.color: "#667eea"; border.width: 2
                    opacity: 0
                }
                SequentialAnimation {
                    running: root.phase === "incoming" && root.statusMsg.length === 0
                    loops: Animation.Infinite
                    NumberAnimation { target: pulseRing; property: "opacity"; to: 0.6; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { target: pulseRing; property: "opacity"; to: 0;   duration: 900; easing.type: Easing.InOutSine }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 74; height: 74; radius: 37
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#667eea" }
                        GradientStop { position: 1; color: "#764ba2" }
                    }
                    Label {
                        anchors.centerIn: parent
                        text: root.peerName.length > 0 ? root.peerName.charAt(0).toUpperCase() : "?"
                        color: "white"; font.pixelSize: 30; font.bold: true
                    }
                }
            }

            Item { height: 16 }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: root.peerName
                color: "white"; font.pixelSize: 20; font.bold: true
                elide: Text.ElideRight; Layout.maximumWidth: parent.width
            }

            Item { height: 8 }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: root.statusMsg.length > 0 ? root.statusMsg
                    : root.phase === "incoming"   ? "\u9080\u8bf7\u4f60\u8bed\u97f3\u901a\u8bdd"
                    : root.phase === "connecting" ? "\u6b63\u5728\u8fde\u63a5..."
                    : "\u6b63\u5728\u547c\u53eb..."
                color: root.statusMsg.length > 0 ? "#f87171" : "#9ca3af"
                font.pixelSize: 13
            }

            Item { height: 40 }

            // Incoming: Reject + Accept
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 52
                visible: root.phase === "incoming" && root.statusMsg.length === 0

                ColumnLayout { spacing: 8
                    Rectangle {
                        width: 64; height: 64; radius: 32; color: "#ef4444"
                        Layout.alignment: Qt.AlignHCenter
                        Label { anchors.centerIn: parent; text: "\uD83D\uDCF5"; font.pixelSize: 26 }
                        MouseArea { anchors.fill: parent; onClicked: root.callRejected() }
                    }
                    Label { text: "\u62d2\u7edd"; color: "#9ca3af"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                }

                ColumnLayout { spacing: 8
                    Rectangle {
                        width: 64; height: 64; radius: 32; color: "#22c55e"
                        Layout.alignment: Qt.AlignHCenter
                        Label { anchors.centerIn: parent; text: "\uD83D\uDCDE"; font.pixelSize: 26 }
                        MouseArea { anchors.fill: parent; onClicked: root.callAccepted() }
                    }
                    Label { text: "\u63a5\u542c"; color: "#9ca3af"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                }
            }

            // Outgoing: Cancel only
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                visible: root.phase === "outgoing" && root.statusMsg.length === 0

                Rectangle {
                    width: 64; height: 64; radius: 32; color: "#ef4444"
                    Layout.alignment: Qt.AlignHCenter
                    Label { anchors.centerIn: parent; text: "\uD83D\uDCF5"; font.pixelSize: 26 }
                    MouseArea { anchors.fill: parent; onClicked: root.callEnded() }
                }
                Label { text: "\u53d6\u6d88"; color: "#9ca3af"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
            }

            // Status hint (reject/busy/no-answer): show a close button immediately
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                visible: root.statusMsg.length > 0

                Rectangle {
                    width: 64; height: 64; radius: 32; color: "#6b7280"
                    Layout.alignment: Qt.AlignHCenter
                    Label { anchors.centerIn: parent; text: "\u2715"; font.pixelSize: 26; color: "white" }
                    MouseArea { anchors.fill: parent; onClicked: { autoCloseTimer.stop(); outgoingTimeoutTimer.stop(); root.reset() } }
                }
                Label { text: "\u5173\u95ed"; color: "#9ca3af"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
            }
        }
    }

    // ── Active call panel (draggable, stays inside main window) ────────

    Rectangle {
        id: activePanel
        visible: root.phase === "active"
        width: 310; height: 400
        radius: 14
        color: "#0f0f1c"
        border.color: "#667eea"; border.width: 1.5
        z: 200

        // Position on first show; drag keeps the user-chosen position
        onVisibleChanged: {
            if (visible && root.width > 40 && root.height > 40) {
                x = root.width  - activePanel.width  - 16
                y = root.height - activePanel.height - 16
            }
        }

        // Draggable title bar ─────────────────────────────────────────
        Rectangle {
            id: titleBar
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 44
            color: "#16162a"; radius: 14
            // Fill bottom rounded corners
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 14; color: "#16162a"
            }

            MouseArea {
                anchors.fill: parent
                drag.target: activePanel
                drag.minimumX: 0
                drag.maximumX: root.width  > activePanel.width  ? root.width  - activePanel.width  : 0
                drag.minimumY: 0
                drag.maximumY: root.height > activePanel.height ? root.height - activePanel.height : 0
            }

            Label {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "\uD83D\uDCDE \u901a\u8bdd\u4e2d \u00b7 " + root.peerName
                color: "white"; font.pixelSize: 13; font.bold: true
                elide: Text.ElideRight
                width: parent.width - 56
            }
            Rectangle {
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                width: 28; height: 28; radius: 14; color: "#ef4444"
                Label { anchors.centerIn: parent; text: "\u2715"; color: "white"; font.pixelSize: 12; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: root.callEnded() }
            }
        }

        // Content ─────────────────────────────────────────────────────
        ColumnLayout {
            anchors {
                top: titleBar.bottom; topMargin: 10
                left: parent.left;  leftMargin: 18
                right: parent.right; rightMargin: 18
                bottom: parent.bottom; bottomMargin: 18
            }
            spacing: 0

            // Avatar with speaking glow
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                width: 88; height: 88

                Rectangle {
                    anchors.centerIn: parent
                    width: 88; height: 88; radius: 44
                    color: "transparent"
                    border.color: "#667eea"
                    border.width: 3
                    opacity: root._speaking ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 72; height: 72; radius: 36
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#667eea" }
                        GradientStop { position: 1; color: "#764ba2" }
                    }
                    Label {
                        anchors.centerIn: parent
                        text: root.peerName.length > 0 ? root.peerName.charAt(0).toUpperCase() : "?"
                        color: "white"; font.pixelSize: 28; font.bold: true
                    }
                }
            }

            Item { height: 12 }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: root.peerName
                color: "white"; font.pixelSize: 16; font.bold: true
            }

            Item { height: 10 }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: root._timerStr
                color: "#7ecdff"; font.pixelSize: 30; font.bold: true
                font.letterSpacing: 2
            }

            Item { Layout.fillHeight: true }

            // Action buttons
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 44
                Layout.bottomMargin: 4

                ColumnLayout { spacing: 8
                    Rectangle {
                        width: 60; height: 60; radius: 30
                        color: root._muted ? "#f59e0b" : "#374151"
                        Layout.alignment: Qt.AlignHCenter
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Label { anchors.centerIn: parent; text: root._muted ? "\uD83D\uDD07" : "\uD83C\uDFA4"; font.pixelSize: 24 }
                        MouseArea { anchors.fill: parent; onClicked: root._toggleMute() }
                    }
                    Label {
                        text: root._muted ? "\u53d6\u6d88\u9759\u97f3" : "\u9759\u97f3"
                        color: "#9ca3af"; font.pixelSize: 11
                        Layout.alignment: Qt.AlignHCenter
                    }
                }

                ColumnLayout { spacing: 8
                    Rectangle {
                        width: 60; height: 60; radius: 30; color: "#ef4444"
                        Layout.alignment: Qt.AlignHCenter
                        Label { anchors.centerIn: parent; text: "\uD83D\uDCF5"; font.pixelSize: 24 }
                        MouseArea { anchors.fill: parent; onClicked: root.callEnded() }
                    }
                    Label { text: "\u6302\u65ad"; color: "#9ca3af"; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                }
            }
        }
    }

    // ── Methods ───────────────────────────────────────────────────────

    function _toggleMute() {
        _muted = !_muted
        AudioCallEngine.setMuted(_muted)
    }

    function startActiveCall() {
        _secs     = 0
        _timerStr = "00:00"
        _muted    = false
        _speaking = false
        AudioCallEngine.start(audioWsBase, HttpClient.baseUrl, roomId, audioToken)
        phase = "active"
    }

    function reset() {
        autoCloseTimer.stop()
        outgoingTimeoutTimer.stop()
        ringtoneEffect.stop()
        AudioCallEngine.stopRingtone()
        durationTimer.stop()
        AudioCallEngine.stop()
        phase     = "idle"
        statusMsg = ""
        _secs     = 0
        _timerStr = "00:00"
        _muted    = false
        _speaking = false
        peerId      = ""
        peerName    = ""
        roomId      = ""
        audioToken  = ""
    }
}