pragma Singleton

import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // [{ id, idx, active }] sorted by idx, the 1-based position the bar labels
    // workspaces by.
    property var list: []

    function activate(ws) {
        Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(ws.idx)]);
    }

    // Quickshell 0.3.0 ships no niri backend — WindowManager.windowsets is empty
    // — so the workspace list comes from niri's own event stream.
    Process {
        running: true
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser {
            onRead: line => root.handleNiriEvent(line)
        }
    }

    function handleNiriEvent(line) {
        let event;
        try {
            event = JSON.parse(line);
        } catch (e) {
            return;
        }

        if (event.WorkspacesChanged) {
            root.list = event.WorkspacesChanged.workspaces
                .map(w => ({ id: w.id, idx: w.idx, active: !!w.is_active }))
                .sort((a, b) => a.idx - b.idx);
        } else if (event.WorkspaceActivated && event.WorkspaceActivated.focused) {
            const activeId = event.WorkspaceActivated.id;
            // Reassigned rather than mutated so the bindings on `list` recompute.
            root.list = root.list.map(w => ({ id: w.id, idx: w.idx, active: w.id === activeId }));
        }
    }
}
