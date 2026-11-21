pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.services

// Network in the bar (NetworkManager, through services/Network.qml): one
// icon showing Wi-Fi signal strength, or Ethernet. Hovering slides out a card
// with the connection, a Wi-Fi switch and the networks around; clicking a
// network connects (asking for the password right in the card if needed).
// Clicking the icon turns Wi-Fi on or off.
// Hidden without a Wi-Fi or Ethernet device.
Item {
    id: root

    property real cardOffset: 0
    // The card stays within this item (the bar).
    property Item bounds: null

    readonly property bool hasWifi: Network.wifiDevice !== ""
    readonly property bool wifiOn: Network.wifiEnabled && Network.wifiHardware
    readonly property var current: Network.active
    readonly property bool connecting: Network.connecting !== ""
    // Connected, but NetworkManager's check says there's no internet.
    readonly property bool noInternet: (!!current || Network.wired) && Network.connectivity !== "full" && Network.connectivity !== "unknown"

    function signalIcon(n: var): string {
        const bars = Math.round((n?.signal ?? 0) / 25);
        return bars >= 4 ? "signal_wifi_4_bar" : bars <= 0 ? "signal_wifi_0_bar" : `network_wifi_${bars}_bar`;
    }

    visible: hasWifi || Network.wired
    implicitWidth: icon.restWidth
    implicitHeight: icon.restHeight

    MaterialIcon {
        id: icon

        readonly property real restOpacity: root.current || Network.wired || root.connecting ? 1 : 0.6

        anchors.centerIn: parent
        text: {
            if (Network.wired && !root.current)
                return "lan";
            if (!root.wifiOn)
                return "wifi_off";
            if (root.noInternet)
                return "signal_wifi_bad";
            if (root.current)
                return root.signalIcon(root.current);
            if (root.connecting)
                return "wifi_find";
            return "signal_wifi_off";
        }
        fill: true
        size: Math.round(19 * Theme.fontScale)
        color: root.noInternet ? Theme.m3error : root.current || Network.wired ? Theme.m3onSurface : Theme.m3onSurfaceVariant
        opacity: restOpacity
        grow: card.open ? 1.1 : 1

        Behavior on color {
            CAnim {}
        }

        // Connecting: pulses.
        SequentialAnimation on opacity {
            running: root.connecting
            loops: Animation.Infinite
            onRunningChanged: if (!running)
                icon.opacity = Qt.binding(() => icon.restOpacity)

            Anim {
                to: 0.35
                type: Anim.DefaultEffects
            }
            Anim {
                to: 1
                type: Anim.DefaultEffects
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        anchors.margins: -Theme.sp(8)
        hoverEnabled: true
        cursorShape: root.hasWifi ? Qt.PointingHandCursor : Qt.ArrowCursor
        // Click: Wi-Fi on/off.
        onClicked: {
            if (root.hasWifi)
                Network.setWifiEnabled(!Network.wifiEnabled);
        }
    }

    // A failed attempt for want of a password: ask for it.
    Connections {
        target: Network

        function onErrorChanged(): void {
            if (Network.needsPassword && Network.errorSsid)
                card.passwordFor = Network.errorSsid;
        }
    }

    BarCard {
        id: card

        // SSID asking for a password.
        property string passwordFor: ""

        readonly property int maxRows: 7
        readonly property real rowHeight: Math.max(44, Theme.size.bodyLarge + Theme.sp(24))

        owner: root
        ownerHovered: mouse.containsMouse
        cardOffset: root.cardOffset
        bounds: root.bounds
        pointerY: mouse.y + mouse.mouseY
        cardWidth: Theme.sp(300) + padding * 2
        // Room for the full list and a password field, so the card can grow
        // without leaving the bar.
        maxHeight: Math.max(cardHeight, header.implicitHeight + rowHeight * (maxRows + 1) + Theme.sp(120))
        pinned: passwordFor !== ""
        grabFocus: passwordFor !== ""
        onClosed: passwordFor = ""
        // Clicked elsewhere while typing: give up on the password.
        onFocusLost: passwordFor = ""
        // One scan each time it opens; no more until the refresh button.
        onOpenChanged: {
            if (open)
                Network.rescan(false);
        }

        Column {
            spacing: Theme.sp(12)

            // Title and the Wi-Fi switch.
            Item {
                id: header

                width: parent.width
                implicitHeight: Math.max(toggle.implicitHeight, title.implicitHeight)

                Column {
                    anchors.left: parent.left
                    anchors.right: refresh.left
                    anchors.rightMargin: Theme.sp(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.sp(2)

                    StyledText {
                        id: title

                        width: parent.width
                        text: root.current?.ssid ?? (Network.wired ? "Ethernet" : root.wifiOn ? "Not connected" : "Wi-Fi is off")
                        font.pixelSize: Theme.size.titleMedium
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: {
                            if (root.connecting)
                                return `Connecting to ${Network.connecting}…`;
                            if (root.noInternet)
                                return "Connected, no internet";
                            if (root.current)
                                return Network.wired ? "Wi-Fi · Ethernet connected too" : "Connected";
                            if (Network.wired)
                                return "Connected by cable";
                            return root.wifiOn ? "Pick a network below" : "Turn it on to see networks";
                        }
                        font.pixelSize: Theme.size.labelMedium
                        color: root.noInternet ? Theme.m3error : Theme.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                // Search again; spins while searching.
                Rectangle {
                    id: refresh

                    visible: root.wifiOn && root.hasWifi
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
                        color: Network.scanning ? Theme.m3primary : Theme.m3onSurfaceVariant

                        RotationAnimation on rotation {
                            running: Network.scanning
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 1200
                            onRunningChanged: if (!running)
                                refreshIcon.rotation = 0
                        }
                    }

                    // Starts over: empty list, then what this scan finds.
                    StateLayer {
                        onClicked: Network.rescan(true)
                    }
                }

                ToggleSwitch {
                    id: toggle

                    visible: root.hasWifi
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Network.wifiEnabled
                    onToggled: checked => Network.setWifiEnabled(checked)
                }
            }

            Rectangle {
                visible: root.wifiOn && root.hasWifi
                width: parent.width
                height: 1
                color: Theme.m3outlineVariant
            }

            // Scrolls once there are more than maxRows networks.
            Flickable {
                id: listView

                visible: root.wifiOn && root.hasWifi
                width: parent.width
                height: Math.min(list.implicitHeight, card.rowHeight * card.maxRows)
                contentWidth: width
                contentHeight: list.implicitHeight
                clip: true
                boundsBehavior: Flickable.DragAndOvershootBounds

                TouchpadScroll {
                    flickable: listView
                }

                // Connected first, then saved ones, then by signal.
                Column {
                    id: list

                    // Connected first, then saved ones, then by signal.
                    function sorted(): var {
                        return Network.networks.slice().sort((a, b) => (b.active - a.active) || (b.known - a.known) || (b.signal - a.signal)).map(n => n.ssid);
                    }

                    // Brings the model in line with the networks, moving rows
                    // rather than rebuilding them, so a row (and a password
                    // being typed in it) survives every refresh. While the
                    // card is open the order stays put: networks that show up
                    // are added at the end. The network asking for a password
                    // stays even if a scan misses it.
                    function sync(): void {
                        const fresh = sorted();
                        let wanted = fresh;
                        if (card.open) {
                            const shown = [];
                            for (let i = 0; i < networkModel.count; i++)
                                shown.push(networkModel.get(i).ssid);
                            wanted = shown.filter(s => fresh.includes(s) || s === card.passwordFor).concat(fresh.filter(s => !shown.includes(s)));
                        }
                        for (let i = networkModel.count - 1; i >= 0; i--)
                            if (!wanted.includes(networkModel.get(i).ssid))
                                networkModel.remove(i);
                        for (let i = 0; i < wanted.length; i++) {
                            if (i < networkModel.count && networkModel.get(i).ssid === wanted[i])
                                continue;
                            let from = -1;
                            for (let j = i + 1; j < networkModel.count; j++)
                                if (networkModel.get(j).ssid === wanted[i]) {
                                    from = j;
                                    break;
                                }
                            if (from >= 0)
                                networkModel.move(from, i, 1);
                            else
                                networkModel.insert(i, {
                                    ssid: wanted[i]
                                });
                        }
                    }

                    width: listView.width
                    spacing: Theme.sp(2)

                    ListModel {
                        id: networkModel
                    }

                    Component.onCompleted: sync()

                    Connections {
                        target: Network

                        function onNetworksChanged(): void {
                            list.sync();
                        }
                    }

                    // Sorted afresh each time the card opens.
                    Connections {
                        target: card

                        function onOpenChanged(): void {
                            if (!card.open)
                                list.sync();
                        }
                    }

                    StyledText {
                        visible: networkModel.count === 0
                        width: parent.width
                        topPadding: Theme.sp(4)
                        bottomPadding: Theme.sp(4)
                        text: "Looking for networks…"
                        font.pixelSize: Theme.size.labelMedium
                        color: Theme.m3onSurfaceVariant
                    }

                    Repeater {
                        model: networkModel

                        Column {
                            id: entry

                            required property string ssid
                            // Current details; a placeholder while a scan misses it.
                            readonly property var net: Network.networks.find(n => n.ssid === ssid) ?? ({
                                    ssid,
                                    signal: 0,
                                    security: "",
                                    secured: true,
                                    active: false,
                                    known: Network.known.includes(ssid)
                                })
                            readonly property bool asking: card.passwordFor === net.ssid
                            readonly property bool busy: Network.connecting === net.ssid

                            width: list.width
                            spacing: Theme.sp(6)

                            // Scroll the password field into view.
                            onAskingChanged: {
                                if (asking)
                                    Qt.callLater(() => {
                                        const bottom = entry.y + entry.height;
                                        if (bottom > listView.contentY + listView.height)
                                            listView.contentY = bottom - listView.height;
                                    });
                            }

                            Rectangle {
                                id: row

                                width: parent.width
                                height: card.rowHeight
                                radius: Theme.rounding.medium
                                color: entry.net.active ? Theme.m3secondaryContainer : "transparent"

                                Behavior on color {
                                    CAnim {}
                                }

                                MaterialIcon {
                                    id: strengthIcon

                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.sp(12)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.signalIcon(entry.net)
                                    fill: true
                                    size: Theme.size.titleMedium + 4
                                    color: entry.net.active ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                                }

                                Column {
                                    anchors.left: strengthIcon.right
                                    anchors.leftMargin: Theme.sp(12)
                                    anchors.right: trailing.left
                                    anchors.rightMargin: Theme.sp(8)
                                    anchors.verticalCenter: parent.verticalCenter

                                    StyledText {
                                        width: parent.width
                                        text: entry.net.ssid
                                        font.weight: entry.net.active ? Font.Medium : Font.Normal
                                        color: entry.net.active ? Theme.m3onSecondaryContainer : Theme.m3onSurface
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        readonly property bool failed: Network.errorSsid === entry.net.ssid && Network.error !== ""

                                        visible: text !== ""
                                        width: parent.width
                                        text: entry.busy ? "Connecting…" : failed ? Network.error : entry.net.active ? "Connected · click to disconnect" : entry.net.known ? "Saved" : ""
                                        font.pixelSize: Theme.size.labelMedium
                                        color: failed ? Theme.m3error : entry.net.active ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                                        opacity: failed ? 1 : 0.8
                                        elide: Text.ElideRight
                                    }
                                }

                                StateLayer {
                                    enabled: !entry.busy
                                    onClicked: {
                                        const n = entry.net;
                                        if (n.active)
                                            Network.disconnect();
                                        else if (n.known || !n.secured)
                                            Network.connect(n.ssid, "");
                                        else
                                            card.passwordFor = entry.asking ? "" : n.ssid;
                                    }
                                }

                                // Lock for secured networks; on hover over a saved
                                // one, a button to forget it.
                                Row {
                                    id: trailing

                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.sp(8)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.sp(4)

                                    MaterialIcon {
                                        visible: entry.net.secured
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "lock"
                                        size: Theme.size.labelMedium + 4
                                        color: entry.net.active ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                                        opacity: 0.7
                                    }

                                    Rectangle {
                                        visible: entry.net.known && rowHover.hovered
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: "transparent"

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            text: "delete"
                                            size: 18
                                            color: Theme.m3onSurfaceVariant
                                        }

                                        StateLayer {
                                            onClicked: Network.forget(entry.net.ssid)
                                        }
                                    }
                                }

                                HoverHandler {
                                    id: rowHover
                                }
                            }

                            // Password, right under its network.
                            Rectangle {
                                visible: entry.asking
                                width: parent.width
                                height: visible ? Math.max(40, password.implicitHeight + Theme.sp(16)) : 0
                                radius: Theme.rounding.small
                                color: Theme.m3surfaceContainerHighest
                                border.width: password.activeFocus ? 2 : 0
                                border.color: Theme.m3primary

                                TextInput {
                                    id: password

                                    function submit(): void {
                                        if (text.length === 0)
                                            return;
                                        Network.connect(entry.net.ssid, text);
                                        text = "";
                                        card.passwordFor = "";
                                    }

                                    anchors.left: parent.left
                                    anchors.right: connectButton.left
                                    anchors.leftMargin: Theme.sp(12)
                                    anchors.rightMargin: Theme.sp(8)
                                    anchors.verticalCenter: parent.verticalCenter
                                    echoMode: TextInput.Password
                                    font.family: Theme.font.family
                                    font.pixelSize: Theme.size.bodyLarge
                                    color: Theme.m3onSurface
                                    selectionColor: Theme.m3primary
                                    selectedTextColor: Theme.m3onPrimary
                                    clip: true
                                    onAccepted: submit()
                                    Keys.onEscapePressed: card.passwordFor = ""
                                    // Focus once the popup has the keyboard.
                                    onVisibleChanged: if (visible)
                                        Qt.callLater(forceActiveFocus)

                                    StyledText {
                                        visible: !password.text
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Password"
                                        color: Theme.m3onSurfaceVariant
                                    }
                                }

                                Rectangle {
                                    id: connectButton

                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.sp(4)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 32
                                    height: 32
                                    radius: 16
                                    color: password.text ? Theme.m3primary : "transparent"

                                    Behavior on color {
                                        CAnim {}
                                    }

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: "arrow_forward"
                                        size: 20
                                        color: password.text ? Theme.m3onPrimary : Theme.m3onSurfaceVariant
                                    }

                                    StateLayer {
                                        onClicked: password.submit()
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
