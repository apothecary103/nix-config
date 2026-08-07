import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import ".."

Scope {
    id: root

    property bool open: false
    property string query: ""

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            root.open = !root.open;
        }
    }

    // Launch counts, so the list is ordered most-used first. JsonAdapter both
    // parses the file and writes it back, so there is no shell quoting to get
    // wrong.
    FileView {
        id: usageFile
        path: Quickshell.env("HOME") + "/.cache/quickshell/launcher-usage.json"
        watchChanges: false
        printErrors: false
        // The file legitimately does not exist until the first launch.
        onLoadFailed: error => usageFile.writeAdapter()
        JsonAdapter {
            id: usage
            property var counts: ({})
        }
    }

    function appKey(app) {
        return (app && (app.id || app.name)) || "";
    }

    function countFor(app) {
        return usage.counts[root.appKey(app)] || 0;
    }

    readonly property var apps: {
        const all = DesktopEntries.applications.values.filter(a => !a.noDisplay);
        return all.sort((x, y) => root.countFor(y) - root.countFor(x) || (x.name || "").localeCompare(y.name || ""));
    }

    // Prefix matches float above substring matches, then most-used.
    readonly property var filtered: {
        const q = root.query.trim().toLowerCase();
        if (!q)
            return root.apps;

        const hits = root.apps.filter(a => (a.name || "").toLowerCase().includes(q) || (a.genericName || "").toLowerCase().includes(q));
        return hits.sort((x, y) => {
            const xp = (x.name || "").toLowerCase().startsWith(q) ? 0 : 1;
            const yp = (y.name || "").toLowerCase().startsWith(q) ? 0 : 1;
            return xp - yp || root.countFor(y) - root.countFor(x) || (x.name || "").localeCompare(y.name || "");
        });
    }

    function launch(index) {
        const app = root.filtered[index];
        if (!app)
            return;

        const key = root.appKey(app);
        if (key) {
            // Reassigned rather than mutated so the `apps` sort recomputes.
            const next = Object.assign({}, usage.counts);
            next[key] = (next[key] || 0) + 1;
            usage.counts = next;
            usageFile.writeAdapter();
        }

        app.execute();
        root.open = false;
    }

    function escapeHtml(s) {
        return (s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // Each piece is escaped separately so names containing & < > cannot break
    // the markup.
    function highlightName(name, q) {
        const query = (q || "").trim();
        if (!query)
            return root.escapeHtml(name);

        const at = name.toLowerCase().indexOf(query.toLowerCase());
        if (at < 0)
            return root.escapeHtml(name);

        return root.escapeHtml(name.slice(0, at)) + "<u><b>" + root.escapeHtml(name.slice(at, at + query.length)) + "</b></u>" + root.escapeHtml(name.slice(at + query.length));
    }

    PanelWindow {
        visible: root.open

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "launcher"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        onVisibleChanged: {
            if (!visible)
                return;
            root.query = "";
            search.text = "";
            list.currentIndex = 0;
            search.forceActiveFocus();
        }

        // Click-away to dismiss; the box below absorbs its own clicks.
        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }

        Rectangle {
            anchors.centerIn: parent
            implicitWidth: 480
            implicitHeight: layout.implicitHeight + 50
            radius: Theme.radius
            color: Colors.base

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: layout
                anchors.fill: parent
                anchors.margins: 25
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.bottomMargin: 15
                    spacing: 10

                    MonoText {
                        text: "\u{F002}" // magnifier
                        font.weight: Font.Medium
                        font.pointSize: 12
                        color: Colors.subtext1
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: search.implicitHeight

                        TextInput {
                            id: search
                            anchors.fill: parent
                            font.family: Theme.fontMono
                            font.weight: Font.Medium
                            font.pointSize: 12
                            color: Colors.text
                            clip: true
                            selectByMouse: true
                            selectionColor: Colors.text
                            selectedTextColor: Colors.base
                            verticalAlignment: TextInput.AlignVCenter

                            onTextChanged: {
                                root.query = text;
                                list.currentIndex = 0;
                            }

                            // Emacs bindings, which is why C-a is start-of-line
                            // rather than select-all.
                            Keys.onPressed: event => {
                                const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                                event.accepted = true;

                                if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (ctrl && event.key === Qt.Key_N))
                                    list.incrementCurrentIndex();
                                else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (ctrl && event.key === Qt.Key_P))
                                    list.decrementCurrentIndex();
                                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                    root.launch(list.currentIndex);
                                else if (event.key === Qt.Key_Escape || (ctrl && event.key === Qt.Key_G))
                                    root.open = false;
                                else if (ctrl && event.key === Qt.Key_A)
                                    search.cursorPosition = 0;
                                else if (ctrl && event.key === Qt.Key_E)
                                    search.cursorPosition = search.text.length;
                                else if (ctrl && event.key === Qt.Key_F)
                                    search.cursorPosition = Math.min(search.text.length, search.cursorPosition + 1);
                                else if (ctrl && event.key === Qt.Key_B)
                                    search.cursorPosition = Math.max(0, search.cursorPosition - 1);
                                else if (ctrl && event.key === Qt.Key_D)
                                    search.remove(search.cursorPosition, search.cursorPosition + 1);
                                else if (ctrl && event.key === Qt.Key_H)
                                    search.remove(search.cursorPosition - 1, search.cursorPosition);
                                else if (ctrl && event.key === Qt.Key_K)
                                    search.remove(search.cursorPosition, search.text.length);
                                else if (ctrl && event.key === Qt.Key_W)
                                    search.remove(root.wordStart(search.text, search.cursorPosition), search.cursorPosition);
                                else
                                    event.accepted = false;
                            }

                            Text {
                                anchors.fill: parent
                                visible: search.text.length === 0
                                text: "search..."
                                font: search.font
                                color: Colors.surface2
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true

                    readonly property int rowHeight: 42
                    readonly property int rows: 6

                    // Reserved unconditionally, so the window never resizes with
                    // the match count.
                    Layout.preferredHeight: list.rows * list.rowHeight + (list.rows - 1) * spacing

                    model: root.filtered
                    spacing: 5
                    clip: true
                    reuseItems: true
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 0
                    snapMode: ListView.SnapToItem
                    highlightRangeMode: ListView.NoHighlightRange

                    // Paginated: moving past the last visible row reveals the
                    // next block of rows with the selection at the top, rather
                    // than scrolling a line at a time.
                    onCurrentIndexChanged: positionViewAtIndex(Math.floor(currentIndex / list.rows) * list.rows, ListView.Beginning)

                    // Trailing slack so a final page holding fewer than `rows`
                    // entries can still scroll its first item to the top;
                    // otherwise StopAtBounds clamps and the page re-shows rows
                    // from the one before it.
                    footer: Item {
                        width: list.width
                        height: (list.rows - 1) * (list.rowHeight + list.spacing)
                    }

                    delegate: Rectangle {
                        id: entry
                        required property var modelData
                        required property int index

                        width: list.width
                        height: list.rowHeight
                        radius: Theme.radius - 2
                        color: entry.ListView.isCurrentItem ? Colors.text : "transparent"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                iconName: entry.modelData.icon
                            }

                            MonoText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 18 - parent.spacing
                                textFormat: Text.StyledText
                                text: root.highlightName(entry.modelData.name || "", root.query)
                                font.pointSize: 12
                                font.weight: Font.Medium
                                color: entry.ListView.isCurrentItem ? Colors.base : Colors.text
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: list.currentIndex = entry.index
                            onClicked: root.launch(entry.index)
                        }
                    }
                }
            }
        }
    }

    // Start of the word before `at`, skipping any run of spaces first (C-w).
    function wordStart(text, at) {
        let p = at;
        while (p > 0 && text[p - 1] === " ")
            p--;
        while (p > 0 && text[p - 1] !== " ")
            p--;
        return p;
    }
}
