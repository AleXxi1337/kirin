pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.components
import qs.services

// Wallpaper picker shown by the launcher for `/wallpaper [filter]`.
// Lists images in the configured folder (recursively) as a grid of previews.
// The selected one is previewed live on the desktop (wallpaper and colours);
// Enter keeps it, leaving the picker any other way restores the saved one.
Item {
    id: root

    property string filter
    property real spacingFactor: 1
    // Device pixel ratio of the screen, for sharp previews.
    property real pixelRatio: 1
    property bool committed: false
    // Live preview starts with the first arrow key, not on opening the picker.
    property bool browsing: false
    signal done

    readonly property string home: Quickshell.env("HOME")
    readonly property string directory: Config.wallpaper.directory.replace(/^~(?=\/|$)/, home)
    readonly property string prettyDirectory: directory.startsWith(home) ? "~" + directory.slice(home.length) : directory

    property var files: []
    property bool loaded: false
    // Image path -> its small cached preview, once there is one.
    property var thumbs: ({})
    // Images whose preview couldn't be made: shown from the original.
    property var unthumbable: ({})
    // Previews at 960×540, already cut to the cells' 16:9 (a cell is never
    // wider): sharp, nothing stretched. The size is in the folder's name, so
    // a change makes them anew.
    readonly property string thumbDir: `${Quickshell.env("XDG_CACHE_HOME") || home + "/.cache"}/kirin/wallpaper-thumbs-960x540`

    // Fuzzy (subsequence) match on the file name, best matches first.
    readonly property var shown: {
        const q = filter.trim().toLowerCase();
        if (!q)
            return files;
        const scored = [];
        for (const path of files) {
            const name = path.slice(path.lastIndexOf("/") + 1).toLowerCase();
            let i = 0, gaps = 0, last = -1;
            for (let j = 0; j < name.length && i < q.length; j++) {
                if (name[j] === q[i]) {
                    if (last >= 0)
                        gaps += j - last - 1;
                    last = j;
                    i++;
                }
            }
            if (i === q.length)
                scored.push({
                    path,
                    score: gaps + (name.includes(q) ? -1000 : 0)
                });
        }
        return scored.sort((a, b) => a.score - b.score).map(s => s.path);
    }

    implicitHeight: shown.length ? Math.min(grid.contentHeight, grid.cellHeight * 2.5) + sp(12) : empty.implicitHeight + sp(48)

    Component.onDestruction: {
        if (!committed)
            Wallpaper.preview = "";
    }

    // Try the selection on the desktop once navigation settles.
    Timer {
        id: previewTimer

        interval: 250
        onTriggered: {
            if (root.browsing)
                Wallpaper.preview = root.shown[grid.currentIndex] ?? "";
        }
    }

    function sp(n: real): int {
        return Math.round(n * spacingFactor);
    }

    function move(key: int): void {
        browsing = true;
        if (grid.currentIndex < 0) {
            grid.currentIndex = 0;
            return;
        }
        switch (key) {
        case Qt.Key_Left:
            grid.moveCurrentIndexLeft();
            break;
        case Qt.Key_Right:
        case Qt.Key_Tab:
            grid.moveCurrentIndexRight();
            break;
        case Qt.Key_Up:
            grid.moveCurrentIndexUp();
            break;
        case Qt.Key_Down:
            grid.moveCurrentIndexDown();
            break;
        }
    }

    function activate(): void {
        const path = shown[grid.currentIndex];
        if (!path)
            return;
        committed = true;
        Wallpaper.preview = path;
        Wallpaper.set(path);
        done();
    }

    // After the grid has taken the new list: setting its model resets the
    // current index to 0, which would undo a selection made right away.
    onShownChanged: Qt.callLater(selectInitial)

    function selectInitial(): void {
        const current = shown.indexOf(Wallpaper.displayed);
        grid.currentIndex = filter.trim() || current < 0 ? (shown.length ? 0 : -1) : current;
        grid.positionViewAtIndex(Math.max(0, grid.currentIndex), GridView.Contain);
    }

    // Lists the images, then makes the previews that are missing or older
    // than their image (decoding a full-size picture for every cell made the
    // grid take seconds). Lines: "F <image>" for each image, then
    // "T <image> <preview>" for each preview ready, "X <image>" for failures.
    Process {
        id: lister

        running: true
        command: ["sh", `${Quickshell.shellDir}/scripts/wallpaper-thumbs.sh`, root.directory, root.thumbDir]

        property var found: []

        stdout: SplitParser {
            onRead: line => {
                const [kind, path, thumb] = line.split("\t");
                if (kind === "F") {
                    lister.found.push(path);
                } else if (kind === "E") {
                    root.files = lister.found;
                    root.loaded = true;
                    Scheme.prepare(root.files);
                    Wallpaper.prepare(root.files);
                } else if (kind === "T") {
                    root.thumbs = Object.assign({}, root.thumbs, { [path]: thumb });
                } else if (kind === "X") {
                    root.unthumbable = Object.assign({}, root.unthumbable, { [path]: true });
                }
            }
        }
        onExited: root.loaded = true
    }

    StyledText {
        id: empty

        visible: root.loaded && !root.shown.length
        anchors.centerIn: parent
        width: parent.width - root.sp(48)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        color: Theme.m3onSurfaceVariant
        text: root.files.length ? `No wallpapers match “${root.filter.trim()}”` : `No images in ${root.prettyDirectory}`
    }

    GridView {
        id: grid

        readonly property int columns: 3

        anchors.fill: parent
        anchors.margins: root.sp(6)
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds

        TouchpadScroll {
            flickable: grid
        }
        cellWidth: width / columns
        cellHeight: (cellWidth - root.sp(12)) * 9 / 16 + root.sp(12)
        model: root.shown
        currentIndex: -1
        highlightFollowsCurrentItem: false

        onCurrentIndexChanged: {
            previewTimer.restart();
            reveal();
        }

        // The selection kept in sight: moved past an edge with the arrows,
        // the grid scrolls (smoothly) just far enough to show it whole.
        function reveal(): void {
            if (currentIndex < 0 || height <= 0)
                return;
            const top = Math.floor(currentIndex / columns) * cellHeight + originY;
            const bottom = top + cellHeight;
            let target = contentY;
            if (top < contentY)
                target = top;
            else if (bottom > contentY + height)
                target = bottom - height;
            target = Math.max(originY, Math.min(target, originY + contentHeight - height));
            if (Math.abs(target - contentY) < 1)
                return;
            follow.stop();
            follow.from = contentY;
            follow.to = target;
            follow.start();
        }

        NumberAnimation {
            id: follow

            target: grid
            property: "contentY"
            duration: 220
            easing.type: Easing.OutCubic
        }

        // Scrolled by hand meanwhile: that wins.
        onMovementStarted: follow.stop()

        delegate: Item {
            id: cell

            required property string modelData
            required property int index
            readonly property bool selected: GridView.isCurrentItem
            readonly property bool current: modelData === Wallpaper.current

            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                id: frame

                x: root.sp(6)
                y: root.sp(6)
                width: parent.width - root.sp(12)
                height: width * 9 / 16
                radius: Theme.rounding.large
                color: Theme.m3surfaceContainerHighest
                border.width: cell.selected ? 3 : 0
                border.color: Theme.m3primary
                // The selected preview pops forward a little.
                scale: cell.selected ? 1 : 0.94

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                // Selection ring: the frame's border shows around a slightly inset preview.
                ClippingRectangle {
                    anchors.fill: parent
                    anchors.margins: cell.selected ? 5 : 0
                    radius: Math.max(0, frame.radius - anchors.margins)
                    color: "transparent"

                    Image {
                        id: preview

                        anchors.fill: parent
                        // The cached preview; the original only if none can be made.
                        source: root.thumbs[cell.modelData] ? `file://${root.thumbs[cell.modelData]}` : root.unthumbable[cell.modelData] && !Wallpaper.isVideo(cell.modelData) ? `file://${cell.modelData}` : ""
                        // Decode at the size it's drawn, in device pixels.
                        sourceSize.width: Math.ceil(frame.width * root.pixelRatio)
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: true
                        cache: true
                    }
                }

                MaterialIcon {
                    visible: preview.status !== Image.Ready
                    anchors.centerIn: parent
                    text: "image"
                    color: Theme.m3onSurfaceVariant
                }

                // A video wallpaper.
                Rectangle {
                    visible: Wallpaper.isVideo(cell.modelData)
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: root.sp(8)
                    width: 24
                    height: 24
                    radius: 12
                    color: Qt.alpha(Theme.m3scrim, 0.55)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "play_arrow"
                        fill: true
                        size: 16
                        color: "white"
                    }
                }

                // Marks the wallpaper in use.
                Rectangle {
                    visible: cell.current
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: root.sp(8)
                    width: 24
                    height: 24
                    radius: 12
                    color: Theme.m3primary

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "check"
                        size: 16
                        color: Theme.m3onPrimary
                    }
                }
            }

            MouseArea {
                anchors.fill: frame
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    grid.currentIndex = cell.index;
                    root.activate();
                }
            }
        }
    }
}
