import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

// A menubar flush with the top edge and exactly as tall as the notch, so the
// notch disappears into it. Content keeps to two halves; the middle, where
// the notch is, stays empty (Island draws over it).
PanelWindow {
    id: root

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: Theme.barHeight
    color: Colors.base
    WlrLayershell.namespace: "bar"

    // The room on either side of the notch, less a margin from it.
    readonly property real half: (root.width - Theme.notchWidth) / 2 - Theme.edge * 2

    IpcHandler {
        target: "bar"

        function toggle(): void {
            root.visible = !root.visible;
        }
    }

    RowLayout {
        id: left

        anchors.left: parent.left
        anchors.leftMargin: Theme.edge
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.half)
        spacing: 10
        clip: true

        Avatar {}

        Workspaces {}

        Title {
            Layout.fillWidth: true
            Layout.maximumWidth: 260
        }
    }

    RowLayout {
        id: right

        anchors.right: parent.right
        anchors.rightMargin: Theme.edge - 6
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.half)
        spacing: 2
        clip: true

        NowPlaying {}

        Tray {}

        Network {}

        Volume {}

        Battery {}

        Clock {}
    }

    // A hairline where the bar meets the windows.
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Colors.highlightMed
        opacity: 0.6
    }
}
