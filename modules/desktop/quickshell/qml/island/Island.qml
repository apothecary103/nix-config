pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import ".."

// A black shape under the notch that grows down out of it, with concave ears
// where it meets the bar: the volume and brightness overlay, and the track
// for a few seconds when it changes. Idle, it is exactly the notch and so
// invisible. Everything it shows sits below the notch's 32 pt.
PanelWindow {
    id: root

    anchors.top: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "island"
    implicitWidth: 460
    implicitHeight: 120
    color: "transparent"
    mask: Region {
        item: shape
    }

    // "", "osd" or "track".
    property string mode: ""
    property string osdKind: "volume"
    property int osdValue: 0
    property string osdLabel: ""

    readonly property int bodyWidth: ({ osd: 300, track: 380 })[root.mode] || Theme.notchWidth
    readonly property int bodyHeight: ({ osd: Theme.notchHeight + 44, track: Theme.notchHeight + 58 })[root.mode] || Theme.notchHeight
    readonly property int ear: root.mode ? 12 : 0
    readonly property int corner: root.mode ? 22 : 10

    property real w: root.bodyWidth
    property real h: root.bodyHeight
    property real e: root.ear
    property real r: root.corner

    Behavior on w {
        NumberAnimation {
            duration: Theme.slow
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.spring
        }
    }
    Behavior on h {
        NumberAnimation {
            duration: Theme.slow
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.spring
        }
    }
    Behavior on e {
        NumberAnimation {
            duration: Theme.normal
        }
    }
    Behavior on r {
        NumberAnimation {
            duration: Theme.normal
        }
    }

    function show(mode, hold) {
        root.mode = mode;
        collapse.interval = hold;
        collapse.restart();
    }

    Timer {
        id: collapse
        onTriggered: root.mode = ""
    }

    IpcHandler {
        target: "island"

        // From the media keys (see osd.nix): kind is volume, brightness or
        // microphone; label is shown as given.
        function osd(kind: string, value: int, label: string): void {
            root.osdKind = kind;
            root.osdValue = value;
            root.osdLabel = label;
            root.show("osd", 1500);
        }
    }

    // A changed track, but not the player settling at login.
    property bool settled: false
    Timer {
        running: true
        interval: 3000
        onTriggered: root.settled = true
    }
    Connections {
        target: Players.current
        ignoreUnknownSignals: true

        function onTrackTitleChanged() {
            if (root.settled && Players.current && Players.current.trackTitle && root.mode !== "osd")
                root.show("track", 3500);
        }
    }

    Shape {
        id: shape

        x: (root.width - width) / 2
        width: root.w + root.e * 2
        height: root.h
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "black"
            strokeWidth: 0
            strokeColor: "transparent"

            startX: 0
            startY: 0
            PathLine {
                x: shape.width
                y: 0
            }
            PathArc {
                x: shape.width - root.e
                y: root.e
                radiusX: root.e
                radiusY: root.e
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: shape.width - root.e
                y: shape.height - root.r
            }
            PathArc {
                x: shape.width - root.e - root.r
                y: shape.height
                radiusX: root.r
                radiusY: root.r
            }
            PathLine {
                x: root.e + root.r
                y: shape.height
            }
            PathArc {
                x: root.e
                y: shape.height - root.r
                radiusX: root.r
                radiusY: root.r
            }
            PathLine {
                x: root.e
                y: root.e
            }
            PathArc {
                x: 0
                y: 0
                radiusX: root.e
                radiusY: root.e
                direction: PathArc.Counterclockwise
            }
        }

        // The overlay: an icon, a level and the value.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.notchHeight + (root.h - Theme.notchHeight - height) / 2
            spacing: 12
            opacity: root.mode === "osd" ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.fast
                }
            }

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                color: "white"
                text: {
                    if (root.osdKind === "brightness")
                        return "\u{F00E0}";
                    if (root.osdKind === "microphone")
                        return root.osdLabel.includes("muted") ? "\u{F036D}" : "\u{F036C}";
                    if (root.osdLabel === "muted")
                        return "\u{F0581}";
                    return root.osdValue >= 50 ? "\u{F057E}" : "\u{F0580}";
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 190
                height: 6
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.18)

                Rectangle {
                    width: parent.width * Math.min(1, root.osdValue / 100)
                    height: parent.height
                    radius: 3
                    color: root.osdLabel.includes("muted") ? Qt.rgba(1, 1, 1, 0.35) : Colors.accent

                    Behavior on width {
                        NumberAnimation {
                            duration: 120
                        }
                    }
                }
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                text: root.osdValue
                color: "white"
                horizontalAlignment: Text.AlignRight
                font.pixelSize: Theme.smallSize + 1
            }
        }

        // The new track: cover, title and artist.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.notchHeight + (root.h - Theme.notchHeight - height) / 2
            spacing: 12
            opacity: root.mode === "track" ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.fast
                }
            }

            ClippingRectangle {
                width: 38
                height: 38
                radius: 8
                color: Qt.rgba(1, 1, 1, 0.1)

                Image {
                    anchors.fill: parent
                    source: Players.current && Players.current.trackArtUrl ? Players.current.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 96
                    sourceSize.height: 96
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Label {
                    text: Players.current ? Players.current.trackTitle : ""
                    color: "white"
                    font.family: Theme.fontBold
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 280)
                }
                Label {
                    text: Players.current ? Players.current.trackArtist : ""
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.pixelSize: Theme.smallSize
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 280)
                }
            }
        }
    }
}
