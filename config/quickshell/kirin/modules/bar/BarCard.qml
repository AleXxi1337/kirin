pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.components
import qs.services

// A card that slides out beside the bar from one of its items (battery,
// clock), floating like a small window: Hyprland's rounding, border and
// shadow (HyprLook). It's up while the pointer is on the item or the card,
// and a moment longer, so the pointer can cross the gap between them.
//
// Put it inside the item:
//     BarCard { owner: item; ownerHovered: mouse.containsMouse; Column { ... } }
// The content is laid out at the card's width minus padding, at the bottom,
// so a card that grows (cardHeight) does so upwards.
//
// The card opens with its middle level with the pointer, kept within
// `bounds` (the bar), and stays there while open.
//
// Only one card is on screen: another one closes first (unless pinned), and
// this one appears once it's gone.
Item {
    id: root

    required property Item owner
    property bool ownerHovered: false
    // From the owner's right edge to where the card starts.
    property real cardOffset: 0

    default property Item contentItem
    property real padding: Theme.sp(16)
    // Card size; by default the content's size plus padding. Animated.
    property real cardWidth: (contentItem?.implicitWidth ?? 0) + padding * 2
    property real cardHeight: (contentItem?.implicitHeight ?? 0) + padding * 2
    // Off for content that animates its own height: the card then follows it
    // frame by frame (an animation of its own would keep restarting and lag).
    property bool animateHeight: true
    // The largest the card gets, so the popup never has to resize.
    property real maxWidth: cardWidth
    property real maxHeight: cardHeight
    // Height the card is centred on the pointer with; it stays where it is
    // when it grows, as long as maxHeight fits.
    property real centerHeight: cardHeight
    // The pointer's height over the owner (owner coordinates).
    property real pointerY: owner.height / 2
    // The card stays within this item's height (the bar).
    property Item bounds: null

    // Where the card's bottom edge is, in owner coordinates; set on opening.
    property real cardBottom: owner.height / 2 + centerHeight / 2
    // Room for the shadow above and below the card. Less near the screen's
    // edges: a popup sticking out of the screen gets moved back in by the
    // compositor, card and all.
    readonly property real shadowRoom: Math.max(Theme.sp(8), HyprLook.shadowExtent)
    property real roomAbove: shadowRoom
    property real roomBelow: shadowRoom

    function place(): void {
        let bottom = pointerY + centerHeight / 2;
        roomAbove = roomBelow = shadowRoom;
        if (bounds) {
            const top = -owner.mapToItem(bounds, 0, 0).y;
            // Room for the largest card below the bar's top, and the bottom
            // above the bar's bottom (which wins if it can't be both).
            bottom = Math.min(Math.max(bottom, top + maxHeight), top + bounds.height);
            // The bar has Hyprland's outer gaps to the screen's edges.
            roomBelow = Math.min(shadowRoom, top + bounds.height - bottom + HyprLook.gapsBottom);
            roomAbove = Math.min(shadowRoom, bottom - maxHeight - top + HyprLook.gapsTop);
        }
        cardBottom = bottom;
        // Where the owner is in the bar's window, which covers the screen's
        // height from its left edge: screen coordinates.
        const p = owner.mapToItem(null, 0, 0);
        ownerX = p.x;
        ownerY = p.y;
    }

    property real ownerX: 0
    property real ownerY: 0

    property int hideDelay: 250
    // Stays up regardless of the pointer (e.g. while typing a password).
    property bool pinned: false
    // Takes the keyboard, for text fields. A click outside ends it:
    // focusLost().
    property bool grabFocus: false
    signal focusLost
    // Clicks on the card's background (not on controls in the content).
    property bool clickable: false
    signal clicked

    readonly property bool pointerIn: ownerHovered || cardHover.hovered
    property bool open: false
    signal closed

    function close(): void {
        hideTimer.stop();
        waiting = false;
        if (open) {
            open = false;
            closed();
        }
    }

    // Wants to open, but another card is still on screen.
    property bool waiting: false

    function show(): void {
        const other = Panels.barCard;
        if (other && other !== root) {
            waiting = true;
            if (!other.pinned)
                other.close();
            return;
        }
        waiting = false;
        if (!open) {
            // The pointer position updates after the hover does.
            Qt.callLater(place);
        }
        Panels.barCard = root;
        open = true;
    }

    onPointerInChanged: {
        if (pointerIn) {
            hideTimer.stop();
            show();
        } else {
            waiting = false;
            hideTimer.restart();
        }
    }

    // The other card is gone: our turn.
    Connections {
        target: Panels

        function onBarCardChanged(): void {
            if (root.waiting && !Panels.barCard && root.pointerIn)
                root.show();
        }
    }

    onContentItemChanged: {
        if (!contentItem)
            return;
        contentItem.parent = body;
        contentItem.width = Qt.binding(() => body.width);
        contentItem.y = Qt.binding(() => body.height - contentItem.height);
    }

    onPinnedChanged: {
        if (!pinned && !pointerIn)
            hideTimer.restart();
    }

    Timer {
        id: hideTimer

        interval: root.hideDelay
        onTriggered: {
            if (!root.pinned)
                root.close();
        }
    }

    // The grab starts a moment after grabFocus, once the click that asked for
    // it is over; started during the click, it ends right away.
    Timer {
        id: grabArmed

        property bool armed: false

        interval: 250
        running: root.grabFocus
        onTriggered: armed = true
    }

    onGrabFocusChanged: {
        if (!grabFocus)
            grabArmed.armed = false;
    }

    // Clicking outside while it has the keyboard.
    HyprlandFocusGrab {
        active: grabArmed.armed && popup.visible
        windows: [popup]
        onCleared: root.focusLost()
    }

    // A layer surface of its own beside the bar, not a popup: popups of the
    // bar can't get the keyboard (the bar never takes it).
    PanelWindow {
        id: popup

        // Room left and right of the card for its shadow and the springy
        // overshoot; above and below see roomAbove/roomBelow.
        readonly property real pad: root.shadowRoom

        screen: root.QsWindow.window?.screen ?? null
        anchors {
            top: true
            left: true
        }
        // The card starts right of the owner (past the bar's edge), its
        // bottom edge at cardBottom.
        margins.left: Math.round(root.ownerX + root.owner.width + root.cardOffset - pad)
        margins.top: Math.round(root.ownerY + root.cardBottom + root.roomBelow - implicitHeight)
        implicitWidth: root.maxWidth + pad * 2
        implicitHeight: root.maxHeight + root.roomAbove + root.roomBelow
        color: "transparent"

        WlrLayershell.namespace: "kirin-bar-card"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: root.grabFocus ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // Only the card takes input; the room around it lets clicks through.
        mask: Region {
            item: card
        }
        // Stays up until the card has faded out.
        visible: root.owner.visible && (root.open || card.opacity > 0)
        onVisibleChanged: {
            if (!visible && Panels.barCard === root)
                Panels.barCard = null;
        }

        WindowShadow {
            target: card
        }

        Rectangle {
            id: card

            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.roomBelow
            x: popup.pad + (root.open ? 0 : -Theme.sp(12))
            width: root.cardWidth
            height: root.cardHeight
            radius: HyprLook.rounding
            color: Theme.m3surface
            border.width: HyprLook.borderSize
            border.color: Qt.alpha(Theme.m3outlineVariant, 0x66 / 255)
            clip: true
            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.94
            transformOrigin: Item.BottomLeft

            Behavior on x {
                Anim {
                    type: Anim.FastSpatial
                }
            }
            Behavior on width {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
            Behavior on height {
                enabled: root.animateHeight

                Anim {
                    type: Anim.DefaultSpatial
                }
            }
            Behavior on scale {
                Anim {
                    type: Anim.FastSpatial
                }
            }
            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }
            Behavior on color {
                CAnim {}
            }

            HoverHandler {
                id: cardHover
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.clickable
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clicked()
            }

            Item {
                id: body

                anchors.fill: parent
                anchors.margins: root.padding
            }
        }
    }
}
