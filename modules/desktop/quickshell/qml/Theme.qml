pragma Singleton

import Quickshell

// Non-colour design tokens. Colours live in Colors.qml, which nix generates
// from modules/desktop/theme.nix.
Singleton {
    readonly property string fontMono: "Maple Mono NF CN"

    readonly property int radius: 7

    // Bar geometry, shared so the notification stack and the OSD can place
    // themselves relative to the bar instead of hand-summing its numbers.
    readonly property int barHeight: 38
    readonly property int barMargin: 10
}
