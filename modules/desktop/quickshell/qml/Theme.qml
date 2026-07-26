pragma Singleton

import Quickshell

Singleton {
    readonly property string fontMono: "Maple Mono NF CN"

    readonly property int radius: 7

    // Shared so the notification stack and the OSD can place themselves
    // relative to the bar instead of hand-summing its numbers.
    readonly property int barHeight: 38
    readonly property int barMargin: 10
}
