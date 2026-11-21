pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.qmlmodels
import Quickshell
import qs.components
import qs.services

// Brightness, sound, network and Bluetooth on one plate: a gear at rest
// (no plate, like the bar's other icons); on hover a plate grows upwards
// from it and they come out above the gear, each
// with its card as before. It stays out while one of their cards is open.
// A click on the gear opens the settings.
Item {
    id: root

    // As the bar gives its modules, for their cards.
    property real barWidth: 0
    property Item bounds: null

    readonly property int iconSize: Math.round(22 * Theme.fontScale)
    // The gear a pixel larger than the bar's icons, and the plate even
    // around it: an odd glyph in it sat a pixel off whichever way it was
    // rounded.
    readonly property int gearSize: iconSize + 1
    readonly property int pad: Theme.sp(5)
    readonly property int gap: Config.bar.moduleSpacing + Theme.sp(4)

    // A card of one of them is on screen (the pointer may be on it, off
    // the bar).
    readonly property bool cardOpen: {
        let item = Panels.barCard?.owner ?? null;
        while (item) {
            if (item === root)
                return true;
            item = item.parent;
        }
        return false;
    }
    readonly property bool wanted: hover.hovered || cardOpen
    property bool open: false

    // 0 at rest … 1 out.
    property real progress: open ? 1 : 0
    readonly property real restHeight: gearSize + pad * 2
    readonly property real outHeight: restHeight + list.implicitHeight + gap

    implicitWidth: gearSize + pad * 2
    implicitHeight: restHeight + (outHeight - restHeight) * progress

    Behavior on progress {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    // Opens at once; closes a moment after the pointer leaves, so passing
    // between the icons and their cards doesn't fold it.
    onWantedChanged: {
        if (wanted) {
            closeTimer.stop();
            open = true;
        } else {
            closeTimer.restart();
        }
    }

    Timer {
        id: closeTimer

        interval: 350
        onTriggered: root.open = root.wanted
    }

    HoverHandler {
        id: hover
    }

    Rectangle {
        id: plate

        anchors.fill: parent
        radius: width / 2
        color: Theme.m3surfaceContainerHigh
        // At rest the gear is a bar icon like the others; the plate comes
        // with the modules.
        opacity: root.progress
    }

    Item {
        anchors.fill: parent
        clip: true

        // The modules, bottom up from the gear: they rise as the plate
        // grows.
        Column {
            id: list

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: gear.top
            anchors.bottomMargin: root.gap
            spacing: Config.bar.moduleSpacing
            opacity: root.progress
            visible: root.progress > 0

            Repeater {
                model: BarModules.controls

                delegate: DelegateChooser {
                    DelegateChoice {
                        roleValue: "brightness"

                        Brightness {
                            anchors.horizontalCenter: parent?.horizontalCenter
                            cardOffset: (root.barWidth - width) / 2 + HyprLook.gapsLeft
                            bounds: root.bounds
                        }
                    }

                    DelegateChoice {
                        roleValue: "volume"

                        Volume {
                            anchors.horizontalCenter: parent?.horizontalCenter
                            cardOffset: (root.barWidth - width) / 2 + HyprLook.gapsLeft
                            bounds: root.bounds
                        }
                    }

                    DelegateChoice {
                        roleValue: "wifi"

                        Wifi {
                            anchors.horizontalCenter: parent?.horizontalCenter
                            cardOffset: (root.barWidth - width) / 2 + HyprLook.gapsLeft
                            bounds: root.bounds
                        }
                    }

                    DelegateChoice {
                        roleValue: "bluetooth"

                        Bluetooth {
                            anchors.horizontalCenter: parent?.horizontalCenter
                            cardOffset: (root.barWidth - width) / 2 + HyprLook.gapsLeft
                            bounds: root.bounds
                        }
                    }
                }
            }
        }

        // A square around the glyph's ink: it turns about the gear's own
        // middle. The text box is taller than the glyph (the font's line
        // metrics), and turned about its middle the gear wandered off.
        Item {
            id: gear

            x: Math.round((root.width - width) / 2)
            y: root.height - root.pad - height
            width: root.gearSize
            height: root.gearSize
            rotation: root.progress * 90

            // A click opens the settings (the hover opens the plate).
            MouseArea {
                anchors.fill: parent
                anchors.margins: -root.pad
                cursorShape: Qt.PointingHandCursor
                onClicked: Panels.openSettings("")
            }

            // Material Symbols draws each glyph in the middle of its em
            // square, which stands on the baseline: the gear's middle is
            // half the size above the baseline, and half the advance in.
            // (Its ink measured large is off: the optical size differs.)
            MaterialIcon {
                id: gearIcon

                x: Math.round((parent.width - implicitWidth) / 2)
                y: Math.round(parent.height / 2 - baselineOffset + size / 2)
                text: "settings"
                fill: true
                size: root.gearSize
                color: root.open ? Theme.m3primary : Theme.m3onSurface

                Behavior on color {
                    CAnim {}
                }
            }
        }
    }
}
