pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property string font: "azuki_font"
    readonly property string fontBold: "azukifontB"
    readonly property string icons: "Symbols Nerd Font"

    // The macOS menu bar's 33 pt, just clearing the notch (NSScreen
    // safeAreaInsets top = 32 pt), so the bar swallows it.
    readonly property int barHeight: 33
    readonly property int notchWidth: 200
    readonly property int notchHeight: 32
    readonly property int edge: 14
    readonly property int pillHeight: 23
    readonly property int radius: 9

    readonly property int textSize: 15
    readonly property int smallSize: 13
    readonly property int iconSize: 15

    // One set of motion tokens, after end-4's Material 3 curves; `scale`
    // speeds or slows everything at once.
    readonly property real scale: 1
    readonly property int fast: 150 * scale
    readonly property int normal: 250 * scale
    readonly property int slow: 450 * scale
    readonly property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property list<real> emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
    readonly property list<real> spring: [0.38, 1.21, 0.22, 1, 1, 1]
    readonly property list<real> springFast: [0.42, 1.67, 0.21, 0.9, 1, 1]
}
