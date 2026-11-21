pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.components
import qs.services

// Laptop battery from UPower, as a single vertical icon. The charge shows in
// its colour: accent above 80%, red below 20%, the text colour in between.
// Hovering slides out a card next to the bar with the percentage, a charge
// bar and the time left; clicking the card expands it with the power profiles.
// Hidden when there's no laptop battery (desktop PCs) or UPower isn't running.
Item {
    id: root

    // Distance from the icon's right edge to where the card starts (past the
    // bar's edge and a gap), set by the bar.
    property real cardOffset: 0
    // The card stays within this item (the bar).
    property Item bounds: null

    readonly property UPowerDevice device: UPower.displayDevice
    readonly property bool available: !!device && device.ready && device.isLaptopBattery && device.isPresent
    // 0–1 in Quickshell ≥ 0.2.
    readonly property real level: Math.max(0, Math.min(1, device?.percentage ?? 0))
    readonly property bool charging: device?.state === UPowerDeviceState.Charging || device?.state === UPowerDeviceState.PendingCharge
    readonly property bool full: device?.state === UPowerDeviceState.FullyCharged
    // Plugged in, whether charging or not (charge limit, full).
    readonly property bool plugged: !UPower.onBattery
    readonly property color levelColor: level > 0.8 ? Theme.m3primary : level < 0.2 ? Theme.m3error : Theme.m3onSurface
    // The icon on the bar: the text colour, red only when the battery is
    // low and not charging (Settings → Power, "low").
    readonly property color iconColor: Power.low ? Theme.m3error : Theme.m3onSurface

    property bool expanded: false

    // "2 h 15 min" from seconds.
    function duration(seconds: real): string {
        const minutes = Math.round(seconds / 60);
        const h = Math.floor(minutes / 60), m = minutes % 60;
        return h > 0 ? (m > 0 ? `${h} h ${m} min` : `${h} h`) : `${m} min`;
    }

    readonly property string status: {
        if (full || (plugged && level >= 0.995))
            return "Fully charged";
        if (charging)
            return device.timeToFull > 0 ? `${duration(device.timeToFull)} until full` : "Charging";
        if (plugged)
            return "Plugged in, not charging";
        return device?.timeToEmpty > 0 ? `${duration(device.timeToEmpty)} left` : "On battery";
    }

    visible: available
    implicitWidth: icon.restWidth
    implicitHeight: icon.restHeight

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        // Material Symbols batteries are vertical: battery_0_bar … battery_6_bar,
        // battery_full; charging ones step 20, 30, 50, 60, 80, 90, full.
        text: {
            if (root.charging || (root.plugged && !root.full)) {
                const steps = [20, 30, 50, 60, 80, 90];
                const step = steps.find(s => root.level * 100 < s + 5);
                return step ? `battery_charging_${step}` : "battery_charging_full";
            }
            if (root.full || root.level >= 0.95)
                return "battery_full";
            if (root.level < 0.2)
                return "battery_alert";
            return `battery_${Math.round(root.level * 6)}_bar`;
        }
        fill: true
        size: Math.round(22 * Theme.fontScale)
        color: root.iconColor
        grow: card.open ? 1.1 : 1

        Behavior on color {
            CAnim {}
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        anchors.margins: -Theme.sp(8)
        hoverEnabled: true
    }

    // Collapsed it's centred on the icon; expanding grows it upwards, since
    // the battery sits at the bottom of the screen.
    BarCard {
        id: card

        readonly property real collapsedWidth: Math.max(Theme.sp(150), header.implicitWidth + padding * 2)
        readonly property real expandedWidth: Math.max(Theme.sp(230), collapsedWidth)
        readonly property real collapsedHeight: header.implicitHeight + hint.fullHeight + padding * 2
        readonly property real expandedHeight: profiles.implicitHeight + header.implicitHeight + padding * 2

        owner: root
        ownerHovered: mouse.containsMouse
        cardOffset: root.cardOffset
        bounds: root.bounds
        pointerY: mouse.y + mouse.mouseY
        cardWidth: root.expanded ? expandedWidth : collapsedWidth
        cardHeight: root.expanded ? expandedHeight : collapsedHeight
        maxWidth: expandedWidth
        maxHeight: expandedHeight
        centerHeight: collapsedHeight
        hideDelay: root.expanded ? 500 : 250
        // Collapsed: a click anywhere on the card expands it.
        clickable: !root.expanded
        onClicked: root.expanded = true
        onClosed: root.expanded = false

        Column {
            id: content

            // Expanded part, above the battery info so the card grows
            // upwards. Fades in once there's room.
            Column {
                id: profiles

                width: parent.width
                visible: opacity > 0
                opacity: root.expanded ? 1 : 0
                spacing: Theme.sp(4)

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                StyledText {
                    bottomPadding: Theme.sp(4)
                    text: "Power mode"
                    font.pixelSize: Theme.size.labelMedium
                    font.weight: Font.Medium
                    color: Theme.m3onSurfaceVariant
                }

                Repeater {
                    model: Power.options

                    // M3 list item; the active profile is highlighted.
                    Rectangle {
                        id: option

                        required property var modelData
                        readonly property bool active: Power.profile === modelData.value

                        width: profiles.width
                        implicitHeight: Math.max(40, optionLabel.implicitHeight + Theme.sp(16))
                        // Without the daemon the profiles show, but can't be picked.
                        enabled: Power.available
                        opacity: enabled ? 1 : 0.38
                        radius: Theme.rounding.medium
                        color: active ? Theme.m3secondaryContainer : "transparent"

                        Behavior on color {
                            CAnim {}
                        }

                        MaterialIcon {
                            id: optionIcon

                            anchors.left: parent.left
                            anchors.leftMargin: Theme.sp(12)
                            anchors.verticalCenter: parent.verticalCenter
                            text: option.modelData.icon
                            fill: option.active
                            size: Theme.size.titleMedium + 4
                            color: option.active ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                        }

                        StyledText {
                            id: optionLabel

                            anchors.left: optionIcon.right
                            anchors.leftMargin: Theme.sp(12)
                            anchors.verticalCenter: parent.verticalCenter
                            text: option.modelData.label
                            font.weight: option.active ? Font.Medium : Font.Normal
                            color: option.active ? Theme.m3onSecondaryContainer : Theme.m3onSurface
                        }

                        StateLayer {
                            onClicked: Power.set(option.modelData.value)
                        }
                    }
                }

                StyledText {
                    visible: !Power.available
                    width: parent.width
                    topPadding: Theme.sp(4)
                    text: "No power profile service is running"
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.size.labelMedium
                    color: Theme.m3onSurfaceVariant
                }

                // The last switch failed: what was asked for and the daemon's reason.
                Row {
                    visible: Power.available && Power.error !== ""
                    width: parent.width
                    topPadding: Theme.sp(4)
                    spacing: Theme.sp(8)

                    MaterialIcon {
                        id: errorIcon

                        text: "error"
                        fill: true
                        size: Theme.size.titleMedium
                        color: Theme.m3error
                    }

                    Column {
                        width: parent.width - errorIcon.width - parent.spacing
                        spacing: Theme.sp(2)

                        StyledText {
                            width: parent.width
                            text: Power.failed >= 0 ? `Couldn't switch to ${Power.label(Power.failed)}` : "Couldn't switch the profile"
                            wrapMode: Text.Wrap
                            font.pixelSize: Theme.size.labelMedium
                            font.weight: Font.Medium
                            color: Theme.m3error
                        }

                        StyledText {
                            width: parent.width
                            text: Power.error
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            font.pixelSize: Theme.size.labelSmall
                            color: Theme.m3onSurfaceVariant
                        }
                    }
                }

                // To Settings → Power (automatic power saver etc.).
                Rectangle {
                    width: profiles.width
                    implicitHeight: Math.max(36, moreLabel.implicitHeight + Theme.sp(12))
                    radius: Theme.rounding.medium
                    color: "transparent"

                    MaterialIcon {
                        id: moreIcon

                        anchors.left: parent.left
                        anchors.leftMargin: Theme.sp(12)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "settings"
                        size: Theme.size.titleMedium + 4
                        color: Theme.m3primary
                    }

                    StyledText {
                        id: moreLabel

                        anchors.left: moreIcon.right
                        anchors.leftMargin: Theme.sp(12)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Power settings"
                        font.weight: Font.Medium
                        color: Theme.m3primary
                    }

                    StateLayer {
                        color: Theme.m3primary
                        onClicked: {
                            card.close();
                            Panels.openSettings("Power");
                        }
                    }
                }

                // Divider between the profiles and the battery info.
                Item {
                    width: parent.width
                    height: Theme.sp(20)

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Theme.sp(12)
                        width: parent.width
                        height: 1
                        color: Theme.m3outlineVariant
                    }
                }
            }

            Column {
                id: header

                width: parent.width
                spacing: Theme.sp(8)

                Row {
                    spacing: Theme.sp(2)

                    StyledText {
                        id: percent

                        text: Math.round(root.level * 100)
                        font.pixelSize: Theme.size.headlineSmall
                        font.weight: Font.Bold
                        color: root.levelColor
                    }

                    StyledText {
                        anchors.baseline: percent.baseline
                        text: "%"
                        font.pixelSize: Theme.size.titleSmall
                        font.weight: Font.Medium
                        color: Theme.m3onSurfaceVariant
                    }

                    MaterialIcon {
                        visible: root.charging
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: Theme.sp(4)
                        text: "bolt"
                        fill: true
                        size: Theme.size.titleMedium
                        color: Theme.m3primary
                    }
                }

                // Charge bar: M3 linear progress indicator.
                Rectangle {
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Theme.m3surfaceContainerHighest

                    Rectangle {
                        width: Math.max(height, parent.width * root.level)
                        height: parent.height
                        radius: 2
                        color: root.levelColor

                        Behavior on width {
                            Anim {
                                type: Anim.DefaultSpatial
                            }
                        }
                        Behavior on color {
                            CAnim {}
                        }
                    }
                }

                StyledText {
                    text: root.status
                    font.pixelSize: Theme.size.labelMedium
                    color: Theme.m3onSurfaceVariant
                }
            }

            // Collapsed: the hint to click. Folds away when expanded.
            Item {
                id: hint

                readonly property real fullHeight: hintRow.implicitHeight + Theme.sp(12)

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
