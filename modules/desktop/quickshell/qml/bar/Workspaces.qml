pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

// kwm's tags as kanji. The shown tag sits in a rose pill that springs from
// tag to tag; occupied tags are in text colour, empty ones muted. Tags past
// the third only appear while shown or occupied; the tenth is the special one.
Item {
    id: root

    readonly property var numerals: ["一", "二", "三", "四", "五", "六", "七", "八", "九", "楽"]
    readonly property var shown: Kwm.tags.filter(t => t.focused || t.occupied || t.id <= 3 || t.id === 10)
    readonly property int cell: 26

    implicitWidth: root.shown.length * root.cell
    implicitHeight: Theme.pillHeight
    Layout.alignment: Qt.AlignVCenter

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Theme.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.emphasizedDecel
        }
    }

    // The pill spans the run of shown tags, so toggling a second one in
    // stretches it rather than jumping.
    readonly property int first: root.shown.findIndex(t => t.focused)
    readonly property int last: {
        for (let i = root.shown.length - 1; i >= 0; i--)
            if (root.shown[i].focused)
                return i;
        return -1;
    }

    Rectangle {
        visible: root.first >= 0
        x: root.first * root.cell + 1
        width: (root.last - root.first + 1) * root.cell - 2
        height: Theme.pillHeight
        radius: height / 2
        color: Colors.accent

        Behavior on x {
            NumberAnimation {
                duration: Theme.slow
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springFast
            }
        }
        Behavior on width {
            NumberAnimation {
                duration: Theme.slow
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springFast
            }
        }
    }

    Row {
        Repeater {
            model: root.shown

            Item {
                id: tag

                required property var modelData

                width: root.cell
                height: Theme.pillHeight

                Label {
                    anchors.centerIn: parent
                    text: root.numerals[tag.modelData.id - 1]
                    font.family: Theme.fontBold
                    color: tag.modelData.focused ? Colors.base : (tag.modelData.occupied ? Colors.text : Colors.muted)
                    scale: hover.containsMouse && !tag.modelData.focused ? 1.15 : 1

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.fast
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Theme.fast
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: m => m.button === Qt.RightButton ? Kwm.toggleTag(tag.modelData.id) : Kwm.focusTag(tag.modelData.id)
                }
            }
        }
    }

    WheelHandler {
        onWheel: e => Kwm.cycle(e.angleDelta.y > 0 ? -1 : 1)
    }
}
