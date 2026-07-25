import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.Mpris
import ".."

// Cover art, title, artist and a play/pause toggle for the active MPRIS player.
// Hidden entirely when nothing is playing.
Row {
    id: root

    // Prefer a player that is actually playing; otherwise the most recent one
    // that is merely paused with a track loaded.
    readonly property var player: {
        const loaded = Mpris.players.values.filter(p => p.playbackState !== MprisPlaybackState.Stopped && p.trackTitle);
        if (loaded.length === 0)
            return null;
        return loaded.find(p => p.isPlaying) || loaded[0];
    }

    visible: root.player !== null
    spacing: 8
    Layout.alignment: Qt.AlignVCenter

    ClippingRectangle {
        width: 20
        height: 20
        radius: 6
        color: Colors.surface0
        antialiasing: true
        anchors.verticalCenter: parent.verticalCenter

        Image {
            anchors.fill: parent
            source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        Text {
            visible: !root.player || !root.player.trackArtUrl
            anchors.centerIn: parent
            text: "\u{F001}" // music note
            font.family: Theme.fontMono
            font.pixelSize: 11
            color: Colors.overlay0
        }
    }

    Row {
        spacing: 6
        anchors.verticalCenter: parent.verticalCenter

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.player ? (root.player.trackTitle || "Unknown") : ""
            font.family: Theme.fontMono
            font.weight: Font.DemiBold
            font.pixelSize: 12
            color: Colors.text
            elide: Text.ElideRight
            width: Math.min(implicitWidth, 130)
        }

        Text {
            visible: root.player && !!root.player.trackArtist
            anchors.verticalCenter: parent.verticalCenter
            text: "·"
            font.family: Theme.fontMono
            font.pixelSize: 12
            color: Colors.overlay0
        }

        Text {
            visible: root.player && !!root.player.trackArtist
            anchors.verticalCenter: parent.verticalCenter
            text: root.player ? root.player.trackArtist : ""
            font.family: Theme.fontMono
            font.pixelSize: 11
            font.italic: true
            font.weight: Font.Medium
            color: Colors.subtext0
            elide: Text.ElideRight
            width: Math.min(implicitWidth, 90)
        }
    }

    Item {
        width: 16
        height: 16
        anchors.verticalCenter: parent.verticalCenter

        Text {
            anchors.centerIn: parent
            text: root.player && root.player.isPlaying ? "\u{F04C}" : "\u{F04B}" // pause / play
            font.family: Theme.fontMono
            font.pixelSize: 13
            color: Colors.blue
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.player) root.player.togglePlaying()
        }
    }
}
