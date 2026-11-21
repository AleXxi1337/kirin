import QtQuick
import QtQuick.Layouts
import qs.services

// A titled card that groups settings rows.
ColumnLayout {
    id: root

    property string title
    default property alias content: rows.data

    Layout.fillWidth: true
    spacing: Theme.sp(8)

    StyledText {
        visible: root.title
        text: root.title
        color: Theme.m3primary
        font.pixelSize: Theme.size.titleSmall
        font.weight: Font.Medium
        Layout.leftMargin: Theme.sp(16)
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: rows.implicitHeight + Theme.sp(8)
        radius: Theme.rounding.card
        color: Theme.m3surfaceContainerHigh

        ColumnLayout {
            id: rows

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Theme.sp(4)
            spacing: 0
        }
    }
}
