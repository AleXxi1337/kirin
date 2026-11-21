pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.components
import qs.services

// Bluetooth (BlueZ, through Quickshell.Bluetooth): one icon in the bar;
// clicking it turns Bluetooth on or off. Hovering slides out a card with a
// switch, a refresh button (searches for devices) and the devices: click one
// to connect, disconnect or pair; paired ones have an auto-connect toggle
// (BlueZ "trusted") and, on hover, forget.
// Hidden without a Bluetooth adapter.
Item {
    id: root

    property real cardOffset: 0
    // The card stays within this item (the bar).
    property Item bounds: null

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    // Bluetooth blocked by rfkill (airplane mode, blueman's switch). On
    // ThinkPads the adapter then disappears altogether.
    property bool blocked: false
    property bool rfkillPresent: false
    readonly property bool on: !blocked && (adapter?.enabled ?? false)
    // Turning on after unblocking: the adapter comes back first.
    property bool enableWhenBack: false

    function setEnabled(enable: bool): void {
        if (!enable) {
            enableWhenBack = false;
            if (adapter)
                adapter.enabled = false;
        } else if (blocked || !adapter) {
            enableWhenBack = true;
            Quickshell.execDetached(["rfkill", "unblock", "bluetooth"]);
        } else {
            adapter.enabled = true;
        }
    }

    onAdapterChanged: {
        if (adapter && enableWhenBack) {
            adapter.enabled = true;
            enableWhenBack = false;
        }
    }

    // rfkill state: read now and on every rfkill event.
    Process {
        id: rfkillState

        running: true
        command: ["sh", "-c", "for d in /sys/class/rfkill/rfkill*; do [ \"$(cat $d/type)\" = bluetooth ] && echo \"$(cat $d/soft)$(cat $d/hard)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l);
                root.rfkillPresent = lines.length > 0;
                root.blocked = lines.length > 0 && lines.every(l => l.includes("1"));
            }
        }
    }

    Process {
        id: rfkillEvents

        running: true
        command: ["rfkill", "event"]
        stdout: SplitParser {
            onRead: rfkillState.running = true
        }
        onExited: rfkillRestart.start()
    }

    Timer {
        id: rfkillRestart

        interval: 5000
        onTriggered: rfkillEvents.running = true
    }
    readonly property var devices: adapter?.devices.values ?? []
    readonly property var connected: devices.filter(d => d.connected)

    // Paired after a click on an unpaired device: connect and trust it then.
    property var pairingDevice: null

    // Searches for devices for a while.
    function refresh(): void {
        if (!adapter || !on)
            return;
        adapter.discovering = true;
        stopSearch.restart();
    }

    // Material Symbols for BlueZ's device icon names.
    function deviceIcon(d: var): string {
        const icon = d?.icon ?? "";
        if (/headset|headphone/.test(icon))
            return "headphones";
        if (/audio|speaker/.test(icon))
            return "speaker";
        if (/mouse/.test(icon))
            return "mouse";
        if (/keyboard/.test(icon))
            return "keyboard";
        if (/gaming|joystick/.test(icon))
            return "sports_esports";
        if (/phone/.test(icon))
            return "smartphone";
        if (/computer|laptop/.test(icon))
            return "computer";
        if (/watch/.test(icon))
            return "watch";
        return "bluetooth";
    }

    function battery(d: var): string {
        if (!d?.batteryAvailable)
            return "";
        const b = d.battery > 1 ? d.battery / 100 : d.battery;
        return `${Math.round(b * 100)}%`;
    }

    // Also while blocked, to turn it back on.
    visible: !!adapter || rfkillPresent
    implicitWidth: icon.restWidth
    implicitHeight: icon.restHeight

    Timer {
        id: stopSearch

        interval: 15000
        onTriggered: {
            if (root.adapter)
                root.adapter.discovering = false;
        }
    }

    Connections {
        target: root.pairingDevice

        function onPairedChanged(): void {
            const d = root.pairingDevice;
            if (d?.paired) {
                d.trusted = true;
                d.connect();
                root.pairingDevice = null;
            }
        }
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: !root.on ? "bluetooth_disabled" : root.connected.length > 0 ? "bluetooth_connected" : "bluetooth"
        fill: true
        size: Math.round(19 * Theme.fontScale)
        color: root.connected.length > 0 ? Theme.m3onSurface : Theme.m3onSurfaceVariant
        opacity: root.on ? 1 : 0.6
        grow: card.open ? 1.1 : 1
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        anchors.margins: -Theme.sp(8)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Click: Bluetooth on/off.
        onClicked: {
            root.setEnabled(!root.on);
        }
    }

    BarCard {
        id: card

        readonly property int maxRows: 7
        readonly property real rowHeight: Math.max(48, Theme.size.bodyLarge + Theme.size.labelMedium + Theme.sp(20))

        owner: root
        ownerHovered: mouse.containsMouse
        cardOffset: root.cardOffset
        bounds: root.bounds
        pointerY: mouse.y + mouse.mouseY
        cardWidth: Theme.sp(300) + padding * 2
        // Room for the full list, so the card can grow without leaving the bar.
        maxHeight: Math.max(cardHeight, header.implicitHeight + rowHeight * maxRows + Theme.sp(60))
        // A short search whenever it opens.
        onOpenChanged: {
            if (open)
                root.refresh();
        }

        Column {
            spacing: Theme.sp(12)

            // Title, refresh, switch.
            Item {
                id: header

                width: parent.width
                implicitHeight: Math.max(toggle.implicitHeight, titleColumn.implicitHeight)

                Column {
                    id: titleColumn

                    anchors.left: parent.left
                    anchors.right: refresh.left
                    anchors.rightMargin: Theme.sp(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.sp(2)

                    StyledText {
                        width: parent.width
                        text: "Bluetooth"
                        font.pixelSize: Theme.size.titleMedium
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: {
                            if (!root.on)
                                return "Off";
                            const n = root.connected.length;
                            if (n === 1)
                                return `Connected to ${root.connected[0].name}`;
                            if (n > 1)
                                return `${n} devices connected`;
                            return root.adapter?.discovering ? "Searching for devices…" : "On";
                        }
                        font.pixelSize: Theme.size.labelMedium
                        color: Theme.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                // Search again; spins while searching.
                Rectangle {
                    id: refresh

                    visible: root.on
                    anchors.right: toggle.left
                    anchors.rightMargin: Theme.sp(8)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36
                    radius: 18
                    color: "transparent"

                    MaterialIcon {
                        id: refreshIcon

                        anchors.centerIn: parent
                        text: "refresh"
                        size: 20
                        color: root.adapter?.discovering ? Theme.m3primary : Theme.m3onSurfaceVariant

                        RotationAnimation on rotation {
                            running: root.adapter?.discovering ?? false
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 1200
                            onRunningChanged: if (!running)
                                refreshIcon.rotation = 0
                        }
                    }

                    StateLayer {
                        onClicked: root.refresh()
                    }
                }

                ToggleSwitch {
                    id: toggle

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.on
                    onToggled: checked => {
                        root.setEnabled(checked);
                    }
                }
            }

            Rectangle {
                visible: root.on
                width: parent.width
                height: 1
                color: Theme.m3outlineVariant
            }

            // Connected first, then paired, then found nearby (named only).
            // Scrolls once there are more than maxRows entries.
            Flickable {
                id: listView

                visible: root.on
                width: parent.width
                height: Math.min(list.implicitHeight, card.rowHeight * card.maxRows)
                contentWidth: width
                contentHeight: list.implicitHeight
                clip: true
                boundsBehavior: Flickable.DragAndOvershootBounds

                TouchpadScroll {
                    flickable: listView
                }

                Column {
                    id: list

                    readonly property var sorted: root.devices.filter(d => d.paired || d.name && d.name !== d.address.replace(/:/g, "-")).slice().sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))

                    width: listView.width
                    spacing: Theme.sp(2)

                    StyledText {
                        visible: list.sorted.length === 0
                        width: parent.width
                        topPadding: Theme.sp(4)
                        bottomPadding: Theme.sp(4)
                        text: root.adapter?.discovering ? "Searching for devices…" : "No devices. Make yours discoverable and refresh."
                        font.pixelSize: Theme.size.labelMedium
                        color: Theme.m3onSurfaceVariant
                        wrapMode: Text.Wrap
                    }

                    Repeater {
                        model: list.sorted

                        // A row, with the group's heading above the first one
                        // of each group (saved devices, then available ones).
                        Column {
                            id: entry

                            required property var modelData
                            required property int index
                            readonly property bool groupStart: index === 0 || list.sorted[index - 1].paired !== modelData.paired

                            width: list.width

                            StyledText {
                                visible: entry.groupStart
                                width: parent.width
                                leftPadding: Theme.sp(12)
                                topPadding: entry.index === 0 ? Theme.sp(2) : Theme.sp(10)
                                bottomPadding: Theme.sp(4)
                                text: entry.modelData.paired ? "Saved devices" : "Available"
                                font.pixelSize: Theme.size.labelMedium
                                font.weight: Font.Medium
                                color: Theme.m3primary
                            }

                            Rectangle {
                                id: row

                                readonly property var device: entry.modelData
                                // Forget asks again first: one click arms, the next forgets.
                                property bool confirmForget: false
                                readonly property bool busy: !device || device.state === BluetoothDeviceState.Connecting || device.state === BluetoothDeviceState.Disconnecting || device.pairing

                                width: list.width
                                height: card.rowHeight
                                radius: Theme.rounding.medium
                                color: device.connected ? Theme.m3secondaryContainer : "transparent"

                                Behavior on color {
                                    CAnim {}
                                }

                                MaterialIcon {
                                    id: deviceIcon

                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.sp(12)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.deviceIcon(row.device)
                                    fill: row.device?.connected
                                    size: Theme.size.titleMedium + 4
                                    color: row.device?.connected ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                                }

                                Column {
                                    anchors.left: deviceIcon.right
                                    anchors.leftMargin: Theme.sp(12)
                                    anchors.right: actions.left
                                    anchors.rightMargin: Theme.sp(8)
                                    anchors.verticalCenter: parent.verticalCenter

                                    StyledText {
                                        width: parent.width
                                        text: row.device?.name || row.device?.address
                                        font.weight: row.device?.connected ? Font.Medium : Font.Normal
                                        color: row.device?.connected ? Theme.m3onSecondaryContainer : Theme.m3onSurface
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: {
                                            const d = row.device;
                                            if (d.pairing)
                                                return "Pairing…";
                                            if (d.state === BluetoothDeviceState.Connecting)
                                                return "Connecting…";
                                            if (d.state === BluetoothDeviceState.Disconnecting)
                                                return "Disconnecting…";
                                            if (row.confirmForget)
                                                return "Click again to forget";
                                            if (d.connected)
                                                return ["Connected", d.trusted ? "auto" : "", root.battery(d)].filter(s => s).join(" · ");
                                            if (d.paired)
                                                return d.trusted ? "Not connected · connects automatically" : "Not connected";
                                            return "Click to pair";
                                        }
                                        font.pixelSize: Theme.size.labelMedium
                                        color: row.device?.connected ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                                        opacity: 0.8
                                        elide: Text.ElideRight
                                    }
                                }

                                StateLayer {
                                    enabled: !row.busy
                                    onClicked: {
                                        const d = row.device;
                                        if (d.connected) {
                                            d.disconnect();
                                        } else if (d.paired) {
                                            d.connect();
                                        } else {
                                            root.pairingDevice = d;
                                            d.pair();
                                        }
                                    }
                                }

                                Timer {
                                    running: row.confirmForget
                                    interval: 3000
                                    onTriggered: row.confirmForget = false
                                }

                                // Saved devices: auto-connect on/off and forget.
                                Row {
                                    id: actions

                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.sp(6)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.sp(2)

                                    component RowButton: Rectangle {
                                        id: button

                                        property string icon
                                        property bool active: false
                                        property bool danger: false
                                        signal clicked

                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 30
                                        height: 30
                                        radius: 15
                                        color: danger ? Theme.m3error : active ? Theme.m3primary : "transparent"

                                        Behavior on color {
                                            CAnim {}
                                        }

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            text: button.icon
                                            size: 18
                                            fill: button.active || button.danger
                                            color: button.danger ? Theme.m3onError : button.active ? Theme.m3onPrimary : row.device?.connected ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                                        }

                                        StateLayer {
                                            onClicked: button.clicked()
                                        }
                                    }

                                    RowButton {
                                        visible: row.device?.paired ?? false
                                        icon: "delete"
                                        danger: row.confirmForget
                                        onClicked: {
                                            if (!row.confirmForget) {
                                                row.confirmForget = true;
                                                return;
                                            }
                                            row.confirmForget = false;
                                            row.device?.forget();
                                        }
                                    }

                                    RowButton {
                                        visible: row.device?.paired
                                        icon: "autorenew"
                                        active: row.device?.trusted
                                        onClicked: {
                                            if (row.device)
                                                row.device.trusted = !row.device.trusted;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Scroll position, while there's something to scroll.
                Rectangle {
                    visible: listView.contentHeight > listView.height + 1
                    parent: listView
                    anchors.right: parent.right
                    y: listView.visibleArea.yPosition * listView.height
                    width: 3
                    height: Math.max(16, listView.visibleArea.heightRatio * listView.height)
                    radius: 1.5
                    color: Theme.m3outline
                    opacity: listView.moving ? 0.8 : 0.35

                    Behavior on opacity {
                        Anim {
                            type: Anim.FastEffects
                        }
                    }
                }
            }
        }
    }
}
