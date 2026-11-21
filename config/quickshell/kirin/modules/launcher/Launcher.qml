pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import qs.components
import qs.services

// Spotlight-style launcher: one search field for apps, files, system commands,
// a calculator and web search. Toggle with `qs -c kirin ipc call launcher toggle`
// (bound to SUPER+Space).
Scope {
    id: root

    property bool shown: false
    // Picked when opening, so the launcher doesn't jump if focus moves.
    property ShellScreen screen

    // The launcher is a bit roomier than other windows: its paddings are 25%
    // larger at the same Spacing setting (80% in settings = 100% here).
    readonly property real spacingFactor: Theme.spacingScale * 1.25

    function sp(n: real): int {
        return Math.round(n * spacingFactor);
    }

    // Set while the close animation plays; the window goes away when it ends.
    property bool closing: false

    // Text the field starts with on the next open ("/clipboard " etc.).
    property string startText: ""

    function open(): void {
        if (shown && closing) {
            closing = false;
            return;
        }
        screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
        shown = true;
    }

    function close(): void {
        if (shown)
            closing = true;
    }

    IpcHandler {
        target: "launcher"

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }

        // Straight into the clipboard history (for a key binding); again closes.
        function clipboard(): void {
            if (root.shown && !root.closing) {
                root.close();
                return;
            }
            root.startText = "/clipboard ";
            root.open();
        }

        function toggle(): void {
            if (root.shown && !root.closing)
                root.close();
            else
                root.open();
        }
    }

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: win

            screen: root.screen
            color: "transparent"

            WlrLayershell.namespace: "kirin-launcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // "/wallpaper [filter]" turns the launcher into the wallpaper picker.
            readonly property bool wallpaperMode: /^\/wallpaper(\s|$)/.test(input.text)
            readonly property string modeArgument: input.text.replace(/^\/\S*\s*/, "")

            Search {
                id: search

                query: input.text
            }

            // Click outside the card closes the launcher.
            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }

            // The launcher has focus: the active window's shadow colour.
            WindowShadow {
                target: card
                active: true
                transform: Translate {
                    y: drop.y
                }
            }

            Rectangle {
                id: card

                // Wider while picking wallpapers, for bigger previews.
                width: Math.min(win.wallpaperMode ? root.sp(900) + 40 : root.sp(600) + 40, win.width - 32)

                Behavior on width {
                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }
                // Grows and shrinks with the results.
                height: column.implicitHeight
                clip: true

                Behavior on height {
                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }
                x: (win.width - width) / 2
                y: win.height * 0.18
                radius: Theme.rounding.extraLarge
                color: Theme.m3surfaceContainer
                // Same as a focused window's border in Hyprland (width from
                // HyprLook, colour as in modules/colors.lua).
                border.width: HyprLook.borderSize
                border.color: Qt.alpha(Theme.m3primary, 0.4)

                // Swallow clicks so they don't reach the close area.
                MouseArea {
                    anchors.fill: parent
                }

                // Open: springs in from slightly smaller and higher.
                // Close: quick fade and shrink, then the window is destroyed.
                opacity: 0
                scale: 0.9
                transformOrigin: Item.Top
                transform: Translate {
                    id: drop

                    y: -root.sp(16)
                }

                Component.onCompleted: appear.start()

                Connections {
                    target: root

                    function onClosingChanged(): void {
                        if (root.closing) {
                            appear.stop();
                            disappear.start();
                        } else {
                            disappear.stop();
                            appear.start();
                        }
                    }
                }

                ParallelAnimation {
                    id: appear

                    Anim {
                        target: card
                        property: "opacity"
                        to: 1
                        type: Anim.DefaultEffects
                    }
                    Anim {
                        target: card
                        property: "scale"
                        to: 1
                        type: Anim.DefaultSpatial
                    }
                    Anim {
                        target: drop
                        property: "y"
                        to: 0
                        type: Anim.DefaultSpatial
                    }
                }

                ParallelAnimation {
                    id: disappear

                    onFinished: {
                        root.shown = false;
                        root.closing = false;
                    }

                    Anim {
                        target: card
                        property: "opacity"
                        to: 0
                        type: Anim.FastEffects
                    }
                    Anim {
                        target: card
                        property: "scale"
                        to: 0.95
                        type: Anim.StandardSmall
                    }
                }

                Column {
                    id: column

                    width: parent.width

                    // Search field.
                    Item {
                        width: parent.width
                        height: Theme.size.display + root.sp(32)

                        MaterialIcon {
                            id: searchIcon

                            anchors.left: parent.left
                            anchors.leftMargin: root.sp(20)
                            anchors.verticalCenter: parent.verticalCenter
                            text: "search"
                            size: Theme.size.display + 2
                            color: Theme.m3onSurfaceVariant
                        }

                        TextInput {
                            id: input

                            Component.onCompleted: {
                                text = root.startText;
                                root.startText = "";
                            }
                            anchors.left: searchIcon.right
                            anchors.leftMargin: root.sp(16)
                            anchors.right: parent.right
                            anchors.rightMargin: root.sp(20)
                            anchors.verticalCenter: parent.verticalCenter
                            focus: true
                            color: Theme.m3onSurface
                            selectionColor: Theme.m3primary
                            selectedTextColor: Theme.m3onPrimary
                            font.family: Theme.font.family
                            font.pixelSize: Theme.size.display
                            clip: true


                            Keys.onPressed: event => {
                                if (win.wallpaperMode && wallpaperLoader.item) {
                                    const grid = wallpaperLoader.item;
                                    switch (event.key) {
                                    case Qt.Key_Left:
                                    case Qt.Key_Right:
                                    case Qt.Key_Up:
                                    case Qt.Key_Down:
                                    case Qt.Key_Tab:
                                        grid.move(event.key);
                                        event.accepted = true;
                                        return;
                                    case Qt.Key_Return:
                                    case Qt.Key_Enter:
                                        grid.activate();
                                        event.accepted = true;
                                        return;
                                    }
                                }
                                switch (event.key) {
                                case Qt.Key_Down:
                                case Qt.Key_Tab:
                                    list.step(1);
                                    break;
                                case Qt.Key_Up:
                                case Qt.Key_Backtab:
                                    list.step(-1);
                                    break;
                                case Qt.Key_Return:
                                case Qt.Key_Enter:
                                    list.activate(list.currentIndex, event.modifiers & Qt.ControlModifier);
                                    break;
                                case Qt.Key_Delete:
                                    // Clipboard history: remove the selected entry.
                                    if (search.results[list.currentIndex]?.kind !== "clip")
                                        return;
                                    Clipboard.remove(search.results[list.currentIndex].line);
                                    break;
                                case Qt.Key_Escape:
                                    if (text)
                                        text = "";
                                    else
                                        root.close();
                                    break;
                                default:
                                    return;
                                }
                                event.accepted = true;
                            }

                            StyledText {
                                visible: !input.text
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Search apps, files and more"
                                color: Theme.m3onSurfaceVariant
                                font.pixelSize: Theme.size.display
                            }
                        }
                    }

                    Rectangle {
                        visible: search.results.length > 0 || win.wallpaperMode
                        width: parent.width
                        height: 1
                        color: Theme.m3outlineVariant
                    }

                    ListView {
                        id: list

                        visible: search.results.length > 0 && !win.wallpaperMode
                        width: parent.width
                        height: visible ? Math.min(contentHeight + root.sp(12), root.sp(380) + 40) : 0
                        topMargin: root.sp(6)
                        bottomMargin: root.sp(6)
                        clip: true
                        boundsBehavior: Flickable.DragAndOvershootBounds

                        TouchpadScroll {
                            flickable: list
                        }
                        model: search.results
                        currentIndex: -1

                        // One highlight that slides between rows instead of each row lighting up.
                        highlightFollowsCurrentItem: false
                        highlight: Rectangle {
                            id: highlight

                            // Where the current row is. For the frame a rebuilt
                            // list has no row yet, it stays where it was instead
                            // of blinking out at the top.
                            readonly property real targetY: list.currentItem?.y ?? list.heldY
                            readonly property real targetHeight: list.currentItem?.height ?? list.heldHeight

                            // Slides when the selection moves, jumps when typing
                            // replaces the list (the model is a fresh array each
                            // time, so the view resets its selection to the top
                            // first, and a slide went up and back down). An
                            // animation of its own rather than a Behavior: one in
                            // a Behavior can't be stopped.
                            function move(): void {
                                if (list.rebuilding) {
                                    snap();
                                    return;
                                }
                                slide.stop();
                                slideY.to = targetY;
                                slideHeight.to = targetHeight;
                                slide.start();
                            }

                            // Called through highlightItem: the list can't see ids
                            // inside this component.
                            function snap(): void {
                                slide.stop();
                                y = targetY;
                                height = targetHeight;
                            }

                            onTargetYChanged: {
                                if (list.currentItem)
                                    list.heldY = targetY;
                                move();
                            }
                            onTargetHeightChanged: {
                                if (list.currentItem)
                                    list.heldHeight = targetHeight;
                                move();
                            }
                            Component.onCompleted: snap()

                            visible: list.currentIndex >= 0
                            x: root.sp(8)
                            width: list.width - root.sp(16)
                            radius: Theme.rounding.large
                            color: Theme.m3secondaryContainer

                            ParallelAnimation {
                                id: slide

                                Anim {
                                    id: slideY

                                    target: highlight
                                    property: "y"
                                    type: Anim.FastSpatial
                                }
                                Anim {
                                    id: slideHeight

                                    target: highlight
                                    property: "height"
                                    type: Anim.FastSpatial
                                }
                            }
                        }

                        // A new result list: the view has already reset the selection
                        // to the top by now, and the highlight started sliding up
                        // there. Stop that, and put it on the first row directly.
                        property bool rebuilding: false
                        property real heldY: 0
                        property real heldHeight: 0

                        onModelChanged: {
                            rebuilding = true;
                            rebuilt.restart();
                            currentIndex = firstSelectable(0, 1);
                            // New rows sit at y 0 until the next layout pass; place
                            // them now so the highlight doesn't flash up there.
                            forceLayout();
                            list.highlightItem?.snap();
                        }

                        Timer {
                            id: rebuilt

                            interval: 50
                            onTriggered: list.rebuilding = false
                        }

                        // Last cursor position seen by a row, in window coordinates.
                        property var lastMouse: null

                        onCountChanged: {
                            if (currentIndex < 0 || currentIndex >= count || search.results[currentIndex]?.kind === "header")
                                currentIndex = firstSelectable(0, 1);
                        }

                        function firstSelectable(from: int, dir: int): int {
                            // The results, not count: that lags behind a new model.
                            for (let i = from; i >= 0 && i < search.results.length; i += dir) {
                                if (search.results[i].kind !== "header")
                                    return i;
                            }
                            return -1;
                        }

                        function step(dir: int): void {
                            const next = firstSelectable(currentIndex + dir, dir);
                            if (next >= 0) {
                                currentIndex = next;
                                positionViewAtIndex(next, ListView.Contain);
                            }
                        }

                        function activate(index: int, alt: bool): void {
                            const item = search.results[index];
                            if (!item || item.kind === "header")
                                return;
                            // Slash commands complete into the field instead of running.
                            if (item.kind === "slash") {
                                input.text = item.insert;
                                return;
                            }
                            search.activate(item, alt);
                            root.close();
                        }

                        delegate: Item {
                            id: row

                            required property var modelData
                            required property int index
                            readonly property bool header: modelData.kind === "header"
                            readonly property bool selected: ListView.isCurrentItem

                            width: ListView.view.width
                            height: header ? Theme.size.labelMedium + root.sp(18) : Theme.size.bodyLarge + Theme.size.labelMedium + root.sp(18)

                            StyledText {
                                visible: row.header
                                anchors.left: parent.left
                                anchors.leftMargin: root.sp(20)
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: root.sp(4)
                                text: row.modelData.title
                                color: Theme.m3primary
                                font.pixelSize: Theme.size.labelMedium
                                font.weight: Font.Medium
                            }

                            Rectangle {
                                visible: !row.header
                                anchors.fill: parent
                                anchors.leftMargin: root.sp(8)
                                anchors.rightMargin: root.sp(8)
                                radius: Theme.rounding.large
                                color: "transparent"

                                // App icon from the icon theme, or a symbol in a tonal circle.
                                Item {
                                    id: icon

                                    anchors.left: parent.left
                                    anchors.leftMargin: root.sp(10)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.size.bodyLarge + Theme.size.labelMedium + 2
                                    height: width

                                    // Apps: their own icon, as it is.
                                    AppIcon {
                                        visible: row.modelData.kind === "app"
                                        anchors.fill: parent
                                        entry: visible ? search.apps[row.modelData.id] ?? null : null
                                        appId: visible ? row.modelData.appIcon ?? "" : ""
                                        selected: row.selected
                                        themed: false
                                    }

                                    // Clipboard images: a thumbnail, in the icon shape.
                                    ClippingRectangle {
                                        visible: !!row.modelData.thumb
                                        anchors.fill: parent
                                        radius: Theme.iconRadius(width)
                                        color: "transparent"

                                        Image {
                                            anchors.fill: parent
                                            source: parent.visible ? `file://${row.modelData.thumb}` : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                        }
                                    }

                                    Rectangle {
                                        visible: row.modelData.kind !== "app" && !row.modelData.thumb
                                        anchors.fill: parent
                                        radius: Theme.iconRadius(width)
                                        color: row.selected ? Theme.m3primary : Theme.m3primaryContainer

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            text: row.modelData.icon ?? ""
                                            size: Math.round(parent.width * 0.55)
                                            fill: true
                                            color: row.selected ? Theme.m3onPrimary : Theme.m3onPrimaryContainer
                                        }
                                    }
                                }

                                Column {
                                    anchors.left: icon.right
                                    anchors.leftMargin: root.sp(12)
                                    anchors.right: parent.right
                                    anchors.rightMargin: root.sp(12)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.sp(1)

                                    StyledText {
                                        width: parent.width
                                        text: row.modelData.title
                                        elide: Text.ElideRight
                                        font.pixelSize: Theme.size.bodyLarge
                                        color: row.selected ? Theme.m3onSecondaryContainer : Theme.m3onSurface
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: row.modelData.subtitle ?? ""
                                        elide: Text.ElideMiddle
                                        font.pixelSize: Theme.size.labelMedium
                                        color: row.selected ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    // Only real mouse movement selects. Qt also sends hover events when
                                    // results change under a still cursor; those keep the same position.
                                    onPositionChanged: mouse => {
                                        const p = mapToItem(null, mouse.x, mouse.y);
                                        const last = row.ListView.view.lastMouse;
                                        row.ListView.view.lastMouse = p;
                                        if (last && (last.x !== p.x || last.y !== p.y))
                                            row.ListView.view.currentIndex = row.index;
                                    }
                                    onClicked: mouse => row.ListView.view.activate(row.index, mouse.modifiers & Qt.ControlModifier)
                                }
                            }
                        }
                    }

                    Loader {
                        id: wallpaperLoader

                        active: win.wallpaperMode
                        visible: active
                        width: parent.width
                        height: item ? item.implicitHeight : 0

                        sourceComponent: WallpaperGrid {
                            filter: win.modeArgument
                            spacingFactor: root.spacingFactor
                            pixelRatio: root.screen?.devicePixelRatio ?? 1
                            onDone: root.close()
                        }
                    }
                }
            }
        }
    }
}
