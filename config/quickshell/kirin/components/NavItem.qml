import QtQuick
import qs.components
import qs.services

// M3 navigation drawer item.
Rectangle {
    id: root

    property string icon
    property string text
    property bool active
    // Draw the active background here; off when a parent draws a sliding indicator.
    property bool background: true
    signal clicked

    implicitHeight: Math.max(56, Theme.size.labelLarge + Theme.sp(36))
    radius: height / 2
    color: active && background ? Theme.m3secondaryContainer : "transparent"

    Behavior on color {
        CAnim {}
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: Theme.sp(16)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.sp(12)

        MaterialIcon {
            text: root.icon
            fill: root.active
            color: root.active ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: root.text
            font.pixelSize: Theme.size.labelLarge
            font.weight: Font.Medium
            color: root.active ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    StateLayer {
        onClicked: root.clicked()
    }
}
