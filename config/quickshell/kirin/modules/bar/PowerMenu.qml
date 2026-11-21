pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.services

// The session menu, from the bar's logo: lock, suspend, reboot, shut
// down. Opens on a click (not on hover like the other cards: the
// pointer ends up in that corner all the time) and goes once the pointer
// has left the logo and the card. No confirmation: an action runs at once.
Item {
    id: root

    required property Item owner
    property bool ownerHovered: false
    property real cardOffset: 0
    property Item bounds: null
    readonly property bool open: card.open

    function toggle(): void {
        if (card.open)
            card.close();
        else {
            uptime.reload();
            card.show();
        }
    }

    // An action without a command is shown greyed out ("Soon").
    readonly property var actions: [
        {
            icon: "lock",
            label: "Lock",
            command: ["qs", "-c", "kirin", "ipc", "call", "lock", "lock"]
        },
        {
            icon: "bedtime",
            label: "Suspend",
            command: ["systemctl", "suspend"]
        },
        {
            icon: "restart_alt",
            label: "Reboot",
            command: ["systemctl", "reboot"]
        },
        {
            icon: "power_settings_new",
            label: "Shut down",
            command: ["systemctl", "poweroff"],
            danger: true
        }
    ]

    function run(action: var): void {
        if (!action.command)
            return;
        card.close();
        Quickshell.execDetached(action.command);
    }

    // "up 3 h 12 min", read when the card opens.
    FileView {
        id: uptime

        path: "/proc/uptime"
        printErrors: false

        readonly property string label: {
            const s = parseFloat(text()) || 0;
            const d = Math.floor(s / 86400);
            const h = Math.floor(s % 86400 / 3600);
            const m = Math.floor(s % 3600 / 60);
            const parts = [];
            if (d)
                parts.push(`${d} d`);
            if (h)
                parts.push(`${h} h`);
            if (!d)
                parts.push(`${m} min`);
            return `up ${parts.join(" ")}`;
        }
    }

    BarCard {
        id: card

        owner: root.owner
        // Hovering the logo only keeps it open; a click opens it.
        ownerHovered: root.ownerHovered && card.open
        cardOffset: root.cardOffset
        bounds: root.bounds
        cardWidth: Theme.sp(200) + padding * 2
        padding: Theme.sp(12)

        Column {
            spacing: Theme.sp(2)

            // Who and how long.
            Column {
                width: parent.width
                leftPadding: Theme.sp(8)
                bottomPadding: Theme.sp(8)

                StyledText {
                    text: Quickshell.env("USER") || "Session"
                    font.pixelSize: Theme.size.titleSmall
                    font.weight: Font.Medium
                }

                StyledText {
                    text: uptime.label
                    font.pixelSize: Theme.size.labelMedium
                    color: Theme.m3onSurfaceVariant
                }
            }

            Repeater {
                model: root.actions

                Item {
                    id: row

                    required property var modelData
                    readonly property bool usable: modelData.command !== null

                    width: parent.width
                    height: 44

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rounding.medium
                        color: "transparent"
                        opacity: row.usable ? 1 : 0.5

                        Rectangle {
                            id: plate

                            anchors.left: parent.left
                            anchors.leftMargin: Theme.sp(4)
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 34
                            radius: Theme.iconRadius(width)
                            color: row.modelData.danger ? Qt.alpha(Theme.m3error, 0.18) : Theme.m3surfaceContainerHighest

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: row.modelData.icon
                                size: 20
                                color: row.modelData.danger ? Theme.m3error : Theme.m3onSurfaceVariant
                            }
                        }

                        StyledText {
                            anchors.left: plate.right
                            anchors.leftMargin: Theme.sp(12)
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.label
                            font.pixelSize: Theme.size.bodyLarge
                        }

                        StyledText {
                            visible: !row.usable
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.sp(8)
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Soon"
                            font.pixelSize: Theme.size.labelMedium
                            color: Theme.m3onSurfaceVariant
                        }

                        StateLayer {
                            visible: row.usable
                            onClicked: root.run(row.modelData)
                        }
                    }
                }
            }
        }
    }
}
