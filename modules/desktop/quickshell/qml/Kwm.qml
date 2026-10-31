pragma Singleton

import Quickshell
import Quickshell.Io

// kwm's tags and focused window, and the commands it takes, through its IPC
// (river/patches/kwm/0002-ipc.patch).
Singleton {
    id: root

    // [{ id, focused, occupied }] for the ten tags.
    property var tags: []
    property string appId: ""
    property string title: ""

    function send(command) {
        Quickshell.execDetached(["sh", "-c", 'echo "$1" > "$XDG_RUNTIME_DIR/kwm/control"', "sh", command]);
    }

    function focusTag(id) {
        root.send("set_output_tag " + id);
    }

    function toggleTag(id) {
        root.send("toggle_output_tag " + id);
    }

    // The next occupied tag (or the first) in a direction, for scrolling.
    function cycle(step) {
        const focused = root.tags.findIndex(t => t.focused);
        for (let i = 1; i <= root.tags.length; i++) {
            const t = root.tags[(focused + step * i + root.tags.length) % root.tags.length];
            if (t.occupied) {
                root.focusTag(t.id);
                return;
            }
        }
    }

    Process {
        running: true
        command: [Tools.kwmState]
        stdout: SplitParser {
            onRead: line => {
                let state;
                try {
                    state = JSON.parse(line);
                } catch (e) {
                    return;
                }
                root.tags = state.tags || [];
                root.appId = state.app_id || "";
                root.title = state.title || "";
            }
        }
    }
}
