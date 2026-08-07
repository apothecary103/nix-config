import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

MonoText {
    id: root

    // Wakes 60x less often than a per-second timer, for a read-out that never
    // shows seconds.
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
    color: Colors.text
    font.pixelSize: 12
    font.weight: Font.DemiBold
    font.letterSpacing: 0.4
    Layout.alignment: Qt.AlignVCenter
}
