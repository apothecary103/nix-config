pragma Singleton

import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    readonly property var sinkAudio: root.sink ? root.sink.audio : null
    readonly property var sourceAudio: root.source ? root.source.audio : null

    readonly property real volume: root.sinkAudio ? root.sinkAudio.volume : 0
    readonly property bool muted: root.sinkAudio ? root.sinkAudio.muted : false
    readonly property bool micMuted: root.sourceAudio ? root.sourceAudio.muted : false

    // `max` allows the usual 150% overdrive.
    readonly property real step: 0.05
    readonly property real max: 1.5

    // Emitted only for changes made through the functions below. Watching the
    // volume properties instead would also fire for the values that settle
    // during startup. The trade is that a bare `wpctl set-volume` from outside
    // the shell does not raise the OSD.
    signal changed(string kind)

    function adjustVolume(delta) {
        const a = root.sinkAudio;
        if (!a)
            return;
        // Nudging the volume up is the usual way to undo an accidental mute.
        if (a.muted && delta > 0)
            a.muted = false;
        a.volume = Math.max(0, Math.min(root.max, a.volume + delta));
        root.changed("volume");
    }

    function toggleMute() {
        if (root.sinkAudio)
            root.sinkAudio.muted = !root.sinkAudio.muted;
        root.changed("volume");
    }

    function toggleMicMute() {
        if (root.sourceAudio)
            root.sourceAudio.muted = !root.sourceAudio.muted;
        root.changed("micmute");
    }

    PwObjectTracker {
        objects: {
            const list = [];
            if (root.sink)
                list.push(root.sink);
            if (root.source)
                list.push(root.source);
            return list;
        }
    }
}
