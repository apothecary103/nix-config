import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Networking
import ".."

Row {
    id: root

    // Wired wins when both are up, since it is the one carrying traffic.
    readonly property var status: {
        let wifi = null;
        let wired = null;
        for (const d of Networking.devices.values) {
            if (!d.connected)
                continue;
            if (d.type === DeviceType.Wifi) {
                const net = d.networks.values.find(n => n.connected);
                // signalStrength is a 0.0-1.0 fraction.
                wifi = { strength: net ? Math.round(net.signalStrength * 100) : 100, iface: d.name };
            } else if (d.type === DeviceType.Wired) {
                wired = { strength: 100, iface: d.name };
            }
        }
        if (wired)
            return { kind: "wired", strength: wired.strength, iface: wired.iface };
        if (wifi)
            return { kind: "wifi", strength: wifi.strength, iface: wifi.iface };
        return { kind: "none", strength: 0, iface: "" };
    }

    readonly property string iface: root.status.iface

    // The arrows are a liveness hint, not a rate read-out, so bytes moved since
    // the last poll are only compared against a threshold: above it counts as
    // activity, below it is background chatter.
    readonly property int idleBytes: 1024
    property bool receiving: false
    property bool transmitting: false

    property int lastRx: -1
    property int lastTx: -1

    // Switching interfaces invalidates the byte baseline — without this reset a
    // stale counter reads as a huge burst of traffic on the new interface.
    onIfaceChanged: {
        root.lastRx = -1;
        root.lastTx = -1;
        root.receiving = false;
        root.transmitting = false;
    }

    FileView {
        id: rxFile
        path: root.iface ? "/sys/class/net/" + root.iface + "/statistics/rx_bytes" : ""
    }
    FileView {
        id: txFile
        path: root.iface ? "/sys/class/net/" + root.iface + "/statistics/tx_bytes" : ""
    }

    Timer {
        interval: 2000
        running: !!root.iface
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            rxFile.reload();
            txFile.reload();

            const rx = parseInt(rxFile.text().trim(), 10);
            const tx = parseInt(txFile.text().trim(), 10);

            if (!isNaN(rx)) {
                root.receiving = root.lastRx >= 0 && rx - root.lastRx > root.idleBytes;
                root.lastRx = rx;
            }
            if (!isNaN(tx)) {
                root.transmitting = root.lastTx >= 0 && tx - root.lastTx > root.idleBytes;
                root.lastTx = tx;
            }
        }
    }

    spacing: 0
    Layout.alignment: Qt.AlignVCenter

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: {
            if (root.status.kind === "none")
                return "\u{F092F}"; // no connection
            const bars = root.status.strength > 0 ? Math.ceil(root.status.strength / 25) : 0;
            if (bars >= 4)
                return "\u{F0928}";
            if (bars === 3)
                return "\u{F0925}";
            if (bars === 2)
                return "\u{F0922}";
            return "\u{F091F}";
        }
        font.family: Theme.fontMono
        font.pixelSize: 18
        color: root.status.kind !== "none" ? Colors.text : Colors.overlay0
    }

    Item {
        visible: root.status.kind !== "none"
        anchors.verticalCenter: parent.verticalCenter
        width: 7
        height: 16

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -3
            text: "▴"
            font.pixelSize: 8
            color: root.transmitting ? Colors.text : Colors.surface1
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 3
            text: "▾"
            font.pixelSize: 8
            color: root.receiving ? Colors.text : Colors.surface1
        }
    }
}
