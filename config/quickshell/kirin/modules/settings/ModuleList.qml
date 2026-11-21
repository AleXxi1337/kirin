pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Settings → Bar's list of modules, reordered by dragging. Rows are placed
// by hand rather than by a layout, so the dragged one follows the pointer
// while the others slide out of its way; the new order is saved on
// release. The grouped controls are one entry, taller, with their own list
// inside (this file again), moved among themselves only.
Item {
    id: list

    property var ids: []
    signal moved(string id, int to)

    readonly property real rowHeight: Math.max(56, Theme.size.bodyLarge + Theme.sp(32))

    // Height of an entry: the group, its header and its rows.
    function heightOf(id: string): real {
        return id === "controls" ? rowHeight * (1 + BarModules.groupOrder.length) : rowHeight;
    }

    // Index of the dragged entry, where it would land, and its y.
    property int dragFrom: -1
    property int dragTo: -1
    property real dragY: 0
    // Released: the entry slides into its slot before the order is saved.
    property bool settling: false

    // The indices in their shown order: the dragged one where it would land.
    readonly property var arrangement: {
        const idx = ids.map((_, i) => i);
        if (dragFrom < 0)
            return idx;
        idx.splice(dragFrom, 1);
        idx.splice(dragTo, 0, dragFrom);
        return idx;
    }

    function yOf(index: int): real {
        let y = 0;
        for (const i of arrangement) {
            if (i === index)
                break;
            y += list.heightOf(ids[i]);
        }
        return y;
    }

    // Where the dragged entry lands for its y: the slot whose top is
    // nearest.
    function slotFor(y: real): int {
        const others = ids.map((_, i) => i).filter(i => i !== dragFrom);
        let best = 0, bestDist = Infinity, top = 0;
        for (let k = 0; k <= others.length; k++) {
            const d = Math.abs(y - top);
            if (d < bestDist) {
                bestDist = d;
                best = k;
            }
            if (k < others.length)
                top += list.heightOf(ids[others[k]]);
        }
        return best;
    }

    implicitHeight: ids.reduce((sum, id) => sum + list.heightOf(id), 0)

    Timer {
        id: commit

        interval: 180
        onTriggered: {
            const id = list.ids[list.dragFrom];
            const to = list.dragTo;
            list.dragFrom = -1;
            list.dragTo = -1;
            list.settling = false;
            if (id !== undefined)
                list.moved(id, to);
        }
    }

    Repeater {
        model: list.ids

        Item {
            id: row

            required property string modelData
            required property int index
            readonly property bool isGroup: modelData === "controls"
            readonly property var module: BarModules.info(modelData)
            readonly property bool shown: isGroup || BarModules.isShown(modelData)
            readonly property bool dragged: list.dragFrom === index

            width: list.width
            height: list.heightOf(modelData)
            z: dragged ? 2 : 1
            y: dragged && !list.settling ? list.dragY : list.yOf(index)

            Behavior on y {
                enabled: !row.dragged || list.settling

                Anim {
                    type: Anim.FastSpatial
                }
            }

            Behavior on height {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            // Lifted look while dragged; the group on a plate of its own.
            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: Theme.sp(4)
                anchors.rightMargin: Theme.sp(4)
                radius: Theme.rounding.large
                color: Theme.m3surfaceContainerHighest
                opacity: row.dragged ? 1 : row.isGroup ? 0.6 : 0
                scale: row.dragged && !list.settling ? 1.02 : 1

                Behavior on opacity {
                    Anim {
                        type: Anim.FastEffects
                    }
                }
                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }
            }

            // The row (the group's header) but the switch is the drag area.
            MouseArea {
                id: grab

                property real offset: 0

                x: 0
                y: 0
                width: parent.width - (row.isGroup ? 0 : toggle.width + Theme.sp(24))
                height: list.rowHeight
                hoverEnabled: true
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: mouse => {
                    if (list.dragFrom >= 0)
                        return;
                    offset = mouse.y;
                    list.dragY = row.y;
                    list.dragTo = row.index;
                    list.dragFrom = row.index;
                }
                onPositionChanged: mouse => {
                    if (!pressed || !row.dragged || list.settling)
                        return;
                    const y = row.mapToItem(list, 0, mouse.y).y - offset;
                    list.dragY = Math.max(-list.rowHeight / 3, Math.min(y, list.implicitHeight - row.height + list.rowHeight / 3));
                    list.dragTo = list.slotFor(list.dragY);
                }
                onReleased: row.drop()
                onCanceled: row.drop()
            }

            function drop(): void {
                if (!dragged || list.settling)
                    return;
                list.settling = true;
                commit.restart();
            }

            RowLayout {
                x: Theme.sp(12)
                width: parent.width - Theme.sp(12) - Theme.sp(16)
                height: list.rowHeight
                spacing: Theme.sp(12)
                opacity: row.shown ? 1 : 0.55

                Behavior on opacity {
                    Anim {
                        type: Anim.FastEffects
                    }
                }

                MaterialIcon {
                    text: "drag_indicator"
                    size: 20
                    color: row.dragged || grab.containsMouse ? Theme.m3primary : Theme.m3outline
                }

                MaterialIcon {
                    text: row.module.icon
                    color: Theme.m3onSurfaceVariant
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: row.module.label
                        font.pixelSize: Theme.size.bodyLarge
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: row.isGroup
                        text: "Behind a gear; they come out on hover."
                        font.pixelSize: Theme.size.labelMedium
                        color: Theme.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }

            ToggleSwitch {
                id: toggle

                visible: !row.isGroup
                anchors.right: parent.right
                anchors.rightMargin: Theme.sp(16)
                y: (list.rowHeight - height) / 2
                checked: row.shown
                onToggled: checked => BarModules.setShown(row.modelData, checked)
            }

            // The group's modules: moved among themselves only.
            Loader {
                id: groupList

                active: row.isGroup
                x: Theme.sp(20)
                y: list.rowHeight
                width: parent.width - Theme.sp(20)

                // This file again (an inline component can't hold itself).
                source: "ModuleList.qml"
                onLoaded: item.moved.connect((id, to) => BarModules.moveInGroup(id, to))

                Binding {
                    target: groupList.item
                    property: "ids"
                    value: BarModules.groupOrder
                    when: groupList.status === Loader.Ready
                }
            }
        }
    }
}
