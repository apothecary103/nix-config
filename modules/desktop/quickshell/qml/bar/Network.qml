import QtQuick
import Quickshell.Networking
import ".."

// Signal strength, wired winning when both are up, with the old bar's
// activity arrows as a liveness hint.
Pill {
    id: root

    readonly property var status: {
        let wifi = null;
        let wired = null;
        for (const d of Networking.devices.values) {
            if (!d.connected)
                continue;
            if (d.type === DeviceType.Wifi) {
                const net = d.networks.values.find(n => n.connected);
                wifi = { strength: net ? Math.round(net.signalStrength * 100) : 100, name: net ? net.name : "" };
            } else if (d.type === DeviceType.Wired) {
                wired = { strength: 100, name: d.name };
            }
        }
        return wired ? Object.assign({ kind: "wired" }, wired) : (wifi ? Object.assign({ kind: "wifi" }, wifi) : { kind: "none", strength: 0, name: "" });
    }

    Icon {
        text: {
            if (root.status.kind === "wired")
                return "\u{F0200}";
            if (root.status.kind === "none")
                return "\u{F092E}";
            const bars = Math.ceil(root.status.strength / 25);
            return ["\u{F092F}", "\u{F091F}", "\u{F0922}", "\u{F0925}", "\u{F0928}"][Math.max(0, Math.min(4, bars))];
        }
        color: root.status.kind === "none" ? Colors.muted : Colors.text
    }
}
