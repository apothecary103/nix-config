import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."

ClippingRectangle {
    implicitWidth: 22
    implicitHeight: 22
    radius: 11
    color: Colors.overlay
    antialiasing: true
    Layout.alignment: Qt.AlignVCenter

    Image {
        anchors.fill: parent
        source: Quickshell.shellDir + "/avatar.jpg"
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 64
        sourceSize.height: 64
    }
}
