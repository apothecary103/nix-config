pragma Singleton

import Quickshell
import Quickshell.Services.Mpris

// The player worth showing: one that is playing, else the most recent paused.
Singleton {
    readonly property var current: {
        const loaded = Mpris.players.values.filter(p => p.playbackState !== MprisPlaybackState.Stopped && p.trackTitle);
        if (loaded.length === 0)
            return null;
        return loaded.find(p => p.isPlaying) || loaded[0];
    }
}
