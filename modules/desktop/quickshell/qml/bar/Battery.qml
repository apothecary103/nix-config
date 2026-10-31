import QtQuick
import Quickshell.Services.UPower
import ".."

// A drawn battery, filled to the charge: love when low, pine while charging.
Pill {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool present: !!root.device && root.device.ready && root.device.isPresent
    readonly property int percent: root.present ? Math.round(root.device.percentage * 100) : 0
    readonly property bool charging: root.present && root.device.state === UPowerDeviceState.Charging
    readonly property bool low: root.present && root.percent < 20 && !root.charging

    visible: root.present

    Item {
        width: 24
        height: 12
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            id: shell
            width: 21
            height: 12
            anchors.verticalCenter: parent.verticalCenter
            radius: 3.5
            color: "transparent"
            border.color: Colors.subtle
            border.width: 1.2
            antialiasing: true

            Rectangle {
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                    margins: 2
                }
                width: Math.max(2, Math.round(17 * root.percent / 100))
                radius: 1.5
                color: root.low ? Colors.love : (root.charging ? Colors.pine : Colors.text)

                Behavior on width {
                    NumberAnimation {
                        duration: Theme.normal
                    }
                }
            }
        }

        Rectangle {
            anchors.left: shell.right
            anchors.leftMargin: 1
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: 5
            radius: 1
            color: Colors.subtle
        }
    }

    Label {
        text: root.percent + "%"
        font.pixelSize: Theme.smallSize + 1
        color: root.low ? Colors.love : Colors.text
    }
}
