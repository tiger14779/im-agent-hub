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

        // 是否为 gif（忽略查询参数与大小写）
        readonly property bool isGif: {
            var s = (viewer.imageSource || "").toLowerCase()
            var qIdx = s.indexOf("?")
            if (qIdx >= 0) s = s.substring(0, qIdx)
            return s.endsWith(".gif")
        }

        // 通用尺寸：取自当前激活的图片项 sourceSize
        property Item activeImg: imgLoader.item
        readonly property int srcW: activeImg ? activeImg.sourceSize.width : 0
        readonly property int srcH: activeImg ? activeImg.sourceSize.height : 0
        readonly property real baseW: srcW > 0
            ? Math.min(srcW, viewer.width * 0.9) : viewer.width * 0.5
        readonly property real baseH: srcW > 0
            ? baseW / (srcW / srcH) : viewer.height * 0.5

        Loader {
            id: imgLoader
            sourceComponent: parent.isGif ? animComp : staticComp
            width: parent.baseW * parent.imgScale
            height: parent.baseH * parent.imgScale
            x: (parent.width - width) / 2 + parent.imgX
            y: (parent.height - height) / 2 + parent.imgY
        }

        Component {
            id: staticComp
            Image {
                source: viewer.imageSource
                fillMode: Image.PreserveAspectFit
                smooth: true
                BusyIndicator {
                    anchors.centerIn: parent
                    running: parent.status === Image.Loading
                    visible: running
                }
                Label {
                    anchors.centerIn: parent
                    text: "\u56FE\u7247\u52A0\u8F7D\u5931\u8D25"
                    color: "white"; font.pixelSize: 14
                    visible: parent.status === Image.Error
                }
            }
        }

        Component {
            id: animComp
            AnimatedImage {
                source: viewer.imageSource
                fillMode: Image.PreserveAspectFit
                playing: true
                paused: false
                cache: true
                smooth: true
                BusyIndicator {
                    anchors.centerIn: parent
                    running: parent.status === Image.Loading
                    visible: running
                }
                Label {
                    anchors.centerIn: parent
                    text: "\u56FE\u7247\u52A0\u8F7D\u5931\u8D25"
                    color: "white"; font.pixelSize: 14
                    visible: parent.status === Image.Error
                }
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
