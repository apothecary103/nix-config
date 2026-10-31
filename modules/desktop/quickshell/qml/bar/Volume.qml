import QtQuick
import ".."

Pill {
    visible: Audio.sinkAudio !== null
    onClicked: Audio.toggleMute()
    onScrolled: w => Audio.adjustVolume(w.angleDelta.y > 0 ? Audio.step : -Audio.step)

    Icon {
        text: Audio.muted ? "\u{F0581}" : (Audio.volume >= 0.5 ? "\u{F057E}" : (Audio.volume > 0 ? "\u{F0580}" : "\u{F057F}"))
        color: Audio.muted ? Colors.muted : Colors.text
    }

    Label {
        text: Math.round(Audio.volume * 100) + "%"
        color: Audio.muted ? Colors.muted : Colors.text
        font.pixelSize: Theme.smallSize + 1
    }
}
