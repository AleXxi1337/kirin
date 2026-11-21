pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import qs.components
import qs.services

// The Alt+Tab picker, as on Windows: the windows, most recently used first,
// each a live preview with its app's icon and title, the selected one on the
// accent plate. Driven by Hyprland's Lua (hypr/modules/winmode.lua,
// "Alt+Tab"), which has the keys: a custom event, "kirinswitch show <index>
// <address,...>" (index from 1) or "kirinswitch hide". Shown a moment after
// Alt+Tab, so a quick one just switches. A click on a window brings it up.
// On the monitor in focus, in the middle; rows wrap past 80% of its width.
// Sizes: 1.5 times the taskbar previews'; the titles in kirin's font size.
Scope {
    id: root

    property var addresses: []
    // From 0.
    property int index: 0
    property bool wanted: false
    property bool shown: false

    function bare(address: string): string {
        return String(address).replace(/^0x/, "");
    }

    function toplevelOf(address: string): var {
        const a = bare(address);
        return Hyprland.toplevels.values.find(t => bare(t.address) === a) ?? null;
    }

    function pick(address: string): void {
        Quickshell.execDetached(["hyprctl", "eval", `kirin_switch_pick('${address}')`]);
    }

    Timer {
        id: delay

        interval: 120
        onTriggered: root.shown = root.wanted
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name !== "custom")
                return;
            const parts = event.data.trim().split(/\s+/);
            if (parts[0] !== "kirinswitch")
                return;
            if (parts[1] === "show" && parts.length >= 4) {
                root.addresses = parts[3].split(",");
                root.index = Number(parts[2]) - 1;
                if (!root.wanted) {
                    root.wanted = true;
                    Hyprland.refreshToplevels();
                    delay.restart();
                }
            } else {
                root.wanted = false;
                root.shown = false;
                delay.stop();
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData
            readonly property bool here: root.shown && Hyprland.focusedMonitor?.name === modelData.name

            readonly property int tileWidth: Theme.sp(360)
            readonly property int previewHeight: Theme.sp(225)
            readonly property int spacing: Theme.sp(18)
            readonly property int padding: Theme.sp(24)
            readonly property real maxWidth: modelData.width * 0.8
            // Tiles in a row, as many as fit.
            readonly property int perRow: Math.max(1, Math.min(root.addresses.length, Math.floor((maxWidth - padding * 2 + spacing) / (tileWidth + spacing))))

            screen: modelData
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            visible: here || card.opacity > 0

            WlrLayershell.namespace: "kirin-switcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            // The keys stay with Hyprland's binds (Alt held).
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {
                item: card
            }

            WindowShadow {
                target: card
            }

            Rectangle {
                id: card

                anchors.centerIn: parent
                width: tiles.width + win.padding * 2
                height: tiles.height + win.padding * 2
                radius: HyprLook.rounding + win.padding / 2
                color: Theme.m3surface
                border.width: HyprLook.borderSize
                border.color: Qt.alpha(Theme.m3outlineVariant, 0x66 / 255)
                opacity: win.here ? 1 : 0
                scale: win.here ? 1 : 0.96

                Behavior on opacity {
                    Anim {
                        type: Anim.FastEffects
                    }
                }
                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                Flow {
                    id: tiles

                    anchors.centerIn: parent
                    width: win.perRow * win.tileWidth + (win.perRow - 1) * win.spacing
                    spacing: win.spacing

                    Repeater {
                        model: root.addresses

                        Rectangle {
                            id: tile

                            required property string modelData
                            required property int index
                            readonly property var toplevel: root.toplevelOf(modelData)
                            readonly property string appId: toplevel?.wayland?.appId || toplevel?.lastIpcObject?.class || ""
                            readonly property bool selected: index === root.index
                            readonly property bool minimized: toplevel?.workspace?.name === "special:minimized"

                            width: win.tileWidth
                            height: column.height + Theme.sp(24)
                            radius: HyprLook.rounding
                            color: selected ? Qt.alpha(Theme.m3primary, 0.16) : tileMouse.containsMouse ? Qt.alpha(Theme.m3onSurface, 0.06) : "transparent"
                            border.width: selected ? 3 : 0
                            border.color: Theme.m3primary

                            Behavior on color {
                                CAnim {}
                            }

                            Column {
                                id: column

                                anchors.horizontalCenter: parent.horizontalCenter
                                y: Theme.sp(12)
                                width: parent.width - Theme.sp(24)
                                spacing: Theme.sp(12)

                                ClippingRectangle {
                                    width: parent.width
                                    height: win.previewHeight
                                    radius: Math.max(4, HyprLook.rounding - Theme.sp(6))
                                    color: Theme.m3surfaceContainerHigh

                                    ScreencopyView {
                                        id: capture

                                        anchors.centerIn: parent
                                        width: Math.min(implicitWidth, parent.width)
                                        height: Math.min(implicitHeight, parent.height)
                                        captureSource: win.here ? tile.toplevel?.wayland ?? null : null
                                        live: win.here
                                        constraintSize: Qt.size(parent.width, parent.height)
                                    }

                                    // Nothing captured (minimized, or not yet):
                                    // the app's icon.
                                    AppIcon {
                                        anchors.centerIn: parent
                                        width: Math.round(72 * Theme.fontScale)
                                        height: width
                                        visible: !capture.hasContent
                                        themed: false
                                        appId: tile.appId
                                        entry: {
                                            DesktopEntries.applications.values;
                                            return tile.appId ? DesktopEntries.heuristicLookup(tile.appId) : null;
                                        }
                                    }
                                }

                                Row {
                                    width: parent.width
                                    spacing: Theme.sp(12)

                                    AppIcon {
                                        id: smallIcon

                                        width: Math.round(27 * Theme.fontScale)
                                        height: width
                                        anchors.verticalCenter: parent.verticalCenter
                                        themed: false
                                        appId: tile.appId
                                        entry: {
                                            DesktopEntries.applications.values;
                                            return tile.appId ? DesktopEntries.heuristicLookup(tile.appId) : null;
                                        }
                                        opacity: tile.minimized ? 0.5 : 1
                                    }

                                    StyledText {
                                        width: parent.width - smallIcon.width - parent.spacing
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tile.toplevel?.title || tile.appId
                                        elide: Text.ElideRight
                                        // The font size from kirin's settings, as text elsewhere.
                                        font.pixelSize: Theme.size.bodyMedium
                                        font.weight: tile.selected ? Font.DemiBold : Font.Normal
                                        color: Theme.m3onSurface
                                    }
                                }
                            }

                            MouseArea {
                                id: tileMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.pick(tile.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
