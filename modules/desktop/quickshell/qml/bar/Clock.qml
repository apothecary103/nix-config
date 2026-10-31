import QtQuick
import Quickshell
import ".."

Pill {
    spacing: 8

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Label {
        text: Qt.formatDateTime(clock.date, "ddd d MMM")
        color: Colors.subtle
        font.pixelSize: Theme.smallSize + 1
    }

    Label {
        text: Qt.formatDateTime(clock.date, "HH:mm")
        font.family: Theme.fontBold
    }
}
