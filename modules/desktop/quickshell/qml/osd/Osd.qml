import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

// Bottom-centre on-screen display for volume, microphone and brightness, in
// place of swayosd. The compositor drives it over IPC; see the IpcHandler below
// for the call names, which the hyprland and niri keybinds use.
Scope {
    id: root

    // "volume" | "micmute" | "brightness"
    property string mode: "volume"
    property bool shown: false

    readonly property int dwellMs: 1400

    function reveal(m) {
        root.mode = m;
        root.shown = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: root.dwellMs
        onTriggered: root.shown = false
    }

    // Audio changes come in through Audio's signal rather than by watching its
    // volume properties — see Audio.qml for why.
    Connections {
        target: Audio
        function onChanged(kind) {
            root.reveal(kind);
        }
    }

    // --- brightness ----------------------------------------------------------
    // brightnessctl is the single source of truth: `-m` prints
    // device,class,current,percent,max for the first backlight, which avoids
    // having to find the device's sysfs path and parse two files out of it.
    property int brightnessPercent: 0

    Process {
        id: brightnessProc
        stdout: StdioCollector {
            onStreamFinished: {
                const percent = parseInt(text.split(",")[3], 10);
                if (!isNaN(percent))
                    root.brightnessPercent = percent;
            }
        }
    }

    function setBrightness(deltaPercent) {
        // brightnessctl prints the new state after setting, so one call both
        // applies the change and refreshes the read-out.
        const arg = deltaPercent > 0 ? deltaPercent + "%+" : -deltaPercent + "%-";
        brightnessProc.command = ["brightnessctl", "-m", "set", arg];
        brightnessProc.running = true;
        root.reveal("brightness");
    }

    // Seed the read-out so the first brightness keypress shows the real level
    // rather than animating up from zero.
    Component.onCompleted: {
        brightnessProc.command = ["brightnessctl", "-m"];
        brightnessProc.running = true;
    }

    // --- IPC -----------------------------------------------------------------
    IpcHandler {
        target: "osd"

        function volumeUp(): void {
            Audio.adjustVolume(Audio.step);
        }
        function volumeDown(): void {
            Audio.adjustVolume(-Audio.step);
        }
        function muteToggle(): void {
            Audio.toggleMute();
        }
        function micMuteToggle(): void {
            Audio.toggleMicMute();
        }
        function brightnessUp(): void {
            root.setBrightness(5);
        }
        function brightnessDown(): void {
            root.setBrightness(-5);
        }
    }

    // --- derived display -----------------------------------------------------
    readonly property bool dimmed: (root.mode === "volume" && Audio.muted) || (root.mode === "micmute" && Audio.micMuted)
    readonly property bool showBar: root.mode !== "micmute"

    readonly property string iconName: {
        if (root.mode === "brightness")
            return "brightness";
        if (root.mode === "micmute")
            return Audio.micMuted ? "mic-muted" : "mic-high";
        if (Audio.muted)
            return "vol-muted";
        if (Audio.volume >= 0.66)
            return "vol-high";
        if (Audio.volume >= 0.33)
            return "vol-medium";
        return "vol-low";
    }

    readonly property int percent: root.mode === "brightness" ? root.brightnessPercent : Math.round(Audio.volume * 100)
    // Clamped for the bar; the label still shows the real percentage.
    readonly property real level: Math.max(0, Math.min(1, root.percent / 100))

    readonly property color accent: {
        if (root.dimmed)
            return Colors.overlay0;
        if (root.mode === "volume" && Audio.volume > 1)
            return Colors.red;
        return Colors.mauve;
    }

    // --- window --------------------------------------------------------------
    PanelWindow {
        visible: root.shown

        // Anchored to the bottom edge only; the compositor centres it there.
        anchors {
            bottom: true
        }
        margins {
            bottom: 52
        }

        implicitWidth: 292
        implicitHeight: 48
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "osd"
        exclusionMode: ExclusionMode.Ignore
        // Fully click-through — never steals focus or blocks the pointer.
        mask: Region {}

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: Colors.mantle

            opacity: root.shown ? 1 : 0
            transform: Translate {
                y: root.shown ? 0 : 12
                Behavior on y {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCirc
                    }
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCirc
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 18
                spacing: 13

                // The icons are Adwaita symbolics, recoloured by MultiEffect to
                // match the rest of the pill. Their fill must stay white:
                // colorization scales colorizationColor by the source's
                // luminance, so a darker fill only ever yields a dim tint.
                Item {
                    Layout.preferredWidth: 19
                    Layout.preferredHeight: 19
                    Layout.alignment: Qt.AlignVCenter

                    Image {
                        id: glyph
                        anchors.fill: parent
                        source: Quickshell.shellDir + "/osd/icons/" + root.iconName + ".svg"
                        sourceSize.width: 40
                        sourceSize.height: 40
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: glyph
                        source: glyph
                        colorization: 1
                        colorizationColor: root.dimmed ? Colors.overlay0 : Colors.text
                    }
                }

                Rectangle {
                    visible: root.showBar
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 7
                    radius: 3.5
                    color: Colors.surface0

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(parent.width * root.level)
                        height: parent.height
                        radius: parent.radius
                        color: root.accent
                        Behavior on width {
                            NumberAnimation {
                                duration: 140
                                easing.type: Easing.OutCirc
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: 160
                            }
                        }
                    }
                }

                Text {
                    visible: root.showBar
                    text: root.percent + "%"
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 42
                    Layout.alignment: Qt.AlignVCenter
                    font.family: Theme.fontMono
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    color: root.dimmed ? Colors.overlay0 : Colors.text
                }

                Text {
                    visible: !root.showBar
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: Audio.micMuted ? "Mic muted" : "Mic on"
                    font.family: Theme.fontMono
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: root.dimmed ? Colors.overlay0 : Colors.text
                }
            }
        }
    }
}
