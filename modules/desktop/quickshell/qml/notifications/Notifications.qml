// Bound, so the Repeater delegate below can reach `stack` without relying on
// dynamic scope lookup.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import ".."

// Notification daemon and the top-right popup stack.
Scope {
    id: root

    NotificationServer {
        id: server

        keepOnReload: false
        imageSupported: true
        actionsSupported: false
        bodySupported: true
        bodyMarkupSupported: true
        persistenceSupported: true

        // Tracking keeps the notification alive past this signal so it shows up
        // in trackedNotifications for the stack below.
        onNotification: notif => notif.tracked = true
    }

    PanelWindow {
        anchors {
            top: true
            right: true
        }

        // Just below the bar, sharing its right margin.
        margins {
            top: Theme.barMargin + Theme.barHeight + 8
            right: Theme.barMargin
        }

        implicitWidth: 300
        // A layer surface with zero height is invalid, so hold one pixel while
        // the stack is empty.
        implicitHeight: Math.max(1, stack.implicitHeight)
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "notifications"
        exclusionMode: ExclusionMode.Ignore
        // Clicks pass through everywhere except the cards themselves.
        mask: Region {
            item: stack
        }

        Column {
            id: stack
            anchors.top: parent.top
            anchors.right: parent.right
            width: parent.width
            spacing: 8

            Repeater {
                model: server.trackedNotifications

                NotificationCard {
                    id: card
                    required property var modelData

                    width: stack.width
                    notif: card.modelData
                }
            }
        }
    }
}
