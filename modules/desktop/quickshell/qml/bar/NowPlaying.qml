import QtQuick
import Quickshell.Widgets
import Quickshell.Services.Mpris
import ".."

// The playing track: cover, title and artist. Click plays or pauses, scroll
// skips.
Pill {
    id: root

    readonly property var player: Players.current

    visible: root.player !== null
    spacing: 8
    onClicked: m => m.button === Qt.RightButton ? root.player.next() : root.player.togglePlaying()
    onScrolled: w => w.angleDelta.y > 0 ? root.player.previous() : root.player.next()

    ClippingRectangle {
        width: 17
        height: 17
        radius: 4
        color: Colors.overlay
        anchors.verticalCenter: parent.verticalCenter

        Image {
            anchors.fill: parent
            source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 64
            sourceSize.height: 64
        }
    }

    Label {
        text: root.player ? (root.player.trackTitle || "Unknown") : ""
        font.pixelSize: Theme.smallSize + 1
        elide: Text.ElideRight
        width: Math.min(implicitWidth, 150)
    }

    Label {
        visible: root.player && !!root.player.trackArtist
        text: root.player ? root.player.trackArtist : ""
        color: Colors.subtle
        font.pixelSize: Theme.smallSize
        elide: Text.ElideRight
        width: Math.min(implicitWidth, 100)
    }

    Icon {
        text: root.player && root.player.isPlaying ? "\u{F03E4}" : "\u{F040A}"
        color: Colors.accent
        font.pixelSize: Theme.iconSize - 1
    }
}
