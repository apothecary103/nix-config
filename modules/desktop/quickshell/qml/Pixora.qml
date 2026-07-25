pragma Singleton

import Quickshell
import Quickshell.Io

// Which icons the Pixora theme actually ships, listed once at startup.
//
// AppIcon checks here before pointing an Image at a Pixora path. Letting the
// Image fail and fall back instead looks simpler but is not: every app whose
// icon Pixora lacks then logs a failed load, once per delegate that shows it.
//
// Pixora is installed by hand into ~/.local/share/icons rather than by nix, so
// the set has to be discovered at runtime.
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
