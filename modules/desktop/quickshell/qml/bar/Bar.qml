import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import ".."

Scope {
    id: root

    // Neither pill can reserve the top edge itself. wlr-layer-shell only honours
    // an exclusive zone on a surface anchored to one edge, or to an edge plus
    // both edges perpendicular to it; a surface anchored to two *adjacent* edges
    // is a corner, and the protocol says its exclusive zone "will be treated the
    // same as zero". Both pills are corners (top+left, top+right), so
    // quickshell's Auto mode resolves no exclusion edge and sends a zone of 0 —
    // which is why `hyprctl monitors` reported reserved [0,0,0,0] and windows
    // tiled underneath the bar.
    //
    // This invisible full-width surface does the reserving instead, anchored
    // top+left+right — the one shape the protocol accepts — and transparent with
    // an empty click mask so it neither draws nor swallows input. Its namespace
    // deliberately differs from the pills' so the compositors' `^bar$` blur
    // rules keep skipping it.
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

        // The strut above reserves the edge for all three surfaces.
        exclusionMode: ExclusionMode.Ignore

        margins {
            top: Theme.barMargin
            left: Theme.barMargin
        }

        implicitWidth: left.implicitWidth + 18
        implicitHeight: Theme.barHeight
        color: "transparent"

        // Each pill is its own surface, sized to itself, because niri's
        // background-effect blurs everything a surface covers with no alpha
        // threshold to exempt the see-through parts: one full-width surface
        // blurred the gap between the pills too, and swallowed clicks there.
        // Named so the compositors' layer rules can target the bar alone.
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
