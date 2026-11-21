pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.modules.notifications
import qs.services

// Notification centre: a bell in the bar (with a dot for unread ones, struck
// through with do not disturb). Hovering slides out a card with the
// notifications, newest first, do not disturb and "Clear all".
// Clicking the bell switches do not disturb.
Item {
    id: root

    property real cardOffset: 0
    // The card stays within this item (the bar).
    property Item bounds: null

    implicitWidth: icon.restWidth
    implicitHeight: icon.restHeight

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: Notifs.dnd ? "notifications_off" : Notifs.unread > 0 ? "notifications_unread" : "notifications"
        fill: Notifs.unread > 0 || card.open
        size: 20
        color: Notifs.unread > 0 && !Notifs.dnd ? Theme.m3primary : Theme.m3onSurface
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
        cursorShape: Qt.PointingHandCursor
        onClicked: Config.notifications.dnd = !Config.notifications.dnd
    }

    BarCard {
        id: card

        readonly property real listMax: Theme.sp(480)

        owner: root
        ownerHovered: mouse.containsMouse
        cardOffset: root.cardOffset
        bounds: root.bounds
        pointerY: mouse.y + mouse.mouseY
        cardWidth: Theme.sp(380) + padding * 2
        maxHeight: header.implicitHeight + footer.implicitHeight + Theme.sp(12) * 2 + listMax + padding * 2
        // Cards unfold frame by frame: the card follows instead of animating
        // its height (an animation chasing that would keep restarting).
        animateHeight: false
        // Seen once the centre is open.
        onOpenChanged: {
            if (open)
                Notifs.unread = 0;
        }

        Column {
            spacing: Theme.sp(12)

            Item {
                id: header

                width: parent.width
                implicitHeight: Math.max(title.implicitHeight, 36)

                StyledText {
                    id: title

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications"
                    font.pixelSize: Theme.size.titleMedium
                    font.weight: Font.Medium
                }
            }

            // Empty state.
            Column {
                id: empty

                visible: Notifs.list.length === 0
                // Fades in once the list has gone.
                opacity: visible ? 1 : 0
                width: parent.width

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                topPadding: Theme.sp(16)
                bottomPadding: Theme.sp(20)
                spacing: Theme.sp(8)

                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Notifs.dnd ? "notifications_off" : "notifications_none"
                    size: 40
                    color: Theme.m3outline
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Notifs.dnd ? "Do not disturb is on" : "No notifications"
                    color: Theme.m3onSurfaceVariant
                }
            }

            Flickable {
                id: listView

                // Clear all: the cards slide out one after another, then the
                // list folds up, and only then they're cleared.
                property bool clearing: false
                // 0 … 1 while the list folds (to the empty state's height).
                property real fold: 0
                readonly property int duration: Theme.anim.durations.expressiveDefaultEffects + 100
                readonly property int stagger: 40

                function clearAll(): void {
                    if (clearing)
                        return;
                    clearing = true;
                    clearOut.start();
                }

                SequentialAnimation {
                    id: clearOut

                    // The last card's slide (staggered ones after the 8th go
                    // together, they're out of sight anyway).
                    PauseAnimation {
                        duration: listView.duration + Math.min(entries.count - 1, 8) * listView.stagger
                    }
                    NumberAnimation {
                        target: listView
                        property: "fold"
                        to: 1
                        duration: listView.duration
                        easing.type: Easing.InOutCubic
                    }
                    ScriptAction {
                        script: {
                            Notifs.clear();
                            listView.clearing = false;
                            listView.fold = 0;
                        }
                    }
                }

                visible: Notifs.list.length > 0
                width: parent.width
                // Folding down to the empty state's height, which takes its place.
                height: {
                    const full = Math.min(cards.implicitHeight, card.listMax);
                    return Math.round(full + (empty.implicitHeight - full) * fold);
                }
                contentWidth: width
                contentHeight: cards.implicitHeight
                clip: true
                boundsBehavior: Flickable.DragAndOvershootBounds

                TouchpadScroll {
                    flickable: listView
                }

                Column {
                    id: cards

                    width: listView.width
                    // Each card carries its gap below it, so it can fold.
                    spacing: 0

                    Repeater {
                        id: entries

                        model: ScriptModel {
                            values: Notifs.list
                        }

                        // One card. Dismissed it slides right and fades, then
                        // its room folds up and only then it goes.
                        Item {
                            id: entry

                            required property var modelData
                            required property int index
                            property bool leaving: false
                            property real fold: 0
                            readonly property real gap: index < entries.count - 1 ? Theme.sp(8) : 0

                            width: cards.width
                            height: Math.round((notif.implicitHeight + gap) * (1 - fold))
                            // Only while folding: during the slide it would cut
                            // the card at its old edge.
                            clip: fold > 0

                            function leave(after: var): void {
                                if (leaving)
                                    return;
                                leaving = true;
                                done = after;
                                away.start();
                            }

                            property var done: null

                            Connections {
                                target: listView

                                function onClearingChanged(): void {
                                    if (listView.clearing)
                                        slideOut.start();
                                }
                            }

                            // Clear all: just the slide, the list folds as one.
                            SequentialAnimation {
                                id: slideOut

                                PauseAnimation {
                                    duration: Math.min(entry.index, 8) * listView.stagger
                                }
                                ParallelAnimation {
                                    NumberAnimation {
                                        target: notif
                                        property: "x"
                                        to: cards.width * 0.5
                                        duration: listView.duration
                                        easing.type: Easing.InCubic
                                    }
                                    NumberAnimation {
                                        target: notif
                                        property: "opacity"
                                        to: 0
                                        duration: listView.duration
                                        easing.type: Easing.InQuad
                                    }
                                }
                            }

                            SequentialAnimation {
                                id: away

                                ParallelAnimation {
                                    NumberAnimation {
                                        target: notif
                                        property: "x"
                                        to: cards.width * 0.5
                                        duration: listView.duration
                                        easing.type: Easing.InCubic
                                    }
                                    NumberAnimation {
                                        target: notif
                                        property: "opacity"
                                        to: 0
                                        duration: listView.duration
                                        easing.type: Easing.InQuad
                                    }
                                }
                                NumberAnimation {
                                    target: entry
                                    property: "fold"
                                    to: 1
                                    duration: listView.duration
                                    easing.type: Easing.InOutCubic
                                }
                                ScriptAction {
                                    script: {
                                        if (entry.done)
                                            entry.done();
                                    }
                                }
                            }

                            NotificationCard {
                                id: notif

                                width: cards.width
                                height: implicitHeight
                                notification: entry.modelData

                                dismissHandler: () => entry.leave(() => Notifs.dismiss(entry.modelData))
                                activateHandler: () => {
                                    const n = entry.modelData;
                                    const action = (n?.actions ?? []).find(a => a.identifier === "default");
                                    if (!action) {
                                        Notifs.hidePopup(n);
                                        return;
                                    }
                                    action.invoke();
                                    if (!n.resident)
                                        entry.leave(() => Notifs.dismiss(n));
                                }
                                invokeHandler: action => {
                                    const n = entry.modelData;
                                    action.invoke();
                                    if (!n.resident)
                                        entry.leave(() => Notifs.dismiss(n));
                                }
                            }
                        }
                    }
                }
            }

            // Controls at the bottom (like Android's shade): sound and do not
            // disturb at the left, clear all at the right.
            Item {
                id: footer

                width: parent.width
                implicitHeight: 36

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.sp(4)

                    // Sound on/off.
                    Rectangle {
                        width: 36
                        height: 36
                        radius: 18
                        color: "transparent"

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: SoundFx.enabled("notification") ? "volume_up" : "volume_off"
                            size: 20
                            color: Theme.m3onSurfaceVariant
                        }

                        StateLayer {
                            onClicked: SoundFx.setEnabled("notification", !SoundFx.enabled("notification"))
                        }
                    }

                    // Do not disturb.
                    Rectangle {
                        width: 36
                        height: 36
                        radius: 18
                        color: Notifs.dnd ? Theme.m3primary : "transparent"

                        Behavior on color {
                            CAnim {}
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: Notifs.dnd ? "notifications_off" : "notifications_active"
                            fill: Notifs.dnd
                            size: 20
                            color: Notifs.dnd ? Theme.m3onPrimary : Theme.m3onSurfaceVariant
                        }

                        StateLayer {
                            color: Notifs.dnd ? Theme.m3onPrimary : Theme.m3onSurface
                            onClicked: Config.notifications.dnd = !Config.notifications.dnd
                        }
                    }
                }

                // Clear all.
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Notifs.list.length > 0
                    width: clearLabel.implicitWidth + Theme.sp(24)
                    height: 36
                    radius: 18
                    color: "transparent"

                    StyledText {
                        id: clearLabel

                        anchors.centerIn: parent
                        text: "Clear all"
                        font.pixelSize: Theme.size.labelLarge
                        font.weight: Font.Medium
                        color: Theme.m3primary
                    }

                    StateLayer {
                        color: Theme.m3primary
                        onClicked: listView.clearAll()
                    }
                }
            }
        }
    }
}
