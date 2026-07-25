import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import ".."

// The top bar: two pills anchored to the screen edges, with the widgets in
// bar/ doing the actual work.
PanelWindow {
    id: root

    anchors {
        top: true
        left: true
        right: true
    }

    margins {
        top: Theme.barMargin
        left: Theme.barMargin
        right: Theme.barMargin
    }

    implicitHeight: Theme.barHeight
    color: "transparent"

    // Named so compositor layer rules can target the bar alone rather than
    // every quickshell surface (see niri.nix's layer-rules).
    WlrLayershell.namespace: "bar"

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: left.implicitWidth + 18
        color: Colors.mantle
        radius: Theme.radius

        RowLayout {
            id: left
            anchors.fill: parent
            anchors.margins: 9
            spacing: 10

            ClippingRectangle {
                width: 20
                height: 20
                radius: 10
                color: Colors.surface0
                antialiasing: true
                Layout.alignment: Qt.AlignVCenter

                Image {
                    anchors.fill: parent
                    source: Quickshell.shellDir + "/avatar.jpg"
                    fillMode: Image.PreserveAspectCrop
                }
            }

            WorkspaceRow {}

            Separator {
                visible: nowPlaying.visible
            }

            NowPlaying {
                id: nowPlaying
            }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: right.implicitWidth + 18
        color: Colors.mantle
        radius: Theme.radius

        RowLayout {
            id: right
            anchors.fill: parent
            anchors.margins: 9
            spacing: 12

            Tray {
                id: tray
            }

            Separator {
                visible: tray.visible
            }

            NetworkStatus {}

            Volume {}

            Battery {}

            Separator {}

            Clock {}
        }
    }
}
