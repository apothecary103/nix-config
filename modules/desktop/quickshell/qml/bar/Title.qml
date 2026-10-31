import QtQuick
import QtQuick.Layouts
import ".."

// The focused window's title, fading out rather than cut off when long.
Item {
    id: root

    implicitWidth: label.implicitWidth
    implicitHeight: Theme.pillHeight
    Layout.alignment: Qt.AlignVCenter
    clip: true

    Label {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: Kwm.title || Kwm.appId
        color: Colors.subtle
        font.pixelSize: Theme.smallSize + 1
        opacity: text ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.normal
            }
        }
    }

    Rectangle {
        visible: label.implicitWidth > root.width
        anchors.right: parent.right
        width: 32
        height: parent.height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: "transparent"
            }
            GradientStop {
                position: 1
                color: Colors.base
            }
        }
    }
}
