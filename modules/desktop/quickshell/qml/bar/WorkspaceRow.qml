// Bound, so the Repeater delegate below can reach `root` without relying on
// dynamic scope lookup.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

// Workspaces as CJK numerals, counting from 零 so the first workspace reads as
// zero. The first five are always shown so the row does not jump around as
// workspaces come and go; anything beyond that appears only while it exists.
Row {
    id: root

    readonly property var numerals: ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
    readonly property int pinned: 5

    readonly property var shown: {
        const live = Workspaces.list.filter(w => w.idx >= 1 && w.idx <= root.numerals.length);
        const byIdx = {};
        for (const w of live)
            byIdx[w.idx] = w;

        const out = [];
        for (let idx = 1; idx <= root.pinned; idx++)
            out.push(byIdx[idx] || { id: idx, idx: idx, active: false });
        for (const w of live)
            if (w.idx > root.pinned)
                out.push(w);
        return out;
    }

    spacing: 12
    Layout.alignment: Qt.AlignVCenter

    Repeater {
        model: root.shown

        Text {
            id: numeral
            required property var modelData

            text: root.numerals[numeral.modelData.idx - 1]
            font.family: Theme.fontMono
            font.pixelSize: 13
            font.bold: true
            color: numeral.modelData.active ? Colors.blue : Colors.overlay0

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Workspaces.activate(numeral.modelData)
            }
        }
    }
}
