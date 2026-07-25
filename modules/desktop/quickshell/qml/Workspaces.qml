pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Workspaces for whichever compositor is running. greetd launches niri by
// default and Hyprland as the alternate session (see modules/desktop/greetd.nix),
// so the bar cannot bind to Quickshell.Hyprland directly. Quickshell 0.3.0 ships
// no niri backend — WindowManager.windowsets is empty — hence the event-stream
// reader below.
//
// `list` is [{ id, idx, active }] sorted by idx, where idx is the 1-based
// position the bar labels workspaces by.
Singleton {
    id: root

    readonly property bool underHyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    readonly property bool underNiri: !!Quickshell.env("NIRI_SOCKET")

    readonly property var list: root.underNiri ? root.niriList : root.hyprlandList

    function activate(ws) {
        if (root.underNiri) {
            Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(ws.idx)]);
        } else if (root.underHyprland) {
            // This Hyprland evaluates dispatch payloads as Lua, so the classic
            // `dispatch workspace N` string is a syntax error rather than a
            // workspace switch. Same hl.dsp API the keybinds in hyprland.nix use.
            Hyprland.dispatch('hl.dsp.focus({ workspace = "' + ws.id + '" })');
        }
    }

    // --- hyprland ------------------------------------------------------------
    // Hyprland ids are global and 1-based, so they double as the label position.
    readonly property var hyprlandList: {
        if (!root.underHyprland)
            return [];
        const focused = Hyprland.focusedWorkspace;
        return Hyprland.workspaces.values
            .map(w => ({ id: w.id, idx: w.id, active: !!focused && focused.id === w.id }))
            .sort((a, b) => a.idx - b.idx);
    }

    // --- niri ----------------------------------------------------------------
    property var niriList: []

    Process {
        running: root.underNiri
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
            root.niriList = event.WorkspacesChanged.workspaces
                .map(w => ({ id: w.id, idx: w.idx, active: !!w.is_active }))
                .sort((a, b) => a.idx - b.idx);
        } else if (event.WorkspaceActivated && event.WorkspaceActivated.focused) {
            const activeId = event.WorkspaceActivated.id;
            // Reassigned rather than mutated so the bindings on `list` recompute.
            root.niriList = root.niriList.map(w => ({ id: w.id, idx: w.idx, active: w.id === activeId }));
        }
    }
}
