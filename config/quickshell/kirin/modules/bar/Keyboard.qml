import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.components
import qs.services

// Keyboard layout as a short code ("en", "ru"); clicking switches to the next
// layout. No card. Hyprland reports the layout per keyboard, so the code comes
// from the keyboard that changed last, and a click sets the same layout on all
// keyboards, which keeps them in step (they can drift: Alt+Shift switches only
// the keyboard it's typed on).
Item {
    id: root

    // Layout codes from kb_layout ("us", "ru") and the active one's index.
    property var layouts: []
    property int index: -1

    readonly property string code: {
        const c = layouts[index] ?? "";
        return /^(us|gb)$/.test(c) ? "en" : c;
    }

    // Keyboard to read; "" for the main one.
    function refresh(keyboard: string): void {
        reader.keyboard = keyboard;
        reader.running = true;
    }

    function next(): void {
        if (layouts.length < 2)
            return;
        const target = (index + 1) % layouts.length;
        index = target;
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", String(target)]);
    }

    visible: code !== ""
    // Its size at rest: growing doesn't push the neighbours.
    implicitWidth: label.restWidth
    implicitHeight: label.restHeight

    StyledText {
        id: label

        anchors.centerIn: parent
        text: root.code
        // Grows by its real size (sharp at rest); `scale` only bridges the
        // animation, as in MaterialIcon.
        readonly property int size: Math.round(15 * Theme.fontScale)
        property real shownGrow: mouse.containsMouse ? 1.1 : 1

        font.pixelSize: Math.round(size * (mouse.containsMouse ? 1.1 : 1))
        font.weight: Font.Bold
        color: mouse.containsMouse ? Theme.m3primary : Theme.m3onSurface
        scale: size * shownGrow / font.pixelSize

        property real restWidth: 0
        property real restHeight: 0

        onImplicitWidthChanged: if (font.pixelSize === size)
            restWidth = implicitWidth
        onImplicitHeightChanged: if (font.pixelSize === size)
            restHeight = implicitHeight
        Component.onCompleted: {
            restWidth = implicitWidth;
            restHeight = implicitHeight;
            restY = y;
        }

        // Grown, the letters are moved back onto their centre at rest, as
        // in MaterialIcon (line metrics don't scale evenly, anchors round).
        readonly property real inkCentre: baselineOffset + (ink.tightBoundingRect.y + ink.tightBoundingRect.height / 2) * font.pixelSize / ink.font.pixelSize
        property real restInkCentre: 0
        property real restY: 0

        onInkCentreChanged: if (font.pixelSize === size)
            restInkCentre = inkCentre
        onYChanged: if (font.pixelSize === size)
            restY = y

        font.hintingPreference: Font.PreferNoHinting
        transform: Translate {
            y: label.font.pixelSize === label.size ? 0 : label.restY + label.restInkCentre - (label.y + label.inkCentre)
        }

        TextMetrics {
            id: ink

            font.family: label.font.family
            font.weight: Font.Bold
            font.pixelSize: 240
            text: label.text
        }

        Behavior on color {
            CAnim {}
        }
        Behavior on shownGrow {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        anchors.margins: -Theme.sp(8)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.next()
    }

    Process {
        id: reader

        property string keyboard: ""

        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const keyboards = JSON.parse(text).keyboards ?? [];
                    const k = keyboards.find(k => k.name === reader.keyboard) ?? keyboards.find(k => k.main) ?? keyboards[0];
                    if (!k)
                        return;
                    root.layouts = k.layout.split(",").map(s => s.trim());
                    root.index = k.active_layout_index;
                } catch (e) {
                    console.warn("kirin: can't read hyprctl devices");
                }
            }
        }
    }

    Connections {
        target: Hyprland

        // "activelayout>>keyboard name,layout name"
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "activelayout")
                root.refresh(event.data.split(",")[0]);
            else if (event.name === "configreloaded")
                root.refresh("");
        }
    }
}
