pragma Singleton

import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/share/icons/pixora/scalable/apps"

    property var names: ({})

    function has(name) {
        return root.names[name] === true;
    }

    function pathFor(name) {
        return "file://" + root.dir + "/" + name + ".svg";
    }

    // Pixora is installed by hand rather than by nix, so the set has to be
    // discovered at runtime. AppIcon gates on has() rather than letting the
    // Image fail over, which would log a failed load per delegate.
    Process {
        running: true
        command: ["sh", "-c", "ls " + root.dir + " 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = {};
                for (const line of text.split("\n")) {
                    const file = line.trim();
                    if (file.endsWith(".svg"))
                        found[file.slice(0, -4)] = true;
                }
                root.names = found;
            }
        }
    }
}
