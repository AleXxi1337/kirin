pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.services

// Notification popups at the top right of the primary monitor, newest on
// top. Each goes after its timeout (not while hovered) and stays in the
// notification centre. Off with do not disturb, except critical ones.
Variants {
    model: Quickshell.screens.filter(s => s.name === Monitors.primary?.name)

    PanelWindow {
        id: window

        required property ShellScreen modelData

        readonly property real cardWidth: Theme.sp(380)
        // Room for the shadow and the slide-in.
        readonly property real pad: Math.max(Theme.sp(8), HyprLook.shadowExtent)

        screen: modelData
        color: "transparent"
        anchors.top: true
        anchors.right: true
        // Hyprland's outer gaps, like windows; the bar isn't on this side.
        // From the screen's top too: the cards sit Hyprland's gap below it,
        // the same as from the right edge.
        margins.top: 0
        // Up to the screen's edge, so a popup sliding out goes off the
        // screen instead of being cut short of it; the cards keep
        // Hyprland's gap from the edge.
        margins.right: 0
        // From the screen's edges: three times Hyprland's outer gaps
        // (gaps_out): well in from the windows' line (a window sits a little
        // past gaps_out, its border and the layout's rounding).
        readonly property real edgeTop: HyprLook.gapsTop * 3
        readonly property real edgeRight: HyprLook.gapsRight * 3
        readonly property real edgeBottom: HyprLook.gapsBottom * 3

        implicitWidth: pad + cardWidth + edgeRight
        // A fixed height, not the cards': resizing the layer surface on every
        // frame of a card unfolding made the animation stutter. The mask
        // keeps the empty part from taking clicks.
        implicitHeight: Math.max(400, (screen?.height ?? 1000) - edgeTop - edgeBottom)
        // Stays a moment after the last one, for its slide-out. From the
        // list of popups, not the ListView's count: a ListView in a hidden
        // window doesn't lay out, so its count never moves off 0.
        // Not while the screen locks: the lock screen is see-through, and
        // a message would show on it (it stays in the centre).
        visible: (Notifs.popups.length > 0 || lingering.running) && !Panels.locking

        Timer {
            id: lingering

            interval: 400
        }

        Connections {
            target: Notifs

            function onPopupsChanged(): void {
                if (Notifs.popups.length === 0)
                    lingering.restart();
            }
        }

        WlrLayershell.namespace: "kirin-notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // Only the cards take input.
        mask: Region {
            x: list.x
            y: scroller.y + window.pad
            width: list.width
            height: scroller.height - window.pad * 2
        }

        // No lower than the media card (and a gap): past that the popups
        // scroll (the wheel), fading out at an edge with more beyond it,
        // as the workspaces do on the bar.
        // The fade past an edge: the cards don't stop short there, they
        // go out over this much.
        readonly property real fade: 20
        // Down to a gap above the media card, the fade included.
        // Within the window too (it stops short of the screen's bottom):
        // past it, the fade was cut off halfway.
        readonly property real room: Math.max(Theme.sp(80), Math.min(window.height, (screen?.height ?? 1000) - Panels.mediaReserve - Theme.sp(12)) - edgeTop)

        Flickable {
            id: scroller

            readonly property bool overflows: contentHeight > height + 1
            readonly property real fade: window.fade

            x: 0
            // Room for the cards' shadows above and below (it clips): the
            // cards start window.pad into it, still at edgeTop.
            y: window.edgeTop - window.pad
            // The window's width: the cards' shadows and slide-out aren't cut.
            width: window.width
            height: Math.min(list.implicitHeight, window.room) + window.pad * 2
            contentWidth: width
            contentHeight: list.implicitHeight + window.pad * 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: overflows

            // Edges with more beyond them fade out (an alpha mask: the
            // popups are over the desktop, no colour to fade into).
            layer.enabled: overflows
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: fadeMask
                // Proportional: the mask's alpha is the popups' (0.5 and 1
                // make the edge a smooth ramp over 0…1; 0 showed all).
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }

        // A Column, not a ListView: it lays out again whenever a card's height
        // settles (text wrapping), where the ListView left cards overlapping.
        Column {
            id: list

            x: window.pad
            y: window.pad
            width: window.cardWidth
            // Each popup carries its gap below it (see entry), so it can fold.
            spacing: 0

            move: Transition {
                Anim {
                    property: "y"
                    type: Anim.DefaultSpatial
                }
            }

            Repeater {
                // Newest on top.
                model: ScriptModel {
                    values: Notifs.popups.slice().reverse()
                }

                // One popup. Going away it slides right and fades, then the
                // room it took folds up (the ones below follow), and only then
                // it's removed: whether by timeout, the close button, a click
                // or an action.
                Item {
                    id: entry

                    required property var modelData
                    property bool leaving: false
                    // 0 … 1 while its room folds up.
                    property real fold: 0
                    readonly property real gap: Theme.sp(8)

                    function leave(after: var): void {
                        if (leaving)
                            return;
                        leaving = true;
                        done = after;
                        away.start();
                    }

                    property var done: null

                    width: list.width
                    // Its own gap below it folds with it, so nothing jumps.
                    height: Math.round((card.implicitHeight + gap) * (1 - fold))
                    // Only while folding (the card has faded by then): during the
                    // slide it would cut the card at its old edge.
                    clip: fold > 0

                    SequentialAnimation {
                        id: away

                        ParallelAnimation {
                            NumberAnimation {
                                target: card
                                property: "x"
                                to: window.cardWidth * 0.5
                                duration: Theme.anim.durations.expressiveDefaultEffects + 100
                                easing.type: Easing.InCubic
                            }
                            NumberAnimation {
                                target: card
                                property: "opacity"
                                to: 0
                                duration: Theme.anim.durations.expressiveDefaultEffects + 100
                                easing.type: Easing.InQuad
                            }
                        }
                        NumberAnimation {
                            target: entry
                            property: "fold"
                            to: 1
                            duration: Theme.anim.durations.expressiveDefaultEffects + 100
                            easing.type: Easing.InOutCubic
                        }
                        ScriptAction {
                            script: {
                                if (entry.done)
                                    entry.done();
                            }
                        }
                    }

                    WindowShadow {
                        target: card
                    }

                    NotificationCard {
                        id: card

                        width: parent.width
                        height: implicitHeight
                        notification: entry.modelData
                        popup: true
                        color: Theme.m3surfaceContainer
                        border.width: HyprLook.borderSize
                        border.color: Qt.alpha(Theme.m3outlineVariant, 0x66 / 255)
                        radius: HyprLook.rounding

                        // Actions run at once; the popup animates away after.
                        dismissHandler: () => entry.leave(() => Notifs.dismiss(entry.modelData))
                        activateHandler: () => {
                            const n = entry.modelData;
                            const action = (n?.actions ?? []).find(a => a.identifier === "default");
                            if (action)
                                action.invoke();
                            entry.leave(() => action && !n.resident ? Notifs.dismiss(n) : Notifs.hidePopup(n));
                        }
                        invokeHandler: action => {
                            const n = entry.modelData;
                            action.invoke();
                            entry.leave(() => n.resident ? Notifs.hidePopup(n) : Notifs.dismiss(n));
                        }

                        Component.onCompleted: enter.start()

                        // Slides in from the right.
                        ParallelAnimation {
                            id: enter

                            Anim {
                                target: card
                                property: "x"
                                from: window.cardWidth * 0.6
                                to: 0
                                type: Anim.DefaultSpatial
                            }
                            Anim {
                                target: card
                                property: "opacity"
                                from: 0
                                to: 1
                                type: Anim.DefaultEffects
                            }
                        }
                    }

                    // Goes after its timeout; hovering holds it.
                    Timer {
                        readonly property int timeout: Notifs.timeout(entry.modelData)

                        running: timeout > 0 && !card.hovered && !entry.leaving
                        interval: timeout
                        onTriggered: entry.leave(() => Notifs.hidePopup(entry.modelData))
                    }
                }
            }
        }
        }

        Item {
            id: fadeMask

            visible: false
            layer.enabled: true
            width: scroller.width
            height: scroller.height

            Rectangle {
                id: fadeRect

                anchors.fill: parent
                // The shadow room above and below the cards' line: as the
                // edge (shown at the very top or bottom, faded otherwise).
                readonly property real edge: window.pad / Math.max(1, scroller.height)
                readonly property real ramp: Math.min(0.5 - edge, scroller.fade / Math.max(1, scroller.height))

                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.rgba(0, 0, 0, scroller.atYBeginning ? 1 : 0)
                    }
                    GradientStop {
                        position: fadeRect.edge
                        color: Qt.rgba(0, 0, 0, scroller.atYBeginning ? 1 : 0)
                    }
                    GradientStop {
                        position: fadeRect.edge + fadeRect.ramp
                        color: "black"
                    }
                    GradientStop {
                        position: 1 - fadeRect.edge - fadeRect.ramp
                        color: "black"
                    }
                    GradientStop {
                        position: 1 - fadeRect.edge
                        color: Qt.rgba(0, 0, 0, scroller.atYEnd ? 1 : 0)
                    }
                    // (Smoother than a straight ramp: eased in between.)
                    GradientStop {
                        position: 1
                        color: Qt.rgba(0, 0, 0, scroller.atYEnd ? 1 : 0)
                    }
                }
            }
        }
    }
}
