import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import ".."

Row {
    id: root

    // The aggregate display device, so no machine-specific sysfs path and no
    // polling. Requires services.upower.enable (quickshell.nix).
    readonly property var device: UPower.displayDevice
    readonly property bool present: !!root.device && root.device.ready && root.device.isPresent
    // UPower's D-Bus property is 0-100 but Quickshell normalises it to 0-1.
    readonly property int percent: root.present ? Math.round(root.device.percentage * 100) : 0
    readonly property bool charging: root.present && root.device.state === UPowerDeviceState.Charging
    readonly property bool low: root.present && root.percent < 20 && !root.charging

    visible: root.present
    spacing: 6
    Layout.alignment: Qt.AlignVCenter

    Item {
        implicitWidth: 23
        implicitHeight: 12
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            id: shell
            width: 20
            height: 12
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            radius: 3
            color: "transparent"
            border.color: Colors.subtext0
            border.width: 1
            antialiasing: true

            Rectangle {
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                    margins: 2
                }
                // A 2px floor keeps the fill visible at very low charge.
                width: Math.max(2, Math.round(16 * (root.percent / 100)))
                radius: 1
                color: root.low ? Colors.red : (root.charging ? Colors.green : Colors.text)
            }

            MonoText {
                visible: root.charging
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -0.5
                text: "\u{F140B}" // charging bolt
                font.pixelSize: 9
                color: Colors.mantle
            }
        }

        Rectangle {
            anchors.left: shell.right
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: 6
            radius: 1.5
            color: Colors.subtext0
            antialiasing: true
        }
    }

    MonoText {
        anchors.verticalCenter: parent.verticalCenter
        text: root.percent + "%"
        color: Colors.text
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }
}
