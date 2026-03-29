import QtQuick
import QtQuick.Controls

// 全屏图片查看器 —— 支持鼠标滚轮缩放和拖拽平移
Popup {
    id: viewer
    modal: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    anchors.centerIn: parent
    width: parent ? parent.width : 800
    height: parent ? parent.height : 600
    padding: 0

    property string imageSource: ""

    background: Rectangle { color: "#cc000000" }

    // 关闭按钮
    Button {
        z: 10
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        width: 36; height: 36
        flat: true
        contentItem: Label {
            text: "\u2715"
            color: "white"
            font.pixelSize: 20
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle { radius: 18; color: closeBtnArea.containsMouse ? "#88ffffff" : "#55ffffff" }
        MouseArea {
            id: closeBtnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: viewer.close()
        }
    }

    // 可缩放/拖拽的图片容器
    Item {
        anchors.fill: parent

        property real imgScale: 1.0
        property real imgX: 0
        property real imgY: 0

        Image {
            id: img
            source: viewer.imageSource
            fillMode: Image.PreserveAspectFit

            // 基础尺寸：不超过容器 90%
            readonly property real baseW: sourceSize.width > 0
                ? Math.min(sourceSize.width, viewer.width * 0.9) : viewer.width * 0.5
            readonly property real baseH: sourceSize.width > 0
                ? baseW / (sourceSize.width / sourceSize.height) : viewer.height * 0.5

            width: baseW * parent.imgScale
            height: baseH * parent.imgScale
            x: (parent.width - width) / 2 + parent.imgX
            y: (parent.height - height) / 2 + parent.imgY
            smooth: true

            BusyIndicator {
                anchors.centerIn: parent
                running: img.status === Image.Loading
                visible: running
            }

            Label {
                anchors.centerIn: parent
                text: "\u56FE\u7247\u52A0\u8F7D\u5931\u8D25"
                color: "white"
                font.pixelSize: 14
                visible: img.status === Image.Error
            }
        }

        // 拖拽 + 双击重置
        MouseArea {
            anchors.fill: parent
            property real pressX: 0
            property real pressY: 0
            property real startOffsetX: 0
            property real startOffsetY: 0

            onPressed: function(mouse) {
                pressX = mouse.x
                pressY = mouse.y
                startOffsetX = parent.imgX
                startOffsetY = parent.imgY
            }
            onPositionChanged: function(mouse) {
                if (pressed) {
                    parent.imgX = startOffsetX + (mouse.x - pressX)
                    parent.imgY = startOffsetY + (mouse.y - pressY)
                }
            }
            onDoubleClicked: {
                parent.imgScale = 1.0
                parent.imgX = 0
                parent.imgY = 0
            }
            onWheel: function(wheel) {
                var delta = wheel.angleDelta.y > 0 ? 0.15 : -0.15
                parent.imgScale = Math.max(0.1, Math.min(8.0, parent.imgScale + delta))
            }
        }
    }

    onClosed: {
        imageSource = ""
    }

    onOpened: {
        // 重置缩放和偏移
        var container = contentItem.children[0]
        if (container) {
            container.imgScale = 1.0
            container.imgX = 0
            container.imgY = 0
        }
    }
}
