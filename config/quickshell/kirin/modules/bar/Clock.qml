pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.services

// The bar's clock: hours over minutes. Hovering slides out a card with the
// time in large type, the day of the week and a month calendar that can be
// paged with the arrows or by scrolling.
Item {
    id: root

    // From the clock's right edge to where the card starts, set by the bar.
    property real cardOffset: 0
    // The card stays within this item (the bar).
    property Item bounds: null

    implicitWidth: digits.implicitWidth
    implicitHeight: digits.implicitHeight

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Column {
        id: digits

        anchors.centerIn: parent
        spacing: -Math.round(6 * Theme.fontScale)

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, "HH")
            font.pixelSize: Math.round(19 * Theme.fontScale)
            font.weight: Font.ExtraBold
            color: card.open ? Theme.m3primary : Theme.m3onSurface

            Behavior on color {
                CAnim {}
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, "mm")
            font.pixelSize: Math.round(19 * Theme.fontScale)
            font.weight: Font.Bold
            color: Theme.m3onSurfaceVariant
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        anchors.margins: -Theme.sp(8)
        hoverEnabled: true
    }

    BarCard {
        id: card

        owner: root
        ownerHovered: mouse.containsMouse
        cardOffset: root.cardOffset
        bounds: root.bounds
        pointerY: mouse.y + mouse.mouseY
        // Back to the current month next time.
        onClosed: calendar.reset()

        Column {
            spacing: Theme.sp(4)

            // Time and day.
            StyledText {
                text: Qt.formatTime(clock.date, "HH:mm")
                font.pixelSize: Math.round(44 * Theme.fontScale)
                font.weight: Font.Medium
                color: Theme.m3onSurface
            }

            Row {
                spacing: Theme.sp(6)

                StyledText {
                    text: Qt.formatDate(clock.date, "dddd")
                    font.pixelSize: Theme.size.titleMedium
                    font.weight: Font.Medium
                    color: Theme.m3primary
                }

                StyledText {
                    anchors.baseline: parent.children[0].baseline
                    text: Qt.formatDate(clock.date, "d MMMM yyyy")
                    font.pixelSize: Theme.size.bodyMedium
                    color: Theme.m3onSurfaceVariant
                }
            }

            Item {
                width: 1
                height: Theme.sp(12)
            }

            // Month calendar, weeks starting on Monday.
            Column {
                id: calendar

                readonly property int cell: Math.round(32 * Theme.fontScale) + Theme.sp(4)
                // Month shown: year and 0-based month.
                property int year: clock.date.getFullYear()
                property int month: clock.date.getMonth()
                readonly property bool current: year === clock.date.getFullYear() && month === clock.date.getMonth()

                // 6 weeks × 7 days from the Monday on or before the 1st.
                readonly property var days: {
                    const first = new Date(year, month, 1);
                    const lead = (first.getDay() + 6) % 7;
                    const out = [];
                    for (let i = 0; i < 42; i++)
                        out.push(new Date(year, month, 1 - lead + i));
                    return out;
                }

                // Pages by `step` months; the grid slides in from that side.
                function shift(step: int): void {
                    const d = new Date(year, month + step, 1);
                    year = d.getFullYear();
                    month = d.getMonth();
                    slide.from = step > 0 ? Theme.sp(24) : -Theme.sp(24);
                    slideIn.restart();
                }

                function reset(): void {
                    year = Qt.binding(() => clock.date.getFullYear());
                    month = Qt.binding(() => clock.date.getMonth());
                }

                width: cell * 7
                spacing: Theme.sp(4)

                // Header: month and year, back to today, previous/next.
                Item {
                    width: parent.width
                    height: Math.max(prev.height, monthLabel.implicitHeight)

                    StyledText {
                        id: monthLabel

                        anchors.left: parent.left
                        anchors.leftMargin: Theme.sp(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDate(new Date(calendar.year, calendar.month, 1), "MMMM yyyy")
                        font.pixelSize: Theme.size.titleSmall
                        font.weight: Font.Medium
                        color: Theme.m3onSurface
                    }

                    // Shown away from the current month.
                    Rectangle {
                        id: today

                        anchors.right: prev.left
                        anchors.rightMargin: Theme.sp(4)
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: todayLabel.implicitWidth + Theme.sp(20)
                        implicitHeight: Math.max(28, todayLabel.implicitHeight + Theme.sp(8))
                        radius: height / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.m3outline
                        opacity: calendar.current ? 0 : 1
                        visible: opacity > 0

                        Behavior on opacity {
                            Anim {
                                type: Anim.FastEffects
                            }
                        }

                        StyledText {
                            id: todayLabel

                            anchors.centerIn: parent
                            text: "Today"
                            font.pixelSize: Theme.size.labelMedium
                            font.weight: Font.Medium
                            color: Theme.m3primary
                        }

                        StateLayer {
                            color: Theme.m3primary
                            onClicked: {
                                const forward = clock.date > new Date(calendar.year, calendar.month, 1);
                                calendar.reset();
                                slide.from = forward ? Theme.sp(24) : -Theme.sp(24);
                                slideIn.restart();
                            }
                        }
                    }

                    component NavButton: Item {
                        id: nav

                        property string icon
                        signal clicked

                        implicitWidth: Math.max(32, navIcon.implicitWidth + Theme.sp(8))
                        implicitHeight: implicitWidth

                        // Round state layer.
                        Rectangle {
                            id: navShape

                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"

                            StateLayer {
                                onClicked: nav.clicked()
                            }
                        }

                        MaterialIcon {
                            id: navIcon

                            anchors.centerIn: parent
                            text: nav.icon
                            size: Theme.size.titleMedium + 6
                            color: Theme.m3onSurfaceVariant
                        }
                    }

                    NavButton {
                        id: prev

                        anchors.right: next.left
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "chevron_left"
                        onClicked: calendar.shift(-1)
                    }

                    NavButton {
                        id: next

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "chevron_right"
                        onClicked: calendar.shift(1)
                    }
                }

                // Weekday initials.
                Row {
                    Repeater {
                        model: 7

                        StyledText {
                            required property int index

                            width: calendar.cell
                            horizontalAlignment: Text.AlignHCenter
                            // 2024-01-01 was a Monday.
                            text: Qt.formatDate(new Date(2024, 0, 1 + index), "ddd").slice(0, 2)
                            font.pixelSize: Theme.size.labelMedium
                            font.weight: Font.Medium
                            color: index >= 5 ? Theme.m3tertiary : Theme.m3onSurfaceVariant
                        }
                    }
                }

                // Days. Scrolling pages through months too.
                Item {
                    width: parent.width
                    height: calendar.cell * 6
                    clip: true

                    Grid {
                        id: grid

                        columns: 7

                        transform: Translate {
                            id: gridShift
                        }

                        ParallelAnimation {
                            id: slideIn

                            Anim {
                                id: slide

                                target: gridShift
                                property: "x"
                                to: 0
                                type: Anim.DefaultSpatial
                            }
                            Anim {
                                target: grid
                                property: "opacity"
                                from: 0
                                to: 1
                                type: Anim.DefaultEffects
                            }
                        }

                        Repeater {
                            model: calendar.days

                            Item {
                                id: day

                                required property var modelData
                                required property int index
                                readonly property bool inMonth: modelData.getMonth() === calendar.month
                                readonly property bool isToday: modelData.toDateString() === clock.date.toDateString()

                                width: calendar.cell
                                height: calendar.cell

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: calendar.cell - Theme.sp(4)
                                    height: width
                                    radius: width / 2
                                    color: day.isToday ? Theme.m3primary : "transparent"
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    text: day.modelData.getDate()
                                    font.pixelSize: Theme.size.bodyMedium
                                    font.weight: day.isToday ? Font.Bold : Font.Normal
                                    color: day.isToday ? Theme.m3onPrimary : day.index % 7 >= 5 ? Theme.m3tertiary : Theme.m3onSurface
                                    opacity: day.inMonth ? 1 : 0.35
                                }
                            }
                        }
                    }

                    // Mouse wheel: a month per notch. Touchpad: a month per
                    // swipe; its momentum is ignored for a moment after paging.
                    WheelHandler {
                        property real total: 0
                        property real lockedUntil: 0

                        onWheel: event => {
                            const now = Date.now();
                            const touchpad = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0;
                            if (touchpad && now < lockedUntil)
                                return;
                            const delta = Math.abs(event.angleDelta.y) >= Math.abs(event.angleDelta.x) ? event.angleDelta.y : event.angleDelta.x;
                            total += delta;
                            if (Math.abs(total) >= 120) {
                                calendar.shift(total > 0 ? -1 : 1);
                                total = 0;
                                if (touchpad)
                                    lockedUntil = now + 350;
                            }
                        }
                    }
                }
            }
        }
    }
}
