import QtQuick
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import ".."

// Tucked behind a chevron, as on the old bar, sliding open on click.
Pill {
    id: root

    property bool expanded: false

    visible: SystemTray.items.values.length > 0
    active: root.expanded
    onClicked: root.expanded = !root.expanded

    Item {
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: 16
        clip: true
        width: root.expanded ? icons.implicitWidth : 0

        Behavior on width {
            NumberAnimation {
                duration: Theme.normal
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.emphasizedDecel
            }
        }

        Row {
            id: icons
            spacing: 8
            height: parent.height

            Repeater {
                model: SystemTray.items.values

                IconImage {
                    id: item
                    required property var modelData

                    implicitSize: 16
                    source: item.modelData.icon

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -2
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: m => m.button === Qt.LeftButton ? item.modelData.activate() : item.modelData.secondaryActivate()
                    }
                }
            }
        }
    }

    Icon {
        text: "\u{F0141}"
        color: root.expanded ? Colors.text : Colors.subtle
        rotation: root.expanded ? 180 : 0

        Behavior on rotation {
            NumberAnimation {
                duration: Theme.normal
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springFast
            }
        }
    }
}
