import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.Notifications
import ".."

Rectangle {
    id: card

    required property Notification notif

    readonly property bool critical: card.notif.urgency === NotificationUrgency.Critical

    // 0 = never expire (critical, or the sender explicitly asked to persist per
    // the fd.o spec); >0 = the sender's timeout; -1 = server default.
    readonly property int timeoutMs: {
        if (card.critical)
            return 0;
        if (card.notif.expireTimeout === 0)
            return 0;
        if (card.notif.expireTimeout > 0)
            return card.notif.expireTimeout;
        return 5000;
    }

    implicitHeight: layout.implicitHeight + 20
    radius: Theme.radius
    color: Colors.mantle

    // Fade and slide in from the right. `entered` flips once on load and the
    // Behaviors below animate everything bound to it.
    property bool entered: false
    Component.onCompleted: card.entered = true

    opacity: card.entered ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCirc
        }
    }

    // A Column positions its children, so the slide goes through a transform
    // rather than through x.
    transform: Translate {
        x: card.entered ? 0 : 30
        Behavior on x {
            NumberAnimation {
                duration: 280
                easing.type: Easing.OutCirc
            }
        }
    }

    Timer {
        interval: card.timeoutMs
        running: card.timeoutMs > 0 && !hover.containsMouse
        onTriggered: card.notif.dismiss()
    }

    // Borderless; critical urgency gets an accent stripe instead.
    Rectangle {
        visible: card.critical
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 1
        width: 3
        height: parent.height - 14
        radius: 2
        color: Colors.red
    }

    // Declared before the content so the content stacks above it.
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.notif.dismiss()
    }

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 10
        anchors.leftMargin: card.critical ? 14 : 10
        spacing: 10

        Item {
            id: thumb

            readonly property bool hasImage: !!card.notif.image
            // Only take up space once something resolves, so a missing icon
            // leaves a clean text-only card rather than an empty square.
            readonly property bool resolved: thumb.hasImage ? image.status === Image.Ready : appIcon.status === Image.Ready

            visible: thumb.resolved
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 40
            implicitHeight: 40

            // The notification's own image (sender avatar, album art) when it
            // has one, otherwise the sending app's icon.
            ClippingRectangle {
                anchors.fill: parent
                radius: 6
                color: Colors.surface0
                antialiasing: true

                Image {
                    id: image
                    visible: thumb.hasImage
                    anchors.fill: parent
                    source: thumb.hasImage ? card.notif.image : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                AppIcon {
                    id: appIcon
                    visible: !thumb.hasImage
                    anchors.fill: parent
                    iconName: thumb.hasImage ? "" : card.notif.appIcon
                    fillMode: Image.PreserveAspectCrop
                }
            }

            // App badge, ringed in the card colour so it reads as a separate
            // mark sitting on the image.
            Rectangle {
                visible: thumb.hasImage && badge.status === Image.Ready
                width: 18
                height: 18
                radius: width / 2
                color: Colors.mantle
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -2
                anchors.bottomMargin: -2

                ClippingRectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: width / 2
                    color: Colors.surface0
                    antialiasing: true

                    AppIcon {
                        id: badge
                        anchors.fill: parent
                        iconName: card.notif.appIcon
                        fillMode: Image.PreserveAspectCrop
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                visible: !!card.notif.summary
                text: card.notif.summary
                font.family: Theme.fontMono
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Colors.text
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: !!card.notif.body
                text: card.notif.body
                textFormat: Text.StyledText
                font.family: Theme.fontMono
                font.pixelSize: 13
                color: Colors.subtext0
                wrapMode: Text.WordWrap
                maximumLineCount: 4
                elide: Text.ElideRight
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
        }
    }
}
