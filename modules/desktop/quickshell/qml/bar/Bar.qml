import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import ".."

Scope {
    id: root

    // Neither pill can reserve the top edge itself: wlr-layer-shell treats the
    // exclusive zone of a surface anchored to two *adjacent* edges (a corner,
    // which both pills are) as zero. This invisible surface is anchored
    // top+left+right — a shape the protocol accepts — and reserves the edge for
    // all three. Its namespace differs from the pills' so the compositors'
    // `^bar$` blur rules skip it.
    PanelWindow {
        id: strut

        anchors {
            top: true
            left: true
            right: true
        }

        margins {
            top: Theme.barMargin
        }

        implicitHeight: Theme.barHeight
        color: "transparent"

        WlrLayershell.namespace: "bar-strut"

        mask: Region {}
    }

    PanelWindow {
        id: leftBar

        anchors {
            top: true
            left: true
        }

        exclusionMode: ExclusionMode.Ignore

        margins {
            top: Theme.barMargin
            left: Theme.barMargin
        }

        implicitWidth: left.implicitWidth + 18
        implicitHeight: Theme.barHeight
        color: "transparent"

        // Each pill is its own surface because niri's background-effect blurs
        // everything a surface covers with no alpha threshold: one full-width
        // surface blurred the gap between the pills and swallowed clicks there.
        WlrLayershell.namespace: "bar"

        Rectangle {
            anchors.fill: parent
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
    }

    PanelWindow {
        id: rightBar

        anchors {
            top: true
            right: true
        }

        margins {
            top: Theme.barMargin
            right: Theme.barMargin
        }

        implicitWidth: right.implicitWidth + 18
        implicitHeight: Theme.barHeight
        color: "transparent"

        WlrLayershell.namespace: "bar"

        exclusionMode: ExclusionMode.Ignore

        Rectangle {
            anchors.fill: parent
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
}
