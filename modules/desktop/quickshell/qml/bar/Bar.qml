import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import ".."

// The top bar: two pills anchored to the screen edges, with the widgets in
// bar/ doing the actual work.
//
// Each pill is its own layer surface rather than both living in one full-width
// surface. niri's background-effect blurs the whole area a surface covers and has
// no alpha threshold to exempt the see-through parts (unlike Hyprland's
// blur:ignore_alpha), so a single wide surface blurred the empty gap between the
// pills as well. Sizing each surface to its pill keeps the blur under the pills
// where it belongs, and leaves the gap genuinely transparent — clicks there now
// reach whatever is underneath too.
Scope {
    id: root

    // Neither pill can reserve the top edge itself. wlr-layer-shell only honours
    // an exclusive zone on a surface anchored to one edge, or to an edge plus
    // both edges perpendicular to it; a surface anchored to two *adjacent*
    // edges is a corner, and the protocol says its exclusive zone "will be
    // treated the same as zero". Both pills are corners (top+left, top+right),
    // so quickshell's Auto mode resolves no exclusion edge and sends a zone of
    // 0 — which is why `hyprctl monitors` reported reserved [0,0,0,0] and
    // windows tiled underneath the bar.
    //
    // This invisible full-width surface does the reserving instead. It is
    // anchored top+left+right, the one shape the protocol accepts, and it is
    // transparent with an empty click mask so it neither draws nor swallows
    // input. Its namespace deliberately differs from the pills' so niri's
    // `^bar$` blur rule keeps skipping it.
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

        // Named so compositor layer rules can target the bar alone rather than
        // every quickshell surface (see niri.nix's layer-rules).
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
