import QtQuick
import QtQuick.Layouts
import ".."

// A hoverable, pressable bar item: the fill eases in on hover, darkens and
// shrinks a touch on press. Children go in `content`.
Item {
    id: root

    default property alias content: row.data
    property alias spacing: row.spacing
    property bool active: false

    signal clicked(var mouse)
    signal scrolled(var wheel)

    implicitWidth: row.implicitWidth + 16
    implicitHeight: Theme.pillHeight
    Layout.alignment: Qt.AlignVCenter

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: mouse.pressed ? Colors.highlightMed : (mouse.containsMouse || root.active ? Colors.overlay : "transparent")
        scale: mouse.pressed ? 0.96 : 1

        Behavior on color {
            ColorAnimation {
                duration: Theme.fast
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Theme.fast
                easing.type: Easing.OutCubic
            }
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: m => root.clicked(m)
        onWheel: w => root.scrolled(w)
    }
}
