import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ImAgentHub

// 音频设备选择器组件
// 用法：
//   AudioDevicePicker {
//       inputIdx:  root._inputIdx
//       outputIdx: root._outputIdx
//       onInputActivated:  (idx, devId) => { root._inputIdx  = idx; ... }
//       onOutputActivated: (idx, devId) => { root._outputIdx = idx; ... }
//   }
ColumnLayout {
    id: root

    property int inputIdx:  0   // 当前麦克风索引（0 = 系统默认）
    property int outputIdx: 0   // 当前扬声器索引（0 = 系统默认）

    // idx=0 → devId="" (系统默认); idx>0 → 真实设备 ID
    signal inputActivated(int idx, string devId)
    signal outputActivated(int idx, string devId)

    spacing: 4

    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: "#2d2d4a"
    }

    Item { height: 4 }

    // ── 麦克风 ────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Label {
            text: "麦克风"
            font.pixelSize: 11
            color: "#6b7280"
            Layout.preferredWidth: 40
        }

        ComboBox {
            id: inputCombo
            Layout.fillWidth: true
            model: ["系统默认"].concat(AudioCallEngine.inputDevices)
            currentIndex: root.inputIdx
            font.pixelSize: 11
            height: 28

            onActivated: (idx) => root.inputActivated(idx, idx === 0 ? "" : AudioCallEngine.inputDeviceId(idx - 1))

            background: Rectangle {
                color: "#1e1e36"; radius: 5
                border.color: "#3d3d5c"; border.width: 1
            }
            contentItem: Text {
                leftPadding: 8
                rightPadding: inputCombo.indicator.width + 4
                text: inputCombo.displayText
                color: "#d1d5db"
                font: inputCombo.font
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            indicator: Canvas {
                x: inputCombo.width - width - 6
                y: (inputCombo.height - height) / 2
                width: 10; height: 6
                contextType: "2d"
                onPaint: {
                    context.reset()
                    context.moveTo(0, 0); context.lineTo(width, 0)
                    context.lineTo(width / 2, height); context.closePath()
                    context.fillStyle = "#6b7280"; context.fill()
                }
            }
            popup: Popup {
                y: inputCombo.height + 2
                width: inputCombo.width
                padding: 1
                background: Rectangle {
                    color: "#1e1e36"; border.color: "#3d3d5c"
                    border.width: 1; radius: 5
                }
                contentItem: ListView {
                    clip: true
                    implicitHeight: Math.min(contentHeight, 200)
                    model: inputCombo.delegateModel
                    ScrollIndicator.vertical: ScrollIndicator {}
                }
            }
            delegate: ItemDelegate {
                width: parent ? parent.width : 0
                height: 28
                highlighted: inputCombo.highlightedIndex === index
                background: Rectangle { color: highlighted ? "#2d2d4a" : "transparent" }
                contentItem: Text {
                    leftPadding: 8; text: modelData
                    color: "#d1d5db"; font.pixelSize: 11
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    Item { height: 4 }

    // ── 扬声器 ────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Label {
            text: "扬声器"
            font.pixelSize: 11
            color: "#6b7280"
            Layout.preferredWidth: 40
        }

        ComboBox {
            id: outputCombo
            Layout.fillWidth: true
            model: ["系统默认"].concat(AudioCallEngine.outputDevices)
            currentIndex: root.outputIdx
            font.pixelSize: 11
            height: 28

            onActivated: (idx) => root.outputActivated(idx, idx === 0 ? "" : AudioCallEngine.outputDeviceId(idx - 1))

            background: Rectangle {
                color: "#1e1e36"; radius: 5
                border.color: "#3d3d5c"; border.width: 1
            }
            contentItem: Text {
                leftPadding: 8
                rightPadding: outputCombo.indicator.width + 4
                text: outputCombo.displayText
                color: "#d1d5db"
                font: outputCombo.font
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            indicator: Canvas {
                x: outputCombo.width - width - 6
                y: (outputCombo.height - height) / 2
                width: 10; height: 6
                contextType: "2d"
                onPaint: {
                    context.reset()
                    context.moveTo(0, 0); context.lineTo(width, 0)
                    context.lineTo(width / 2, height); context.closePath()
                    context.fillStyle = "#6b7280"; context.fill()
                }
            }
            popup: Popup {
                y: outputCombo.height + 2
                width: outputCombo.width
                padding: 1
                background: Rectangle {
                    color: "#1e1e36"; border.color: "#3d3d5c"
                    border.width: 1; radius: 5
                }
                contentItem: ListView {
                    clip: true
                    implicitHeight: Math.min(contentHeight, 200)
                    model: outputCombo.delegateModel
                    ScrollIndicator.vertical: ScrollIndicator {}
                }
            }
            delegate: ItemDelegate {
                width: parent ? parent.width : 0
                height: 28
                highlighted: outputCombo.highlightedIndex === index
                background: Rectangle { color: highlighted ? "#2d2d4a" : "transparent" }
                contentItem: Text {
                    leftPadding: 8; text: modelData
                    color: "#d1d5db"; font.pixelSize: 11
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    Item { height: 4 }

    // ── 回声消除 ──────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Label {
            text: "回声"
            font.pixelSize: 11
            color: "#6b7280"
            Layout.preferredWidth: 40
        }

        CheckBox {
            id: aecCheck
            Layout.fillWidth: true
            text: "启用回声消除 (扬声器模式)"
            checked: AudioCallEngine.aecEnabled
            font.pixelSize: 11
            onToggled: AudioCallEngine.setAecEnabled(checked)

            indicator: Rectangle {
                x: 0
                y: (aecCheck.height - height) / 2
                width: 16; height: 16; radius: 3
                color: aecCheck.checked ? "#6366f1" : "#1e1e36"
                border.color: aecCheck.checked ? "#6366f1" : "#3d3d5c"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "✓"; color: "white"
                    font.pixelSize: 10
                    visible: aecCheck.checked
                }
            }
            contentItem: Text {
                leftPadding: aecCheck.indicator.width + 6
                text: aecCheck.text
                color: "#9ca3af"
                font: aecCheck.font
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
