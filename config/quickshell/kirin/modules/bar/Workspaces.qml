pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.components
import qs.services

// Workspaces in the middle of the bar: each one with windows is a stack of
// its apps' icons, overlapping. The current one fans out (the icons move
// apart) over a plate with the accent gradient, which slides from one
// workspace to the next. One icon per window. An empty current workspace
// shows its number.
// Click: go there. Scroll: the next or previous one.
//
// No taller than `maxHeight` (the room the bar has between the logo and the
// modules below): past it, the column scrolls inside, keeping the current
// workspace in the middle of the view, and fades out at an edge with more
// beyond it.
Item {
    id: root

    // 0: no limit.
    property real maxHeight: 0
    readonly property real fullHeight: groups.implicitHeight + platePadV * 2

    readonly property int iconSize: Math.round(22 * Theme.fontScale)
    // Plate around the current workspace's icons.
    readonly property int platePad: Theme.sp(3)
    // Above and below the icons a bit more than at the sides: a tall,
    // narrow plate.
    readonly property int platePadV: platePad + 2

    // Normal workspaces of every monitor (not special ones like the
    // scratchpad or minimized windows) with windows, and the focused one,
    // in order. The bar is on the primary monitor only; workspaces of the
    // monitors not in focus are shown greyed out, and focusing another
    // monitor turns its own up instead.
    readonly property var workspaces: Hyprland.workspaces.values.filter(w => w.id > 0 && (w.toplevels.values.length > 0 || w === Hyprland.focusedWorkspace)).sort((a, b) => a.id - b.id)

    // The current workspace's group, for the plate.
    property Item current: null

    function goTo(target: string): void {
        Quickshell.execDetached(["hyprctl", "eval", `hl.dispatch(hl.dsp.focus({ workspace = ${target} }))`]);
    }

    implicitWidth: iconSize + platePad * 2
    implicitHeight: maxHeight > 0 ? Math.min(fullHeight, maxHeight) : fullHeight

    // Window classes are filled in by Hyprland's client list.
    Component.onCompleted: Hyprland.refreshToplevels()

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (["openwindow", "closewindow", "movewindowv2", "windowtitlev2"].includes(event.name))
                Hyprland.refreshToplevels();
        }
    }

    Flickable {
        id: view

        // Where it scrolls to: the current workspace (its plate, where it's
        // going) in the middle, within the ends.
        readonly property real wantY: Math.max(0, Math.min(plate.targetY + plate.targetHeight / 2 - height / 2, contentHeight - height))

        anchors.fill: parent
        clip: true
        // The wheel goes to the next workspace (below), not a scroll.
        interactive: false
        contentWidth: width
        contentHeight: root.fullHeight

        Component.onCompleted: contentY = wantY

        // Follows as the plate does, frame by frame: the target moves while
        // the current workspace fans out.
        FrameAnimation {
            running: Math.abs(view.contentY - view.wantY) > 0.2
            onTriggered: {
                // Time constant 90 ms.
                const k = 1 - Math.exp(-frameTime / 0.09);
                view.contentY += (view.wantY - view.contentY) * k;
                if (Math.abs(view.contentY - view.wantY) <= 0.2)
                    view.contentY = view.wantY;
            }
        }

        // The plate. Follows the current group frame by frame (that group
        // grows while this moves, so an animation towards it would restart
        // every frame and lag).
        Rectangle {
            id: plate

            property real targetY: root.current ? root.current.y + groups.y - root.platePadV : 0
            property real targetHeight: root.current ? root.current.height + root.platePadV * 2 : 0
            // Not bound: set by the follower; jumps there the first time.
            property real shownY: 0
            property real shownHeight: 0

            onTargetHeightChanged: {
                if (shownHeight === 0) {
                    shownY = targetY;
                    shownHeight = targetHeight;
                }
            }

            visible: root.current !== null
            x: 0
            width: root.width
            y: shownY
            height: shownHeight
            radius: width / 2
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

            FrameAnimation {
                running: Math.abs(plate.shownY - plate.targetY) > 0.2 || Math.abs(plate.shownHeight - plate.targetHeight) > 0.2
                onTriggered: {
                    // Time constant 60 ms.
                    const k = 1 - Math.exp(-frameTime / 0.06);
                    plate.shownY += (plate.targetY - plate.shownY) * k;
                    plate.shownHeight += (plate.targetHeight - plate.shownHeight) * k;
                    if (Math.abs(plate.shownY - plate.targetY) <= 0.2)
                        plate.shownY = plate.targetY;
                    if (Math.abs(plate.shownHeight - plate.targetHeight) <= 0.2)
                        plate.shownHeight = plate.targetHeight;
                }
            }
        }

        Column {
            id: groups

            anchors.horizontalCenter: parent.horizontalCenter
            y: root.platePadV
            spacing: root.platePadV * 2 + Theme.sp(4)

            Repeater {
                model: ScriptModel {
                    values: root.workspaces
                }

                Item {
                    id: group

                    required property var modelData
                    // The focused workspace: fanned out on the plate.
                    readonly property bool active: modelData === Hyprland.focusedWorkspace
                    // On a monitor that isn't in focus: greyed out.
                    readonly property bool away: modelData.monitor !== Hyprland.focusedMonitor
                    // App id of each of its windows (two kitty windows: two
                    // icons), in window order.
                    readonly property var apps: modelData.toplevels.values.map(t => t.wayland?.appId || t.lastIpcObject?.class || "")
                    // 0 stacked … 1 fanned out.
                    property real spread: active ? 1 : 0
                    // Distance between icon tops: overlapping when stacked.
                    readonly property real step: root.iconSize * (0.45 + 0.55 * spread) + Theme.sp(6) * spread

                    width: root.iconSize
                    height: apps.length > 0 ? root.iconSize + (apps.length - 1) * step : root.iconSize

                    Behavior on spread {
                        Anim {
                            type: Anim.DefaultSpatial
                        }
                    }

                    onActiveChanged: {
                        if (active)
                            root.current = group;
                        else if (root.current === group)
                            root.current = null;
                    }
                    Component.onCompleted: {
                        if (active)
                            root.current = group;
                    }
                    Component.onDestruction: {
                        if (root.current === group)
                            root.current = null;
                    }

                    Repeater {
                        model: group.apps

                        Item {
                            id: iconEntry

                            required property string modelData
                            required property int index
                            // Looked up again once the desktop entries are read.
                            readonly property var desktop: {
                                DesktopEntries.applications.values;
                                return DesktopEntries.heuristicLookup(modelData);
                            }

                            y: index * group.step
                            // The first window's app on top.
                            z: group.apps.length - index
                            width: root.iconSize
                            height: root.iconSize

                            // Behind each symbol, a disc in the bar's colour hides
                            // the one below where they overlap; not needed once
                            // they're fanned out.
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + 4
                                height: width
                                radius: width / 2
                                color: Theme.m3surface
                                opacity: 1 - group.spread
                            }

                            // The app as a filled symbol, no background: on the
                            // gradient in the colour that reads on it.
                            SymbolIcon {
                                anchors.fill: parent
                                entry: iconEntry.desktop
                                appId: iconEntry.modelData
                                color: group.active ? Theme.m3onPrimary : group.away ? Theme.m3outline : Theme.m3onSurface
                                opacity: group.away ? 0.55 : 1

                                Behavior on color {
                                    CAnim {}
                                }
                                Behavior on opacity {
                                    Anim {
                                        type: Anim.DefaultEffects
                                    }
                                }
                            }
                        }
                    }

                    // An empty current workspace: its number.
                    StyledText {
                        visible: group.apps.length === 0
                        anchors.centerIn: parent
                        text: group.modelData.id
                        font.pixelSize: Theme.size.labelLarge
                        font.weight: Font.Bold
                        color: group.active ? Theme.m3onPrimary : Theme.m3onSurfaceVariant
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -root.platePad
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.goTo(String(group.modelData.id))
                    }
                }
            }
        }
    }

    // More above or below: the edge fades into the bar.
    component Fade: Rectangle {
        required property bool atTop
        required property bool shown

        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.sp(36)
        opacity: shown ? 1 : 0
        gradient: Gradient {
            GradientStop {
                position: 0
                color: atTop ? Theme.m3surface : "transparent"
            }
            GradientStop {
                position: 1
                color: atTop ? "transparent" : Theme.m3surface
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Fade {
        anchors.top: parent.top
        atTop: true
        shown: view.contentY > 1
    }

    Fade {
        anchors.bottom: parent.bottom
        atTop: false
        shown: view.contentY < view.contentHeight - view.height - 1
    }

    // Scrolling over the workspaces: the next or previous one.
    // A wheel notch is 120; touchpads send small steps, added up.
    WheelHandler {
        property real sum: 0

        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            sum += event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
            if (Math.abs(sum) >= 120) {
                root.goTo(sum < 0 ? "\"e+1\"" : "\"e-1\"");
                sum = 0;
            }
        }
    }
}
