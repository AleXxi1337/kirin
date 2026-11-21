pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.components
import qs.services

// On-screen display for the brightness and volume keys: a card at the right
// edge of the primary monitor with a vertical slider for each thing the keys
// changed (brightness, microphone, speakers), only those. Shown only through
// IPC from the key bindings (hypr/modules/keybindings.lua), so changes made
// elsewhere don't bring it up:
//   qs -c kirin ipc call osd brightness|mic|volume
// Stays while hovered; the sliders can be dragged and the icons clicked
// (mute; light/dark mode for brightness) like in the bar's cards.
Scope {
    id: root

    // Columns, top to bottom of the request: left to right in the card.
    readonly property var kinds: ["brightness", "mic", "volume"]

    property bool open: false
    // Kinds shown; one is added by each key press while the card is up.
    property var active: []
    property bool hovered: false

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    function show(kind: string): void {
        if (!kinds.includes(kind))
            return;
        if (kind === "brightness" && Backlight.pending < 0)
            Backlight.reload();
        if (kind === "volume")
            SoundFx.trigger("volume");
        if (!open)
            active = [];
        if (!active.includes(kind))
            active = active.concat([kind]);
        open = true;
        hide.restart();
    }

    PwObjectTracker {
        objects: [root.sink, root.source]
    }

    IpcHandler {
        target: "osd"

        // Not one show(kind): "qs ipc call osd show …" clashes with qs's own
        // "show" subcommand.
        function brightness(): void {
            root.show("brightness");
        }

        function volume(): void {
            root.show("volume");
        }

        function mic(): void {
            root.show("mic");
        }

        // Brightness keys: change it smoothly and show it. `percent` is
        // signed, e.g. 5 or -5.
        function brightnessStep(percent: int): void {
            Backlight.step(percent / 100);
            root.show("brightness");
        }
    }

    Timer {
        id: hide

        interval: 1800
        onTriggered: {
            if (root.hovered)
                restart();
            else
                root.open = false;
        }
    }

    // Read the brightness often while it's shown (dragging, keys held down).
    onOpenChanged: Backlight.watchers += open ? 1 : -1

    Variants {
        model: Quickshell.screens.filter(s => s.name === Monitors.primary?.name)

        PanelWindow {
            id: window

            required property ShellScreen modelData

            readonly property real columnWidth: Theme.sp(64)
            readonly property real pad: HyprLook.shadowExtent + Theme.sp(16)

            screen: modelData
            color: "transparent"
            // Only the right edge: centred vertically.
            anchors.right: true
            implicitWidth: columnWidth * root.kinds.length + Theme.sp(16) + pad * 2 + HyprLook.gapsRight * 2
            implicitHeight: card.implicitHeight + pad * 2
            // Stays mapped until the card has slid out.
            visible: root.open || card.opacity > 0

            WlrLayershell.namespace: "kirin-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // Only the card takes input.
            mask: Region {
                item: card
            }

            WindowShadow {
                target: card
            }

            Rectangle {
                id: card

                // Columns grow in and out, so the width follows them.
                implicitWidth: columns.implicitWidth + Theme.sp(16)
                implicitHeight: columns.implicitHeight + Theme.sp(24)
                width: implicitWidth
                height: implicitHeight
                anchors.verticalCenter: parent.verticalCenter
                // From the right edge: three times Hyprland's outer gaps, in
                // line with the notifications and the media player.
                x: parent.width - width - HyprLook.gapsRight * 3 + (root.open ? 0 : Theme.sp(24))
                radius: HyprLook.rounding
                color: Theme.m3surface
                border.width: HyprLook.borderSize
                border.color: Qt.alpha(Theme.m3outlineVariant, 0x66 / 255)
                clip: true
                opacity: root.open ? 1 : 0

                Behavior on x {
                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }
                Behavior on opacity {
                    Anim {
                        type: Anim.FastEffects
                    }
                }

                HoverHandler {
                    onHoveredChanged: root.hovered = hovered
                }

                Row {
                    id: columns

                    anchors.centerIn: parent

                    Repeater {
                        model: root.kinds

                        // One slider with its value above and its icon below.
                        // Folds to zero width while not active.
                        Item {
                            id: column

                            required property string modelData
                            readonly property bool brightness: modelData === "brightness"
                            readonly property bool mic: modelData === "mic"
                            readonly property PwNode node: mic ? root.source : modelData === "volume" ? root.sink : null
                            readonly property bool muted: node?.audio?.muted ?? false
                            readonly property real value: brightness ? Backlight.level : node?.audio?.volume ?? 0
                            readonly property bool usable: brightness ? Backlight.available : !!node?.audio
                            property real shown: root.active.includes(modelData) && usable ? 1 : 0

                            implicitWidth: Math.round(window.columnWidth * shown)
                            implicitHeight: content.implicitHeight
                            visible: shown > 0
                            clip: true

                            Behavior on shown {
                                Anim {
                                    type: Anim.DefaultSpatial
                                }
                            }

                            function setValue(v: real): void {
                                hide.restart();
                                if (brightness) {
                                    Backlight.setLevel(v);
                                } else if (node?.audio) {
                                    node.audio.volume = Math.max(0, Math.min(1, v));
                                    if (node.audio.muted && v > 0)
                                        node.audio.muted = false;
                                }
                            }

                            Column {
                                id: content

                                anchors.horizontalCenter: parent.horizontalCenter
                                width: window.columnWidth
                                spacing: Theme.sp(8)
                                opacity: column.shown

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Math.round(column.value * 100)
                                    font.pixelSize: Theme.size.labelLarge
                                    font.weight: Font.Medium
                                    font.features: {
                                        "tnum": 1
                                    }
                                    color: column.muted ? Theme.m3onSurfaceVariant : Theme.m3onSurface
                                }

                                // ValueSlider is horizontal: turned a quarter, so up is more.
                                Item {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 44
                                    height: Theme.sp(180)

                                    ValueSlider {
                                        anchors.centerIn: parent
                                        width: parent.height
                                        height: parent.width
                                        rotation: -90
                                        from: column.brightness ? 0.01 : 0
                                        to: 1
                                        value: Math.min(1, column.value)
                                        opacity: column.muted ? 0.5 : 1
                                        onMoved: value => column.setValue(value)
                                    }
                                }

                                // Mute (light/dark mode for brightness), as in the bar.
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 40
                                    height: 40
                                    radius: 20
                                    color: column.muted ? Theme.m3secondaryContainer : "transparent"

                                    Behavior on color {
                                        CAnim {}
                                    }

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: {
                                            if (column.brightness)
                                                return Config.appearance.mode !== "light" ? "dark_mode" : "light_mode";
                                            if (column.mic)
                                                return column.muted ? "mic_off" : "mic";
                                            const v = column.value;
                                            if (column.muted || v <= 0.001)
                                                return "volume_off";
                                            return v < 0.34 ? "volume_mute" : v < 0.67 ? "volume_down" : "volume_up";
                                        }
                                        fill: true
                                        size: 22
                                        color: column.muted ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                                    }

                                    StateLayer {
                                        onClicked: {
                                            hide.restart();
                                            if (column.brightness)
                                                Config.appearance.mode = Config.appearance.mode !== "light" ? "light" : "dark";
                                            else if (column.node?.audio)
                                                column.node.audio.muted = !column.node.audio.muted;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
