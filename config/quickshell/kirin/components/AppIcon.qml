import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services

// An app's icon. `themed`: on a plate in the icon shape (Settings →
// Appearance → Icon shape), like Android's themed icons: its one-colour
// symbol (SymbolIcon, Papirus) in the accent colour on a tonal plate. Not
// themed: the app's own icon as it is (the launcher, the notifications),
// the plate only for an app that has no icon at all.
Item {
    id: root

    // The desktop entry, or null; `appId` is tried as well.
    property var entry: null
    property string appId
    property bool selected: false
    property bool critical: false
    // Apps with no symbol of their own: their own icon, as it is, instead of
    // a symbol for their kind. The launcher wants that; the
    // notifications take the kind's symbol.
    property bool ownIconFallback: false
    property bool themed: true
    readonly property bool useOwn: ownSource !== "" && (!themed || (ownIconFallback && !symbol.specific))
    readonly property string ownSource: {
        const icon = entry?.icon ?? appId;
        return icon ? Quickshell.iconPath(icon, true) : "";
    }

    Rectangle {
        visible: !root.useOwn
        anchors.fill: parent
        radius: Theme.iconRadius(width)
        color: root.critical ? Theme.m3error : root.selected ? Theme.m3primary : Theme.m3primaryContainer

        Behavior on color {
            CAnim {}
        }
    }

    SymbolIcon {
        id: symbol

        visible: !root.useOwn
        anchors.centerIn: parent
        width: Math.round(parent.width * 0.6)
        height: width
        entry: root.entry
        appId: root.appId
        color: root.critical ? Theme.m3onError : root.selected ? Theme.m3onPrimary : Theme.m3onPrimaryContainer

        Behavior on color {
            CAnim {}
        }
    }

    // The app's own icon, cut to the icon shape. Icon themes like Colloid
    // draw apps as tiles with a margin round them (6% a side) and corners
    // of their own: drawn 14% larger, the tile fills the shape, and its
    // corners follow the setting from nearly square up to a circle.
    ClippingRectangle {
        visible: root.useOwn
        anchors.fill: parent
        radius: Theme.iconRadius(width)
        color: "transparent"

        // Rendered at exactly its size on screen, on whole pixels: an icon
        // scaled from another size (IconImage's), or placed between pixels,
        // came out blurred.
        Image {
            // 14% larger (Colloid's icons have a 6% margin each side), by an
            // even number of pixels: the same whole-pixel overhang on both
            // sides. An odd one put the picture half a pixel off centre
            // (Math.round(-1.5) is -1) and the circle cut one side more.
            readonly property int size: Math.round(parent.width) + 2 * Math.round(parent.width * 0.07)
            readonly property real dpr: root.Window.window?.devicePixelRatio ?? 1

            x: -(size - Math.round(parent.width)) / 2
            y: -(size - Math.round(parent.height)) / 2
            width: size
            height: size
            source: parent.visible ? root.ownSource : ""
            sourceSize: Qt.size(Math.round(size * dpr), Math.round(size * dpr))
            smooth: true
            asynchronous: true
        }
    }
}
