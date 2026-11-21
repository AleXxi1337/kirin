pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.services

// M3 exposed dropdown menu. options: [{ value, label }]; emits selected(value).
Item {
    id: root

    property var options: []
    property var current
    signal selected(var value)

    readonly property var currentOption: options.find(o => o.value === current) ?? null

    implicitWidth: Math.max(Theme.sp(150), label.implicitWidth + arrow.width + Theme.sp(36))
    implicitHeight: Math.max(40, label.implicitHeight + Theme.sp(16))

    Rectangle {
        id: field

        anchors.fill: parent
        radius: Theme.rounding.small
        color: Theme.m3surfaceContainerHighest
        border.width: popup.visible ? 2 : 0
        border.color: Theme.m3primary

        StyledText {
            id: label

            anchors.left: parent.left
            anchors.leftMargin: Theme.sp(12)
            anchors.right: arrow.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.currentOption?.label ?? String(root.current ?? "")
            font.pixelSize: Theme.size.bodyLarge
            elide: Text.ElideRight
        }

        MaterialIcon {
            id: arrow

            anchors.right: parent.right
            anchors.rightMargin: Theme.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            text: "arrow_drop_down"
            color: Theme.m3onSurfaceVariant
            rotation: popup.visible ? 180 : 0

            Behavior on rotation {
                Anim {
                    type: Anim.FastSpatial
                }
            }
        }

        StateLayer {
            onClicked: popup.visible ? popup.close() : popup.open()
        }
    }

    Popup {
        id: popup

        y: root.height + 4
        width: Math.max(root.width, Theme.sp(160))
        height: Math.min(list.contentHeight + Theme.sp(16), Theme.sp(320))
        padding: 0
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        onOpened: list.positionViewAtIndex(Math.max(0, root.options.findIndex(o => o.value === root.current)), ListView.Center)

        background: Item {
            WindowShadow {
                target: menuBackground
            }

            Rectangle {
                id: menuBackground

                anchors.fill: parent
                radius: Theme.rounding.small
                color: Theme.m3surfaceContainer
                // Like the shell's other floating surfaces (bar cards, OSD).
                border.width: HyprLook.borderSize
                border.color: Qt.alpha(Theme.m3outlineVariant, 0x66 / 255)
            }
        }

        enter: Transition {
            Anim {
                property: "opacity"
                from: 0
                to: 1
                type: Anim.FastEffects
            }
            Anim {
                property: "scale"
                from: 0.92
                to: 1
                type: Anim.FastSpatial
            }
        }
        exit: Transition {
            Anim {
                property: "opacity"
                to: 0
                type: Anim.FastEffects
            }
        }

        contentItem: ListView {
            id: list

            clip: true
            topMargin: Theme.sp(8)
            bottomMargin: Theme.sp(8)
            boundsBehavior: Flickable.DragAndOvershootBounds

            TouchpadScroll {
                flickable: list
            }
            model: root.options

            delegate: Rectangle {
                id: option

                required property var modelData
                readonly property bool active: modelData.value === root.current

                width: ListView.view.width
                height: Math.max(40, optionLabel.implicitHeight + Theme.sp(16))
                color: active ? Theme.m3secondaryContainer : "transparent"

                StyledText {
                    id: optionLabel

                    anchors.left: parent.left
                    anchors.leftMargin: Theme.sp(16)
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.sp(16)
                    anchors.verticalCenter: parent.verticalCenter
                    text: option.modelData.label
                    font.pixelSize: Theme.size.bodyLarge
                    color: option.active ? Theme.m3onSecondaryContainer : Theme.m3onSurface
                    elide: Text.ElideRight
                }

                StateLayer {
                    onClicked: {
                        root.selected(option.modelData.value);
                        popup.close();
                    }
                }
            }
        }
    }
}
