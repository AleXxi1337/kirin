import QtQuick
import qs.components
import qs.services

// Hover/press overlay from M3. Fills its parent and follows its corner radii.
MouseArea {
    id: root

    property color color: Theme.m3onSurface

    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        color: root.color
        radius: root.parent.radius ?? 0
        topLeftRadius: root.parent.topLeftRadius ?? radius
        topRightRadius: root.parent.topRightRadius ?? radius
        bottomLeftRadius: root.parent.bottomLeftRadius ?? radius
        bottomRightRadius: root.parent.bottomRightRadius ?? radius
        opacity: root.pressed ? 0.1 : root.containsMouse ? 0.08 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
