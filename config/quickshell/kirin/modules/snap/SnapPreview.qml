pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.components
import qs.services

// Where a window dragged to a screen edge or corner will go when let go
// (windows mode: hypr/modules/winmode.lua, "Snapping"). Hyprland's Lua
// sends a custom event: "kirinsnap show <monitor> x y w h" (global
// coordinates, titlebar included) or "kirinsnap hide".
// A plate in the accent colour, rounded as windows are; it grows in, flows
// from one zone to the next, and fades out.
Scope {
    id: root

    property string monitor: ""
    // Global coordinates.
    property rect target: Qt.rect(0, 0, 0, 0)
    property bool shown: false

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name !== "custom")
                return;
            const parts = event.data.trim().split(/\s+/);
            if (parts[0] !== "kirinsnap")
                return;
            if (parts[1] === "show" && parts.length >= 7) {
                root.monitor = parts[2];
                root.target = Qt.rect(Number(parts[3]), Number(parts[4]), Number(parts[5]), Number(parts[6]));
                root.shown = true;
            } else {
                root.shown = false;
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData
            readonly property bool here: root.shown && root.monitor === modelData.name

            screen: modelData
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            visible: here || plate.opacity > 0

            WlrLayershell.namespace: "kirin-snap"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // Never takes input: the drag goes on under it.
            mask: Region {}

            Rectangle {
                id: plate

                // Moves between zones while shown; put in place at once when
                // it appears.
                readonly property bool animating: opacity > 0.01

                x: root.target.x - win.modelData.x
                y: root.target.y - win.modelData.y
                width: root.target.width
                height: root.target.height
                radius: HyprLook.rounding
                color: Qt.alpha(Theme.m3primary, 0.16)
                border.width: 2
                border.color: Qt.alpha(Theme.m3primary, 0.55)
                opacity: win.here ? 1 : 0
                scale: win.here ? 1 : 0.95

                Behavior on x {
                    enabled: plate.animating

                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }
                Behavior on y {
                    enabled: plate.animating

                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }
                Behavior on width {
                    enabled: plate.animating

                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }
                Behavior on height {
                    enabled: plate.animating

                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }
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
            }
        }
    }
}
