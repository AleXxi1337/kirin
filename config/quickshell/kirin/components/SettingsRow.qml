import QtQuick
import QtQuick.Layouts
import qs.services

// One setting: icon, title and description on the left, a control on the right
// (`trailing`), and optionally a wide control underneath (default children).
Item {
    id: root

    property string icon
    property string title
    property string subtitle
    property alias trailing: trailingSlot.data
    default property alias content: below.data

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + Theme.sp(24)

    ColumnLayout {
        id: column

        anchors.fill: parent
        anchors.leftMargin: Theme.sp(16)
        anchors.rightMargin: Theme.sp(16)
        anchors.topMargin: Theme.sp(12)
        anchors.bottomMargin: Theme.sp(12)
        spacing: Theme.sp(12)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.sp(16)

            MaterialIcon {
                visible: root.icon
                text: root.icon
                color: Theme.m3onSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.sp(2)

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.pixelSize: Theme.size.bodyLarge
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle
                    text: root.subtitle
                    color: Theme.m3onSurfaceVariant
                    wrapMode: Text.Wrap
                }
            }

            RowLayout {
                id: trailingSlot

                spacing: Theme.sp(8)
            }
        }

        ColumnLayout {
            id: below

            visible: children.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: root.icon ? 40 : 0
            spacing: Theme.sp(8)
        }
    }
}
