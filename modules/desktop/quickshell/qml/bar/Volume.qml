import QtQuick
import QtQuick.Layouts
import ".."

// Wrapped in an Item so the click target can fill the row without being laid out
// as another row child.
Item {
    id: root

    visible: Audio.sinkAudio !== null
    implicitWidth: contents.implicitWidth
    implicitHeight: contents.implicitHeight
    Layout.alignment: Qt.AlignVCenter

    Row {
        id: contents
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        MonoText {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (Audio.muted)
                    return "\u{F026}";
                if (Audio.volume >= 0.5)
                    return "\u{F028}";
                return "\u{F027}";
            }
            font.pixelSize: 15
            color: Audio.muted ? Colors.overlay0 : Colors.text
        }

        MonoText {
            anchors.verticalCenter: parent.verticalCenter
            text: Audio.muted ? "Mute" : Math.round(Audio.volume * 100) + "%"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: Audio.muted ? Colors.overlay0 : Colors.text
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Audio.toggleMute()
        onWheel: wheel => Audio.adjustVolume(wheel.angleDelta.y > 0 ? Audio.step : -Audio.step)
    }
}
