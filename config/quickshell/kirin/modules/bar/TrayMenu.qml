pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.components
import qs.services

// A tray app's menu (Tray): its entries, submenus opening in place with a
// way back.
Column {
    id: menu

    // The tray app whose menu this is.
    required property SystemTrayItem item
    // An entry was picked.
    signal done

    // Menus from the top one down to the one shown.
    property var stack: []
    readonly property var current: stack.length ? stack[stack.length - 1] : menu.item?.menu ?? null

    function reset(): void {
        stack = [];
    }

    spacing: 0

    QsMenuOpener {
        id: opener

        menu: menu.current
    }

    // App name; in a submenu, the way back.
    Item {
        width: parent.width
        height: Math.max(36, heading.implicitHeight + Theme.sp(12))

        MaterialIcon {
            id: back

            visible: menu.stack.length > 0
            anchors.left: parent.left
            anchors.leftMargin: Theme.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            text: "arrow_back"
            size: 18
            color: Theme.m3onSurfaceVariant
        }

        StyledText {
            id: heading

            anchors.left: back.visible ? back.right : parent.left
            anchors.leftMargin: Theme.sp(8)
            anchors.right: parent.right
            anchors.rightMargin: Theme.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            text: menu.stack.length ? menu.current.text.replace(/_(?!_)/g, "") : menu.item?.tooltipTitle || menu.item?.title || menu.item?.id || ""
            font.pixelSize: Theme.size.labelMedium
            font.weight: Font.Medium
            color: Theme.m3onSurfaceVariant
            elide: Text.ElideRight
        }

        StateLayer {
            visible: menu.stack.length > 0
            onClicked: menu.stack = menu.stack.slice(0, -1)
        }
    }

    Repeater {
        model: opener.children

        Loader {
            id: entryLoader

            required property QsMenuEntry modelData

            width: menu.width
            // Entries go away for a moment while an app rebuilds its menu.
            active: !!modelData
            sourceComponent: modelData?.isSeparator ? separator : entry

            Component {
                id: separator

                Item {
                    height: Theme.sp(9)

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.sp(8)
                        width: entryLoader.width - Theme.sp(16)
                        height: 1
                        color: Theme.m3outlineVariant
                    }
                }
            }

            Component {
                id: entry

                Rectangle {
                    readonly property QsMenuEntry e: entryLoader.modelData

                    height: Math.max(36, label.implicitHeight + Theme.sp(14))
                    radius: Theme.rounding.small
                    color: "transparent"
                    opacity: e?.enabled ? 1 : 0.4

                    // Check box or radio button state.
                    MaterialIcon {
                        id: check

                        visible: parent.e?.buttonType !== QsMenuButtonType.None
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.sp(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.e?.buttonType === QsMenuButtonType.RadioButton ? (parent.e?.checkState === Qt.Checked ? "radio_button_checked" : "radio_button_unchecked") : (parent.e?.checkState === Qt.Checked ? "check_box" : "check_box_outline_blank")
                        size: 18
                        fill: parent.e?.checkState === Qt.Checked
                        color: parent.e?.checkState === Qt.Checked ? Theme.m3primary : Theme.m3onSurfaceVariant
                    }

                    Image {
                        id: entryIcon

                        visible: !check.visible && !!parent.e?.icon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.sp(8)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        source: parent.e?.icon ?? ""
                        sourceSize: Qt.size(36, 36)
                    }

                    StyledText {
                        id: label

                        anchors.left: check.visible ? check.right : entryIcon.visible ? entryIcon.right : parent.left
                        anchors.leftMargin: Theme.sp(check.visible || entryIcon.visible ? 10 : 12)
                        anchors.right: arrow.left
                        anchors.rightMargin: Theme.sp(4)
                        anchors.verticalCenter: parent.verticalCenter
                        // DBus menus mark mnemonics with "_" ("__" is a literal one).
                        text: (parent.e?.text ?? "").replace(/__/g, "\u0000").replace(/_/g, "").replace(/\u0000/g, "_")
                        elide: Text.ElideRight
                    }

                    MaterialIcon {
                        id: arrow

                        anchors.right: parent.right
                        anchors.rightMargin: Theme.sp(6)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "chevron_right"
                        size: 18
                        color: Theme.m3onSurfaceVariant
                        opacity: parent.e?.hasChildren ? 1 : 0
                    }

                    StateLayer {
                        enabled: parent.e?.enabled ?? false
                        onClicked: {
                            const e = parent.e;
                            if (!e)
                                return;
                            if (e.hasChildren) {
                                menu.stack = menu.stack.concat([e]);
                            } else {
                                e.triggered();
                                menu.done();
                            }
                        }
                    }
                }
            }
        }
    }
}
