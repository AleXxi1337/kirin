pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import qs.components
import qs.services

// The taskbar, in windows mode (WindowMode, hypr/modules/winmode.lua): in
// place of the workspaces, one entry per app, its windows grouped: a stack
// of the app's own icon (as in the launcher), one per window, overlapping
// as on a workspace in tiling (MAX_STACK at most). The active app on the accent plate, apps with every window
// minimized faded; an app asking for attention pulses until it's focused.
//
// Click: one window: it comes back if minimized, minimizes if active, comes
// up otherwise. Several: the last used one comes up; if the app is active
// already, the next of its windows does. Middle click: a new window. Right
// click: the menu (new window, minimize/restore, close). Drag: reorder the
// apps (kept until kirin restarts).
// Hover: a card with each window's live preview and title; a click on one
// brings it up, its × (or a middle click) closes it.
//
// No taller than `maxHeight` (as the workspaces): past it, the column
// scrolls (the wheel), fading out at an edge with more beyond it.
Item {
    id: root

    // 0: no limit.
    property real maxHeight: 0
    // As the bar gives its modules, for the cards.
    property real cardOffset: 0
    property Item bounds: null

    readonly property int iconSize: Math.round(26 * Theme.fontScale)
    readonly property int pad: Theme.sp(5)
    readonly property int cell: iconSize + pad * 2
    readonly property int gap: Theme.sp(4)
    // Icons in a stack: each this far below the one before (overlapping).
    readonly property real stackStep: Math.round(iconSize * 0.45)
    readonly property int maxStack: 3
    readonly property string minimizedName: "special:minimized"

    // Windows on a desktop or minimized; not the scratchpad nor the lock
    // screen's workspaces.
    readonly property var windows: Hyprland.toplevels.values.filter(t => {
        const ws = t.workspace;
        return ws && (ws.id > 0 || ws.name === root.minimizedName);
    })

    function appIdOf(t: var): string {
        return t?.wayland?.appId || t?.lastIpcObject?.class || "";
    }

    function minimized(t: var): bool {
        return t?.workspace?.name === root.minimizedName;
    }

    // The order the user dragged the apps into; apps not in it follow, in
    // the order they opened.
    property var order: []

    // Windows by app: map key → {appId, windows}, keys in taskbar order.
    readonly property var groups: {
        const map = {};
        const keys = [];
        for (const t of windows) {
            const id = appIdOf(t);
            const key = id || t.address;
            if (!map[key]) {
                map[key] = {
                    appId: id,
                    windows: []
                };
                keys.push(key);
            }
            map[key].windows.push(t);
        }
        const kept = order.filter(k => !!map[k]);
        return {
            map,
            keys: kept.concat(keys.filter(k => !kept.includes(k)))
        };
    }

    function move(key: string, to: int): void {
        const keys = groups.keys.filter(k => k !== key);
        keys.splice(Math.max(0, Math.min(to, keys.length)), 0, key);
        order = keys;
    }

    property bool dragging: false

    // Windows asking for attention, by address, until they're focused.
    property var urgent: ({})

    // An app's height for its number of windows.
    function heightFor(n: int): real {
        return cell + (Math.min(Math.max(n, 1), maxStack) - 1) * stackStep;
    }

    // Each app's top, by key, in taskbar order.
    readonly property var tops: {
        const out = {};
        let y = 0;
        for (const k of groups.keys) {
            out[k] = y;
            y += heightFor(groups.map[k].windows.length) + gap;
        }
        return out;
    }
    readonly property real fullHeight: {
        let h = 0;
        for (const k of groups.keys)
            h += heightFor(groups.map[k].windows.length) + gap;
        return groups.keys.length > 0 ? h - gap : 0;
    }

    // Where a dragged app (key, its centre at y) goes: after every other
    // app whose centre is above it, laid out without it.
    function slotFor(key: string, centre: real): int {
        let y = 0;
        let slot = 0;
        for (const k of groups.keys) {
            if (k === key)
                continue;
            const h = heightFor(groups.map[k].windows.length);
            if (y + h / 2 < centre)
                slot++;
            y += h + gap;
        }
        return slot;
    }

    implicitWidth: cell
    implicitHeight: maxHeight > 0 ? Math.min(fullHeight, maxHeight) : fullHeight

    // Window classes are filled in by Hyprland's client list.
    Component.onCompleted: Hyprland.refreshToplevels()

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            const name = event.name;
            if (["openwindow", "closewindow", "movewindowv2", "windowtitlev2"].includes(name))
                Hyprland.refreshToplevels();
            if (name === "urgent") {
                const u = Object.assign({}, root.urgent);
                u[root.bare(event.data)] = true;
                root.urgent = u;
            } else if (name === "activewindowv2" || name === "closewindow") {
                const address = root.bare(event.data.split(",")[0]);
                if (root.urgent[address]) {
                    const u = Object.assign({}, root.urgent);
                    delete u[address];
                    root.urgent = u;
                }
                // The focus history (for "the last used one").
                if (name === "activewindowv2")
                    Hyprland.refreshToplevels();
            }
        }
    }

    function bare(address: string): string {
        return address.replace(/^0x/, "");
    }

    function hex(address: string): string {
        return address.startsWith("0x") ? address : `0x${address}`;
    }

    // Lua calls for each window, in one go.
    function call(fn: string, wins: var): void {
        if (!wins.length)
            return;
        Quickshell.execDetached(["hyprctl", "eval", wins.map(w => `${fn}('${hex(w.address)}')`).join("; ")]);
    }

    function entryOf(appId: string): var {
        DesktopEntries.applications.values;
        return appId ? DesktopEntries.heuristicLookup(appId) : null;
    }

    function newWindow(appId: string): void {
        const entry = entryOf(appId);
        if (entry)
            Apps.launch(entry);
    }

    // Least focus history id: the last used.
    function byRecent(wins: var): var {
        return wins.slice().sort((a, b) => (a.lastIpcObject?.focusHistoryID ?? 1e9) - (b.lastIpcObject?.focusHistoryID ?? 1e9));
    }

    function clickApp(wins: var, active: bool): void {
        if (wins.length === 1) {
            call("kirin_taskbar_activate", wins);
            return;
        }
        if (!active) {
            call("kirin_taskbar_focus", [byRecent(wins)[0]]);
            return;
        }
        // Active: the next of its windows (in the order they opened).
        const i = wins.findIndex(w => w.activated);
        call("kirin_taskbar_focus", [wins[(i + 1) % wins.length]]);
    }

    Flickable {
        id: view

        anchors.fill: parent
        clip: true
        interactive: !root.dragging && contentHeight > height + 1
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: root.fullHeight

        Item {
            id: column

            width: view.width
            height: root.fullHeight

            Repeater {
                model: ScriptModel {
                    values: root.groups.keys
                }

                Item {
                    id: app

                    required property string modelData
                    required property int index

                    readonly property var group: root.groups.map[modelData] ?? null
                    readonly property var wins: group?.windows ?? []
                    readonly property string appId: group?.appId ?? ""
                    readonly property bool active: wins.some(w => w.activated && !root.minimized(w))
                    readonly property bool allMinimized: wins.length > 0 && wins.every(w => root.minimized(w))
                    readonly property bool urgent: !active && wins.some(w => !!root.urgent[root.bare(w.address)])
                    readonly property string name: root.entryOf(appId)?.name || wins[0]?.title || appId

                    // Right click asked for the menu, in place of the previews.
                    property bool menuWanted: false
                    property bool dragging: false
                    property real dragY: 0

                    // Its windows' icons, the active one on top, then in
                    // the order they opened.
                    readonly property var stack: {
                        const list = wins.slice().sort((a, b) => (b.activated ? 1 : 0) - (a.activated ? 1 : 0));
                        return list.slice(0, root.maxStack);
                    }

                    y: dragging ? dragY : (root.tops[modelData] ?? 0)
                    z: dragging ? 1 : 0
                    width: root.cell
                    height: root.heightFor(wins.length)

                    Behavior on height {
                        Anim {
                            type: Anim.DefaultSpatial
                        }
                    }

                    Behavior on y {
                        enabled: !app.dragging

                        Anim {
                            type: Anim.DefaultSpatial
                        }
                    }

                    // The accent plate under the active app.
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        opacity: app.active ? 1 : 0
                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: Theme.m3primary
                            }
                            GradientStop {
                                position: 1
                                color: Theme.m3tertiary
                            }
                        }

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }

                    // Asking for attention: the accent plate, pulsing.
                    Rectangle {
                        id: attention

                        anchors.fill: parent
                        radius: width / 2
                        color: Theme.m3tertiary
                        opacity: 0
                        visible: app.urgent

                        SequentialAnimation on opacity {
                            running: app.urgent
                            loops: Animation.Infinite
                            alwaysRunToEnd: true

                            NumberAnimation {
                                from: 0
                                to: 0.55
                                duration: 650
                                easing.type: Easing.InOutSine
                            }
                            NumberAnimation {
                                from: 0.55
                                to: 0
                                duration: 650
                                easing.type: Easing.InOutSine
                            }
                        }
                    }

                    // Hovered (not the active one): a light plate.
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Theme.m3onSurface
                        opacity: (mouse.containsMouse || app.dragging) && !app.active ? 0.1 : 0

                        Behavior on opacity {
                            Anim {
                                type: Anim.FastEffects
                            }
                        }
                    }

                    // The stack: the app's own icon once per window,
                    // overlapping, the first on top; minimized windows'
                    // faded. Behind each, a disc in the bar's colour sets it
                    // off from the one below (not on the accent plate).
                    Item {
                        id: icons

                        anchors.horizontalCenter: parent.horizontalCenter
                        y: root.pad
                        width: root.iconSize
                        height: parent.height - root.pad * 2
                        scale: app.dragging ? 1.08 : 1

                        Behavior on scale {
                            Anim {
                                type: Anim.FastSpatial
                            }
                        }

                        Repeater {
                            model: app.stack

                            Item {
                                id: stacked

                                required property var modelData
                                required property int index

                                y: index * root.stackStep
                                z: app.stack.length - index
                                width: root.iconSize
                                height: root.iconSize

                                Behavior on y {
                                    Anim {
                                        type: Anim.DefaultSpatial
                                    }
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width + 4
                                    height: width
                                    radius: width / 2
                                    color: Theme.m3surface
                                    visible: app.stack.length > 1
                                    opacity: app.active ? 0 : 1

                                    Behavior on opacity {
                                        Anim {
                                            type: Anim.DefaultEffects
                                        }
                                    }
                                }

                                AppIcon {
                                    anchors.fill: parent
                                    themed: false
                                    appId: app.appId
                                    entry: root.entryOf(app.appId)
                                    opacity: root.minimized(stacked.modelData) ? 0.4 : 1

                                    Behavior on opacity {
                                        Anim {
                                            type: Anim.DefaultEffects
                                        }
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: mouse

                        property real startY: 0
                        property real startSceneY: 0
                        property bool moved: false

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        cursorShape: app.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                        onPressed: event => {
                            moved = false;
                            startY = app.y;
                            startSceneY = mapToItem(null, event.x, event.y).y;
                        }
                        onPositionChanged: event => {
                            if (!(pressedButtons & Qt.LeftButton))
                                return;
                            const dy = mapToItem(null, event.x, event.y).y - startSceneY;
                            if (!moved) {
                                if (Math.abs(dy) < Theme.sp(6) || root.groups.keys.length < 2)
                                    return;
                                moved = true;
                                card.close();
                                app.dragY = startY;
                                app.dragging = root.dragging = true;
                            }
                            app.dragY = Math.max(0, Math.min(root.fullHeight - app.height, startY + dy));
                            const to = root.slotFor(app.modelData, app.dragY + app.height / 2);
                            if (to !== app.index)
                                root.move(app.modelData, to);
                        }
                        onReleased: {
                            if (app.dragging)
                                app.dragging = root.dragging = false;
                        }
                        onCanceled: {
                            if (app.dragging)
                                app.dragging = root.dragging = false;
                        }
                        onClicked: event => {
                            if (moved)
                                return;
                            if (event.button === Qt.RightButton) {
                                app.menuWanted = true;
                                card.show();
                            } else if (event.button === Qt.MiddleButton) {
                                root.newWindow(app.appId);
                            } else {
                                root.clickApp(app.wins, app.active);
                            }
                        }
                    }

                    // The previews, or the menu.
                    BarCard {
                        id: card

                        owner: app
                        ownerHovered: mouse.containsMouse && !app.dragging
                        cardOffset: root.cardOffset
                        bounds: root.bounds
                        padding: Theme.sp(app.menuWanted ? 8 : 12)
                        onClosed: app.menuWanted = false

                        Item {
                            implicitWidth: app.menuWanted ? Theme.sp(220) : previews.implicitWidth
                            implicitHeight: app.menuWanted ? menu.implicitHeight : previews.implicitHeight

                            Previews {
                                id: previews

                                visible: !app.menuWanted
                                width: parent.width
                                wins: app.wins
                                shown: card.open && !app.menuWanted
                                onDone: card.close()
                            }

                            TaskMenu {
                                id: menu

                                visible: app.menuWanted
                                width: parent.width
                                name: app.name
                                appId: app.appId
                                wins: app.wins
                                allMinimized: app.allMinimized
                                onDone: card.close()
                            }
                        }
                    }
                }
            }
        }
    }

    // --- The hover card: a live preview of each window ------------------------

    component Previews: Flickable {
        id: list

        property var wins: []
        // Captures run only while the card is up.
        property bool shown: false
        signal done

        readonly property int thumbWidth: Theme.sp(240)
        readonly property real maxListHeight: Math.max(Theme.sp(240), (root.bounds?.height ?? 800) * 0.75)

        implicitWidth: thumbWidth
        implicitHeight: Math.min(previewColumn.implicitHeight, maxListHeight)
        height: implicitHeight
        contentWidth: width
        contentHeight: previewColumn.implicitHeight
        clip: true
        interactive: contentHeight > height + 1
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: previewColumn

            width: list.width
            spacing: Theme.sp(12)

            Repeater {
                model: ScriptModel {
                    values: list.wins
                    objectProp: "address"
                }

                Item {
                    id: preview

                    required property var modelData
                    readonly property bool isMinimized: root.minimized(modelData)
                    // The window's shape, from its size.
                    readonly property real aspect: {
                        const s = modelData.lastIpcObject?.size;
                        return s && s[0] > 0 && s[1] > 0 ? s[1] / s[0] : 0.6;
                    }
                    readonly property int thumbHeight: Math.round(Math.max(Theme.sp(90), Math.min(Theme.sp(180), list.thumbWidth * aspect)))

                    width: previewColumn.width
                    height: header.height + Theme.sp(6) + thumbHeight

                    // Icon, title, ×.
                    Item {
                        id: header

                        width: parent.width
                        height: Math.max(Theme.sp(24), title.implicitHeight)

                        AppIcon {
                            id: smallIcon

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(16 * Theme.fontScale)
                            height: width
                            themed: false
                            appId: root.appIdOf(preview.modelData)
                            entry: root.entryOf(appId)
                        }

                        StyledText {
                            id: title

                            anchors.left: smallIcon.right
                            anchors.leftMargin: Theme.sp(8)
                            anchors.right: closeButton.left
                            anchors.rightMargin: Theme.sp(4)
                            anchors.verticalCenter: parent.verticalCenter
                            text: preview.modelData.title || root.appIdOf(preview.modelData)
                            elide: Text.ElideRight
                            font.pixelSize: Theme.size.labelMedium
                            font.weight: preview.modelData.activated ? Font.DemiBold : Font.Normal
                            color: Theme.m3onSurface
                        }

                        Rectangle {
                            id: closeButton

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.sp(24)
                            height: width
                            radius: width / 2
                            color: "transparent"
                            opacity: thumbMouse.containsMouse || closeLayer.containsMouse ? 1 : 0.55

                            Behavior on opacity {
                                Anim {
                                    type: Anim.FastEffects
                                }
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "close"
                                size: 16
                                color: Theme.m3onSurfaceVariant
                            }

                            StateLayer {
                                id: closeLayer

                                onClicked: root.call("kirin_taskbar_close", [preview.modelData])
                            }
                        }
                    }

                    ClippingRectangle {
                        id: thumb

                        anchors.top: header.bottom
                        anchors.topMargin: Theme.sp(6)
                        width: parent.width
                        height: preview.thumbHeight
                        radius: Theme.rounding.medium
                        color: Theme.m3surfaceContainerHigh
                        border.width: preview.modelData.activated ? 2 : 0
                        border.color: Theme.m3primary

                        ScreencopyView {
                            id: capture

                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, parent.width)
                            height: Math.min(implicitHeight, parent.height)
                            captureSource: list.shown ? preview.modelData.wayland ?? null : null
                            live: list.shown
                            constraintSize: Qt.size(thumb.width, thumb.height)
                        }

                        // Nothing captured (yet): the app's icon.
                        AppIcon {
                            anchors.centerIn: parent
                            width: Math.round(40 * Theme.fontScale)
                            height: width
                            visible: !capture.hasContent
                            themed: false
                            appId: root.appIdOf(preview.modelData)
                            entry: root.entryOf(appId)
                        }

                        // Minimized: a hint on top.
                        Rectangle {
                            visible: preview.isMinimized
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: Theme.sp(6)
                            width: Theme.sp(24)
                            height: width
                            radius: width / 2
                            color: Qt.alpha(Theme.m3surface, 0.85)

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "minimize"
                                size: 16
                                color: Theme.m3onSurfaceVariant
                            }
                        }

                        // Hover: a light veil.
                        Rectangle {
                            anchors.fill: parent
                            color: Theme.m3onSurface
                            opacity: thumbMouse.pressed ? 0.12 : thumbMouse.containsMouse ? 0.06 : 0

                            Behavior on opacity {
                                Anim {
                                    type: Anim.FastEffects
                                }
                            }
                        }

                        MouseArea {
                            id: thumbMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: event => {
                                if (event.button === Qt.MiddleButton) {
                                    root.call("kirin_taskbar_close", [preview.modelData]);
                                } else {
                                    root.call("kirin_taskbar_focus", [preview.modelData]);
                                    list.done();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- The right click menu ---------------------------------------------------

    component TaskMenu: Column {
        id: taskMenu

        property string name
        property string appId
        property var wins: []
        property bool allMinimized: false
        signal done

        readonly property bool several: wins.length > 1

        spacing: 0

        // The app's name.
        Item {
            width: parent.width
            height: Math.max(36, heading.implicitHeight + Theme.sp(12))

            StyledText {
                id: heading

                anchors.left: parent.left
                anchors.leftMargin: Theme.sp(8)
                anchors.right: parent.right
                anchors.rightMargin: Theme.sp(8)
                anchors.verticalCenter: parent.verticalCenter
                text: taskMenu.name
                font.pixelSize: Theme.size.labelMedium
                font.weight: Font.Medium
                color: Theme.m3onSurfaceVariant
                elide: Text.ElideRight
            }
        }

        MenuEntry {
            visible: !!root.entryOf(taskMenu.appId)
            icon: "open_in_new"
            text: "New window"
            onActivated: {
                root.newWindow(taskMenu.appId);
                taskMenu.done();
            }
        }

        MenuEntry {
            icon: taskMenu.allMinimized ? "open_in_full" : "minimize"
            text: taskMenu.allMinimized ? (taskMenu.several ? "Restore all" : "Restore") : (taskMenu.several ? "Minimize all" : "Minimize")
            onActivated: {
                if (taskMenu.allMinimized)
                    root.call("kirin_taskbar_focus", taskMenu.wins);
                else
                    root.call("kirin_taskbar_minimize", taskMenu.wins);
                taskMenu.done();
            }
        }

        Item {
            width: parent.width
            height: Theme.sp(9)

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.sp(8)
                width: parent.width - Theme.sp(16)
                height: 1
                color: Theme.m3outlineVariant
            }
        }

        MenuEntry {
            icon: "close"
            text: taskMenu.several ? `Close all windows (${taskMenu.wins.length})` : "Close window"
            danger: true
            onActivated: {
                root.call("kirin_taskbar_close", taskMenu.wins);
                taskMenu.done();
            }
        }
    }

    component MenuEntry: Rectangle {
        id: entry

        property string icon
        property string text
        property bool danger: false
        signal activated

        width: parent?.width ?? 0
        height: Math.max(36, label.implicitHeight + Theme.sp(14))
        radius: Theme.rounding.small
        color: "transparent"

        MaterialIcon {
            id: entryIcon

            anchors.left: parent.left
            anchors.leftMargin: Theme.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            text: entry.icon
            size: 18
            color: entry.danger ? Theme.m3error : Theme.m3onSurfaceVariant
        }

        StyledText {
            id: label

            anchors.left: entryIcon.right
            anchors.leftMargin: Theme.sp(10)
            anchors.right: parent.right
            anchors.rightMargin: Theme.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            text: entry.text
            elide: Text.ElideRight
            color: entry.danger ? Theme.m3error : Theme.m3onSurface
        }

        StateLayer {
            onClicked: entry.activated()
        }
    }
}
