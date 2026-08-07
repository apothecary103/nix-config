import QtQuick
import Quickshell

Image {
    id: root

    property string iconName: ""

    fillMode: Image.PreserveAspectFit
    asynchronous: true
    sourceSize.width: 64
    sourceSize.height: 64

    readonly property var candidates: {
        if (!root.iconName)
            return [];
        if (root.iconName.startsWith("/"))
            return ["file://" + root.iconName];
        if (root.iconName.startsWith("file:"))
            return [root.iconName];

        const list = [];
        if (Pixora.has(root.iconName))
            list.push(Pixora.pathFor(root.iconName));
        const themed = Quickshell.iconPath(root.iconName, true);
        if (themed)
            list.push(themed);
        return list;
    }

    property int candIndex: 0
    onIconNameChanged: root.candIndex = 0

    // Empty rather than a broken-image placeholder once the candidates run out,
    // so callers can bind visibility to `status === Image.Ready`.
    source: root.candIndex < root.candidates.length ? root.candidates[root.candIndex] : ""
    onStatusChanged: {
        if (root.status === Image.Error && root.candIndex < root.candidates.length - 1)
            root.candIndex++;
    }
}
