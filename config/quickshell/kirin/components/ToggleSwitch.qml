import QtQuick
import qs.components
import qs.services

// M3 switch. Controlled: emits toggled(), the owner updates `checked`.
Item {
    id: root

    property bool checked
    signal toggled(bool checked)

    implicitWidth: 52
    implicitHeight: 32

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.m3primary : Theme.m3surfaceContainerHighest
        border.width: root.checked ? 0 : 2
        border.color: Theme.m3outline

        Behavior on color {
            CAnim {}
        }
    }

    Rectangle {
        id: thumb

        property real diameter: mouse.pressed ? 28 : root.checked ? 24 : 16
        // The centre is animated, not x: x also depends on the (animated)
        // diameter, and a Behavior on x restarted on every frame of the size
        // change, so the thumb stalled midway after a click.
        property real center: root.checked ? root.width - root.height / 2 : root.height / 2

        width: diameter
        height: diameter
        radius: diameter / 2
        x: center - diameter / 2
        anchors.verticalCenter: parent.verticalCenter
        color: root.checked ? Theme.m3onPrimary : Theme.m3outline

        Behavior on center {
            Anim {
                type: Anim.FastSpatial
            }
        }
        Behavior on diameter {
            Anim {
                type: Anim.FastSpatial
            }
        }
        Behavior on color {
            CAnim {}
        }

        // Hover halo, drawn behind the thumb.
        Rectangle {
            z: -1
            anchors.centerIn: parent
            width: 40
            height: 40
            radius: 20
            color: root.checked ? Theme.m3primary : Theme.m3onSurface
            opacity: mouse.pressed ? 0.1 : mouse.containsMouse ? 0.08 : 0
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: "check"
            size: 16
            color: Theme.m3onPrimaryContainer
            opacity: root.checked ? 1 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
