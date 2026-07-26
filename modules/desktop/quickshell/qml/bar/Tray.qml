import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import ".."

Row {
    id: root

    property bool expanded: false

    visible: SystemTray.items.values.length > 0
    spacing: 6
    Layout.alignment: Qt.AlignVCenter

    Item {
        implicitWidth: 16
        implicitHeight: 16
        anchors.verticalCenter: parent.verticalCenter

        Text {
            anchors.centerIn: parent
            text: "\u{F0141}" // chevron left
            font.family: Theme.fontMono
            font.pixelSize: 16
            color: root.expanded ? Colors.text : Colors.subtext0
            rotation: root.expanded ? 180 : 0

            Behavior on rotation {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutBack
                }
            }
            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }
    }

    Item {
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: 16
        clip: true

        width: root.expanded ? icons.implicitWidth : 0
        Behavior on width {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCirc
            }
        }

        Row {
            id: icons
            spacing: 8
            height: parent.height

            Repeater {
                model: SystemTray.items.values

                Item {
                    id: item
                    required property var modelData

                    implicitWidth: 16
                    implicitHeight: 16
                    anchors.verticalCenter: parent.verticalCenter

                    IconImage {
                        anchors.fill: parent
                        source: item.modelData.icon
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -2
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton)
                                item.modelData.activate();
                            else
                                item.modelData.secondaryActivate();
                        }
                    }
                }
            }
        }
    }
}
