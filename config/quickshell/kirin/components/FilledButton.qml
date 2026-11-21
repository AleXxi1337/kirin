import QtQuick
import qs.services

// M3 tonal button with an optional leading icon. `danger`: in the error
// colour, for what can't be undone.
Rectangle {
    id: root

    property string icon
    property string text
    property bool danger: false
    readonly property color ink: danger ? Theme.m3onError : Theme.m3onSecondaryContainer
    signal clicked

    implicitWidth: content.implicitWidth + (icon ? 40 : 48)
    implicitHeight: Math.max(40, content.implicitHeight + Theme.sp(16))
    radius: height / 2
    color: danger ? Theme.m3error : Theme.m3secondaryContainer

    Row {
        id: content

        anchors.centerIn: parent
        spacing: Theme.sp(8)

        MaterialIcon {
            visible: root.icon
            text: root.icon
            size: 18
            color: root.ink
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: root.text
            font.pixelSize: Theme.size.labelLarge
            font.weight: Font.Medium
            color: root.ink
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    StateLayer {
        color: root.ink
        onClicked: root.clicked()
    }
}
