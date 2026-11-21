pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.components
import qs.services

// Sound output (PipeWire): one icon in the bar; scrolling over it changes the
// volume, clicking mutes. Hovering slides out a card with the output device
// and its volume; clicking the card expands it with output and microphone
// pickers, the microphone's volume and a volume for each app playing sound.
Item {
    id: root

    property real cardOffset: 0
    // The card stays within this item (the bar).
    property Item bounds: null

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioSink)
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property var sources: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioSource)
    // Apps playing sound.
    // Every sound stream, all tracked (a node's properties come only while
    // it's tracked)…
    readonly property var allStreams: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioOutStream)
    // …and the apps among them: kirin's own sounds have their own row.
    // Known by the node's name, there from the start, and listed only once
    // ready: a stream's properties come a moment after it, and a sound
    // flashed in meanwhile, jolting the card.
    readonly property var streams: allStreams.filter(n => n.ready && n.name !== SoundFx.streamName && n.properties["application.name"] !== SoundFx.streamName)

    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    property bool expanded: false

    // Volume and mute only update for tracked nodes.
    PwObjectTracker {
        objects: [root.sink, ...root.sinks, root.source, ...root.sources, ...root.allStreams]
    }

    // Up to 100% by scrolling and dragging; a volume already above that (set
    // elsewhere) is left alone until lowered.
    function setVolume(node: var, value: real): void {
        if (!node?.audio)
            return;
        const current = node.audio.volume;
        const max = Math.max(1, value < current ? 0 : current);
        node.audio.volume = Math.max(0, Math.min(max, value));
        if (value > current && node.audio.muted)
            node.audio.muted = false;
    }

    function volumeIcon(node: var): string {
        const v = node?.audio?.volume ?? 0;
        if (node?.audio?.muted || v <= 0.001)
            return "volume_off";
        return v < 0.34 ? "volume_mute" : v < 0.67 ? "volume_down" : "volume_up";
    }

    function percent(node: var): string {
        return `${Math.round((node?.audio?.volume ?? 0) * 100)}%`;
    }

    // App name and icon from the stream's properties.
    function appName(node: var): string {
        const p = node?.properties ?? {};
        return p["application.name"] || node?.description || node?.name || "App";
    }

    function appIcon(node: var): string {
        const p = node?.properties ?? {};
        for (const name of [p["application.icon-name"], p["application.process.binary"], (p["application.name"] ?? "").toLowerCase()])
            if (name) {
                const path = Quickshell.iconPath(name, true);
                if (path)
                    return path;
            }
        return "";
    }

    visible: !!sink
    implicitWidth: icon.restWidth
    implicitHeight: icon.restHeight

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: root.volumeIcon(root.sink)
        fill: true
        size: 20
        color: root.muted ? Theme.m3onSurfaceVariant : Theme.m3onSurface
        opacity: root.muted ? 0.6 : 1
        grow: card.open ? 1.1 : 1
    }


    MouseArea {
        id: mouse

        // Scrolling accumulates, so touchpads change it smoothly and a mouse
        // wheel notch is 5%.
        anchors.fill: parent
        anchors.margins: -Theme.sp(8)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        // Left or middle: mute.
        onClicked: {
            if (root.sink?.audio)
                root.sink.audio.muted = !root.sink.audio.muted;
        }
        onWheel: event => {
            // The other way round: wheel (or fingers) down, up a step.
            const delta = -(event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x);
            root.setVolume(root.sink, root.volume + delta / 120 * 0.05);
        }
    }

    // Mute button and slider: for the device and for each app.
    component VolumeControl: Item {
        id: control

        required property var node
        property bool compact: false
        // Microphone icons instead of speaker ones.
        property bool mic: false

        implicitHeight: compact ? 32 : 44

        Rectangle {
            id: muteButton

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: control.compact ? 32 : 40
            height: width
            radius: width / 2
            color: control.node?.audio?.muted ? Theme.m3secondaryContainer : "transparent"

            Behavior on color {
                CAnim {}
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: control.mic ? (control.node?.audio?.muted ? "mic_off" : "mic") : root.volumeIcon(control.node)
                fill: true
                size: control.compact ? 18 : 22
                color: control.node?.audio?.muted ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
            }

            StateLayer {
                onClicked: {
                    if (control.node?.audio)
                        control.node.audio.muted = !control.node.audio.muted;
                }
            }
        }

        ValueSlider {
            anchors.left: muteButton.right
            anchors.leftMargin: Theme.sp(8)
            anchors.right: label.left
            anchors.rightMargin: Theme.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            height: control.compact ? 28 : 36
            from: 0
            to: 1
            value: control.node?.audio?.volume ?? 0
            opacity: control.node?.audio?.muted ? 0.5 : 1
            onMoved: value => root.setVolume(control.node, value)
        }

        StyledText {
            id: label

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.sp(36)
            horizontalAlignment: Text.AlignRight
            text: root.percent(control.node)
            font.pixelSize: Theme.size.labelMedium
            font.features: {
                "tnum": 1
            }
            color: Theme.m3onSurfaceVariant
        }
    }

    // Dropdown that unfolds inside the card: the current device with its
    // icon, and below it the others as inset rows, the chosen one highlighted.
    component DevicePicker: Rectangle {
        id: devicePicker

        property var nodes: []
        property var current: null
        property string empty: ""
        property bool mic: false
        property bool open: false
        signal picked(var node)

        function label(node: var): string {
            return node?.description || node?.nickname || node?.name || "";
        }

        // A guess from the node's names; PipeWire has no reliable kind.
        function icon(node: var): string {
            const name = `${node?.name ?? ""} ${label(node)}`;
            if (mic)
                return /bluez|headset/i.test(name) ? "headset_mic" : "mic";
            if (/bluez|headphone|headset/i.test(name))
                return "headphones";
            if (/hdmi|displayport|\bdp\b/i.test(name))
                return "tv";
            return "speaker";
        }

        // Heights known up front (not the animated one), so the card follows
        // the animation instead of a target that moves under it.
        readonly property real rowHeight: Math.max(44, currentName.implicitHeight + Theme.sp(20))
        readonly property real optionHeight: Math.max(36, currentName.implicitHeight + Theme.sp(14))
        readonly property real inset: Theme.sp(4)
        readonly property real openHeight: rowHeight + 1 + inset * 2 + nodes.length * optionHeight + Math.max(0, nodes.length - 1) * options.spacing
        readonly property real targetHeight: open ? openHeight : rowHeight

        height: targetHeight
        radius: Theme.rounding.medium
        color: Theme.m3surfaceContainerHighest
        clip: true

        Behavior on height {
            Anim {
                type: Anim.DefaultSpatial
            }
        }

        // The current device.
        Rectangle {
            id: head

            width: parent.width
            height: devicePicker.rowHeight
            radius: devicePicker.radius
            color: "transparent"

            Rectangle {
                id: badge

                anchors.left: parent.left
                anchors.leftMargin: Theme.sp(8)
                anchors.verticalCenter: parent.verticalCenter
                width: devicePicker.rowHeight - Theme.sp(16)
                height: width
                radius: width / 2
                color: devicePicker.open ? Theme.m3primary : Theme.m3secondaryContainer

                Behavior on color {
                    CAnim {}
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: devicePicker.icon(devicePicker.current)
                    size: 18
                    fill: true
                    color: devicePicker.open ? Theme.m3onPrimary : Theme.m3onSecondaryContainer

                    Behavior on color {
                        CAnim {}
                    }
                }
            }

            StyledText {
                id: currentName

                anchors.left: badge.right
                anchors.leftMargin: Theme.sp(10)
                anchors.right: arrow.left
                anchors.rightMargin: Theme.sp(4)
                anchors.verticalCenter: parent.verticalCenter
                text: devicePicker.label(devicePicker.current) || devicePicker.empty
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            MaterialIcon {
                id: arrow

                anchors.right: parent.right
                anchors.rightMargin: Theme.sp(10)
                anchors.verticalCenter: parent.verticalCenter
                text: "expand_more"
                size: 20
                color: devicePicker.open ? Theme.m3primary : Theme.m3onSurfaceVariant
                rotation: devicePicker.open ? 180 : 0

                Behavior on rotation {
                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }
                Behavior on color {
                    CAnim {}
                }
            }

            StateLayer {
                onClicked: devicePicker.open = !devicePicker.open
            }
        }

        Rectangle {
            y: devicePicker.rowHeight
            x: Theme.sp(12)
            width: parent.width - Theme.sp(24)
            height: 1
            color: Theme.m3outlineVariant
            opacity: devicePicker.open ? 1 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        // The devices to pick from. Always there, so they fold away with the
        // picker instead of vanishing before it closes.
        Column {
            id: options

            y: devicePicker.rowHeight + 1 + devicePicker.inset
            x: devicePicker.inset
            width: parent.width - devicePicker.inset * 2
            spacing: Theme.sp(2)
            opacity: devicePicker.open ? 1 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Repeater {
                model: devicePicker.nodes

                Rectangle {
                    id: option

                    required property var modelData
                    readonly property bool active: modelData === devicePicker.current

                    width: options.width
                    height: devicePicker.optionHeight
                    radius: Theme.rounding.small
                    color: active ? Theme.m3secondaryContainer : "transparent"

                    MaterialIcon {
                        id: optionIcon

                        anchors.left: parent.left
                        anchors.leftMargin: Theme.sp(10)
                        anchors.verticalCenter: parent.verticalCenter
                        text: devicePicker.icon(option.modelData)
                        size: 18
                        fill: option.active
                        color: option.active ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                    }

                    StyledText {
                        anchors.left: optionIcon.right
                        anchors.leftMargin: Theme.sp(10)
                        anchors.right: check.left
                        anchors.rightMargin: Theme.sp(4)
                        anchors.verticalCenter: parent.verticalCenter
                        text: devicePicker.label(option.modelData)
                        font.pixelSize: Theme.size.labelLarge
                        color: option.active ? Theme.m3onSecondaryContainer : Theme.m3onSurface
                        elide: Text.ElideRight
                    }

                    MaterialIcon {
                        id: check

                        anchors.right: parent.right
                        anchors.rightMargin: Theme.sp(10)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "check"
                        size: 18
                        color: Theme.m3onSecondaryContainer
                        visible: option.active
                    }

                    StateLayer {
                        enabled: devicePicker.open
                        onClicked: {
                            devicePicker.picked(option.modelData);
                            devicePicker.open = false;
                        }
                    }
                }
            }
        }
    }

    BarCard {
        id: card

        readonly property real collapsedHeight: header.implicitHeight + hint.fullHeight + padding * 2
        // The pickers at their final heights, not mid-animation.
        readonly property real pickerSlack: (outputPicker.height - outputPicker.targetHeight) + (inputPicker.visible ? inputPicker.height - inputPicker.targetHeight : 0)
        readonly property real expandedHeight: more.implicitHeight - pickerSlack + header.implicitHeight + micRow.fullHeight + padding * 2
        // Room for both pickers open: the window keeps its size while they
        // open and close, and only the card inside it moves.
        readonly property real roomyHeight: expandedHeight + (outputPicker.openHeight - outputPicker.targetHeight) + (inputPicker.visible ? inputPicker.openHeight - inputPicker.targetHeight : 0)

        owner: root
        ownerHovered: mouse.containsMouse
        cardOffset: root.cardOffset
        bounds: root.bounds
        pointerY: mouse.y + mouse.mouseY
        cardWidth: (root.expanded ? Theme.sp(320) : Theme.sp(260)) + padding * 2
        // The content animates every part of its height itself (the expanded
        // part, the pickers, the mic row, the hint); the card just follows.
        animateHeight: false
        maxWidth: Theme.sp(320) + padding * 2
        maxHeight: Math.max(roomyHeight, cardHeight)
        centerHeight: collapsedHeight
        hideDelay: root.expanded ? 500 : 250
        clickable: !root.expanded
        onClicked: root.expanded = true
        onClosed: {
            root.expanded = false;
            outputPicker.open = false;
            inputPicker.open = false;
        }

        Column {
            // Expanded: output device and apps, above, so the card grows up.
            // Unfolds by a fraction of its height, so pickers opening inside
            // it change its height right away, with no animation of its own.
            Item {
                id: moreFold

                property real shown: root.expanded ? 1 : 0

                width: parent.width
                height: Math.round(more.implicitHeight * shown)
                visible: shown > 0
                clip: true

                Behavior on shown {
                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }

                Column {
                    id: more

                    anchors.bottom: parent.bottom
                    width: parent.width
                    opacity: root.expanded ? 1 : 0
                    spacing: Theme.sp(6)

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }

                    StyledText {
                        text: "Output"
                        font.pixelSize: Theme.size.labelMedium
                        font.weight: Font.Medium
                        color: Theme.m3onSurfaceVariant
                    }

                    DevicePicker {
                        id: outputPicker

                        width: parent.width
                        nodes: root.sinks
                        current: root.sink
                        empty: "No output"
                        onPicked: node => Pipewire.preferredDefaultAudioSink = node
                    }

                    // Microphone device; its volume is under the speaker's.
                    StyledText {
                        visible: root.sources.length > 0
                        topPadding: Theme.sp(8)
                        text: "Microphone"
                        font.pixelSize: Theme.size.labelMedium
                        font.weight: Font.Medium
                        color: Theme.m3onSurfaceVariant
                    }

                    DevicePicker {
                        id: inputPicker

                        visible: root.sources.length > 0
                        width: parent.width
                        nodes: root.sources
                        current: root.source
                        empty: "No microphone"
                        mic: true
                        onPicked: node => Pipewire.preferredDefaultAudioSource = node
                    }

                    StyledText {
                        topPadding: Theme.sp(8)
                        text: "Apps"
                        font.pixelSize: Theme.size.labelMedium
                        font.weight: Font.Medium
                        color: Theme.m3onSurfaceVariant
                    }

                    StyledText {
                        visible: root.streams.length === 0
                        text: "No apps are playing sound"
                        font.pixelSize: Theme.size.labelMedium
                        color: Theme.m3onSurfaceVariant
                        opacity: 0.7
                    }

                    Repeater {
                        model: root.streams

                        Column {
                            id: app

                            required property var modelData
                            readonly property string iconPath: root.appIcon(modelData)

                            width: more.width
                            spacing: 0

                            Row {
                                spacing: Theme.sp(8)

                                Image {
                                    visible: !!app.iconPath
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18
                                    height: 18
                                    source: app.iconPath
                                    sourceSize: Qt.size(36, 36)
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, more.width - 26)
                                    text: root.appName(app.modelData)
                                    font.pixelSize: Theme.size.bodyMedium
                                    elide: Text.ElideRight
                                }
                            }

                            VolumeControl {
                                width: parent.width
                                node: app.modelData
                                compact: true
                            }
                        }
                    }

                    // kirin's own sounds (notifications, charger, volume
                    // keys…): their volume, as with the apps. Muting turns
                    // them off without losing the level (SoundFx).
                    Column {
                        width: more.width
                        spacing: 0

                        Row {
                            spacing: Theme.sp(8)

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "notifications_active"
                                fill: true
                                size: 18
                                color: Theme.m3onSurfaceVariant
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "System sounds"
                                font.pixelSize: Theme.size.bodyMedium
                            }
                        }

                        Item {
                            width: parent.width
                            implicitHeight: 32

                            Rectangle {
                                id: sfxMute

                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                height: width
                                radius: width / 2
                                color: Config.sounds.muted ? Theme.m3secondaryContainer : "transparent"

                                Behavior on color {
                                    CAnim {}
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: Config.sounds.muted ? "volume_off" : Config.sounds.volume < 0.34 ? "volume_mute" : Config.sounds.volume < 0.67 ? "volume_down" : "volume_up"
                                    fill: true
                                    size: 18
                                    color: Config.sounds.muted ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                                }

                                StateLayer {
                                    onClicked: Config.sounds.muted = !Config.sounds.muted
                                }
                            }

                            ValueSlider {
                                anchors.left: sfxMute.right
                                anchors.leftMargin: Theme.sp(8)
                                anchors.right: sfxLabel.left
                                anchors.rightMargin: Theme.sp(8)
                                anchors.verticalCenter: parent.verticalCenter
                                height: 28
                                from: 0
                                to: 1
                                value: Config.sounds.volume
                                opacity: Config.sounds.muted ? 0.5 : 1
                                onMoved: value => {
                                    Config.sounds.volume = Math.round(value * 100) / 100;
                                    Config.sounds.muted = false;
                                    sfxPreview.restart();
                                }
                            }

                            StyledText {
                                id: sfxLabel

                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.sp(36)
                                horizontalAlignment: Text.AlignRight
                                text: `${Math.round(Config.sounds.volume * 100)}%`
                                font.pixelSize: Theme.size.labelMedium
                                font.features: {
                                    "tnum": 1
                                }
                                color: Theme.m3onSurfaceVariant
                            }

                            // A sound once dragging pauses, at the new level.
                            Timer {
                                id: sfxPreview

                                interval: 350
                                onTriggered: SoundFx.preview("notification")
                            }
                        }
                    }

                    // Divider before the device's own volume.
                    Item {
                        width: parent.width
                        height: Theme.sp(20)

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Theme.sp(10)
                            width: parent.width
                            height: 1
                            color: Theme.m3outlineVariant
                        }
                    }
                }
            }

            // Always: device name, volume.
            Column {
                id: header

                width: parent.width
                spacing: Theme.sp(2)

                StyledText {
                    width: parent.width
                    text: root.sink?.description || root.sink?.nickname || "Sound"
                    font.pixelSize: Theme.size.titleSmall
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }

                VolumeControl {
                    width: parent.width
                    node: root.sink
                }
            }

            // Expanded: the microphone's volume, under the speaker's.
            Item {
                id: micRow

                readonly property real fullHeight: root.source ? micControl.implicitHeight : 0

                width: parent.width
                height: root.expanded ? fullHeight : 0
                clip: true

                Behavior on height {
                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }

                VolumeControl {
                    id: micControl

                    anchors.bottom: parent.bottom
                    width: parent.width
                    node: root.source
                    mic: true
                    opacity: root.expanded ? 1 : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }
            }

            // Collapsed: the hint to click. Folds away when expanded.
            Item {
                id: hint

                readonly property real fullHeight: hintRow.implicitHeight + Theme.sp(8)

                width: parent.width
                height: root.expanded ? 0 : fullHeight
                clip: true

                Behavior on height {
                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }

                Row {
                    id: hintRow

                    anchors.bottom: parent.bottom
                    opacity: root.expanded ? 0 : 0.7
                    spacing: Theme.sp(4)

                    Behavior on opacity {
                        Anim {
                            type: Anim.FastEffects
                        }
                    }

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "expand_less"
                        size: Theme.size.labelMedium + 4
                        color: Theme.m3onSurfaceVariant
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Click to expand"
                        font.pixelSize: Theme.size.labelMedium
                        color: Theme.m3onSurfaceVariant
                    }
                }
            }
        }
    }
}
