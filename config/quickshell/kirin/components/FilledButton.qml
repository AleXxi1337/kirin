import QtQuick
import qs.services

// M3 tonal button with an optional leading icon.
Rectangle {
    id: root

    property string icon
    property string text
    signal clicked

    implicitWidth: content.implicitWidth + (icon ? 40 : 48)
    implicitHeight: Math.max(40, content.implicitHeight + Theme.sp(16))
    radius: height / 2
    color: Theme.m3secondaryContainer

    Row {
        id: content

        anchors.centerIn: parent
        spacing: Theme.sp(8)

        MaterialIcon {
            visible: root.icon
            text: root.icon
            size: 18
            color: Theme.m3onSecondaryContainer
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: root.text
            font.pixelSize: Theme.size.labelLarge
            font.weight: Font.Medium
            color: Theme.m3onSecondaryContainer
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    StateLayer {
        color: Theme.m3onSecondaryContainer
        onClicked: root.clicked()
    }
}
