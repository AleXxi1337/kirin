pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.components
import qs.services

// System tray (StatusNotifierItem). Up to bar.trayVisible apps: their icons
// stacked in the bar (TrayIcon), greyscale until hovered. More: a single
// "⋯" in the bar, and all the apps in a square card beside it, 3 × 3, which
// scrolls when there are more. Click activates an app, middle click is its secondary
// action, right click (or click, for menu-only items) opens its menu
// (TrayMenu): in a card of its own for icons in the bar, in a window of its
// own beside the ⋯ card for the ones in it. Takes no space without tray apps. Apps listed in the
// config's bar.trayHidden are left out.
Column {
    id: root

    property real cardOffset: 0
    // The card stays within this item (the bar).
    property Item bounds: null

    // Without the ones hidden in the config (bar.trayHidden).
    readonly property var items: SystemTray.items.values.filter(i => !(Config.bar.trayHidden ?? []).includes(i.id))
    // More than fit: everything goes into the ⋯ card.
    readonly property bool overflows: Config.bar.trayVisible > 0 && items.length > Config.bar.trayVisible

    // Left, middle and right click on an app.
    function click(item: var, button: int, openMenu: var): void {
        if (button === Qt.MiddleButton)
            item.secondaryActivate();
        else if (button === Qt.RightButton || item.onlyMenu) {
            if (item.hasMenu)
                openMenu();
        } else
            item.activate();
    }

    // A bit more than the bar's own spacing: app icons fill their square,
    // font icons have some room around the shape.
    spacing: Theme.sp(18)
    bottomPadding: Theme.sp(4)

    // --- Few apps: in the bar ------------------------------------------------

    Repeater {
        model: root.overflows ? [] : root.items

        Item {
            id: trayItem

            required property SystemTrayItem modelData
            // Right click asked for the menu; the card opens while the
            // pointer is on the icon or the card.
            property bool menuWanted: false

            anchors.horizontalCenter: parent?.horizontalCenter
            implicitWidth: icon.implicitWidth
            implicitHeight: icon.implicitHeight

            TrayIcon {
                id: icon

                item: trayItem.modelData
                hovered: mouse.containsMouse || card.open
            }

            MouseArea {
                id: mouse

                anchors.fill: parent
                anchors.margins: -Theme.sp(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: event => root.click(trayItem.modelData, event.button, () => {
                        menu.reset();
                        trayItem.menuWanted = true;
                    })
            }

            BarCard {
                id: card

                owner: trayItem
                ownerHovered: trayItem.menuWanted && mouse.containsMouse
                cardOffset: root.cardOffset + (root.width - trayItem.width) / 2
                bounds: root.bounds
                pointerY: mouse.y + mouse.mouseY
                padding: Theme.sp(8)
                cardWidth: Theme.sp(240) + padding * 2
                onClosed: trayItem.menuWanted = false

                TrayMenu {
                    id: menu

                    item: trayItem.modelData
                    onDone: card.close()
                }
            }
        }
    }

    // --- Many apps: ⋯ and a card ---------------------------------------------

    Item {
        id: more

        // The app whose menu is open beside the card, and its slot.
        property var menuItem: null
        property Item menuAnchor: null

        visible: root.overflows
        anchors.horizontalCenter: parent.horizontalCenter
        implicitWidth: 16
        implicitHeight: 16

        MaterialIcon {
            anchors.centerIn: parent
            text: "more_horiz"
            size: 20
            color: moreCard.open ? Theme.m3primary : Theme.m3onSurfaceVariant
            grow: moreCard.open ? 1.1 : 1
            Behavior on color {
                CAnim {}
            }
        }

        MouseArea {
            id: moreMouse

            anchors.fill: parent
            anchors.margins: -Theme.sp(6)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: more.menuItem = null
        }

        BarCard {
            id: moreCard

            readonly property int columns: 3
            readonly property int rows: 3
            readonly property int cell: 36

            owner: more
            ownerHovered: moreMouse.containsMouse
            cardOffset: root.cardOffset + (root.width - more.width) / 2
            bounds: root.bounds
            pointerY: moreMouse.y + moreMouse.mouseY
            padding: Theme.sp(10)
            cardWidth: columns * cell + padding * 2
            // Stays while an app's menu is open beside it.
            pinned: !!more.menuItem
            // Back to the grid next time.
            onClosed: more.menuItem = null

            Item {
                implicitWidth: moreCard.columns * moreCard.cell
                implicitHeight: grid.height

                // All the apps, 3 to a row; scrolls past 3 rows.
                Flickable {
                    id: grid

                    width: parent.width
                    // Always the full 3 × 3: a square, whatever the number of apps.
                    height: moreCard.rows * moreCard.cell
                    contentWidth: width
                    contentHeight: apps.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.DragAndOvershootBounds

                    TouchpadScroll {
                        flickable: grid
                    }

                    Grid {
                        id: apps

                        columns: moreCard.columns

                        Repeater {
                            model: root.overflows ? root.items : []

                            Item {
                                id: cellItem

                                required property SystemTrayItem modelData

                                width: moreCard.cell
                                height: moreCard.cell

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: Theme.rounding.small
                                    color: cellMouse.containsMouse ? Qt.alpha(Theme.m3onSurface, 0.08) : "transparent"
                                }

                                TrayIcon {
                                    anchors.centerIn: parent
                                    item: cellItem.modelData
                                    hovered: cellMouse.containsMouse
                                }

                                MouseArea {
                                    id: cellMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                    onClicked: event => root.click(cellItem.modelData, event.button, () => {
                                            appMenu.reset();
                                            more.menuAnchor = cellItem;
                                            more.menuItem = cellItem.modelData;
                                        })
                                }
                            }
                        }
                    }

                    // Scroll position, while there's something to scroll.
                    Rectangle {
                        visible: grid.contentHeight > grid.height + 1
                        parent: grid
                        anchors.right: parent.right
                        y: grid.visibleArea.yPosition * grid.height
                        width: 3
                        height: Math.max(16, grid.visibleArea.heightRatio * grid.height)
                        radius: 1.5
                        color: Theme.m3outline
                        opacity: grid.moving ? 0.8 : 0.35
                    }
                }
            }
        }

        // An app's menu: a window of its own beside its slot, the card
        // staying up behind it. Closes on picking an entry, on a click
        // elsewhere, and a moment after the pointer has left both it and the
        // card (the click outside isn't always reported for popups).
        PopupWindow {
            id: menuWindow

            readonly property real pad: Math.max(Theme.sp(8), HyprLook.shadowExtent)

            visible: !!more.menuItem && !!more.menuAnchor
            anchor.item: more.menuAnchor
            // Right of the card (past the slot's column and the card's edge).
            anchor.rect.x: more.menuAnchor ? more.menuAnchor.width + (moreCard.columns - 1 - Math.round(more.menuAnchor.x / moreCard.cell)) * moreCard.cell + moreCard.padding + Theme.sp(8) - pad : 0
            anchor.rect.y: -pad
            anchor.edges: Edges.Top | Edges.Left
            anchor.gravity: Edges.Bottom | Edges.Right
            implicitWidth: menuCard.width + pad * 2
            implicitHeight: menuCard.height + pad * 2
            color: "transparent"

            HyprlandFocusGrab {
                active: menuWindow.visible
                windows: [menuWindow]
                onCleared: more.menuItem = null
            }

            Timer {
                running: menuWindow.visible && !menuHover.hovered && !moreCard.pointerIn
                interval: 700
                onTriggered: more.menuItem = null
            }

            WindowShadow {
                target: menuCard
            }

            Rectangle {
                id: menuCard

                HoverHandler {
                    id: menuHover
                }

                x: menuWindow.pad
                y: menuWindow.pad
                width: Theme.sp(240) + Theme.sp(8) * 2
                height: appMenu.implicitHeight + Theme.sp(8) * 2
                radius: HyprLook.rounding
                color: Theme.m3surface
                border.width: HyprLook.borderSize
                border.color: Qt.alpha(Theme.m3outlineVariant, 0x66 / 255)

                TrayMenu {
                    id: appMenu

                    x: Theme.sp(8)
                    y: Theme.sp(8)
                    width: parent.width - Theme.sp(16)
                    item: more.menuItem
                    onDone: more.menuItem = null
                }
            }
        }
    }
}
