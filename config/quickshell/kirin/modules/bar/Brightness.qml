pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.services

// Screen brightness (the laptop's backlight) and light/dark mode. The icon is
// a sun or a moon for the colour scheme's mode; clicking it switches mode,
// scrolling over it changes the brightness. Hovering slides out a card with
// a brightness slider. Hidden without a backlight (desktop monitors).
// The brightness itself is the Brightness service.
Item {
    id: root

    property real cardOffset: 0
    // The card stays within this item (the bar).
    property Item bounds: null

    readonly property bool dark: Config.appearance.mode !== "light"

    readonly property real level: Backlight.level

    function setLevel(value: real): void {
        Backlight.setLevel(value);
    }

    visible: Backlight.available
    implicitWidth: icon.restWidth
    implicitHeight: icon.restHeight

    // Read often while the card shows the value.
    Connections {
        target: card

        function onOpenChanged(): void {
            Backlight.watchers += card.open ? 1 : -1;
        }
    }

    Component.onDestruction: {
        if (card.open)
            Backlight.watchers -= 1;
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: root.dark ? "dark_mode" : "light_mode"
        fill: true
        size: 20
        color: Theme.m3onSurface
        grow: card.open ? 1.1 : 1

        // A half turn when the mode switches.
        RotationAnimation on rotation {
            id: turn

            running: false
            from: -180
            to: 0
            duration: Theme.anim.durations.normal
            easing.type: Easing.OutBack
        }
    }




    Connections {
        target: Config.appearance

        function onModeChanged(): void {
            turn.restart();
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        anchors.margins: -Theme.sp(8)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Click: light/dark mode.
        onClicked: Config.appearance.mode = root.dark ? "light" : "dark"
        // Scroll: brightness, 5% per wheel notch.
        onWheel: event => {
            // The other way round: wheel (or fingers) down, up a step.
            const delta = -(event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x);
            root.setLevel(root.level + delta / 120 * 0.05);
        }
    }

    BarCard {
        id: card

        owner: root
        ownerHovered: mouse.containsMouse
        cardOffset: root.cardOffset
        bounds: root.bounds
        pointerY: mouse.y + mouse.mouseY
        cardWidth: Theme.sp(240) + padding * 2

        Column {
            spacing: Theme.sp(4)

            Item {
                width: parent.width
                height: title.implicitHeight

                StyledText {
                    id: title

                    text: "Brightness"
                    font.pixelSize: Theme.size.titleSmall
                    font.weight: Font.Medium
                }

                StyledText {
                    anchors.right: parent.right
                    anchors.baseline: title.baseline
                    text: `${Math.round(root.level * 100)}%`
                    font.pixelSize: Theme.size.labelMedium
                    font.features: {
                        "tnum": 1
                    }
                    color: Theme.m3onSurfaceVariant
                }
            }

            Item {
                width: parent.width
                height: 40

                MaterialIcon {
                    id: low

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "brightness_low"
                    size: 20
                    color: Theme.m3onSurfaceVariant
                }

                ValueSlider {
                    anchors.left: low.right
                    anchors.leftMargin: Theme.sp(8)
                    anchors.right: high.left
                    anchors.rightMargin: Theme.sp(8)
                    anchors.verticalCenter: parent.verticalCenter
                    height: 36
                    from: 0.01
                    to: 1
                    value: root.level
                    onMoved: value => root.setLevel(value)
                }

                MaterialIcon {
                    id: high

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "brightness_high"
                    size: 20
                    color: Theme.m3onSurfaceVariant
                }
            }
        }
    }
}
