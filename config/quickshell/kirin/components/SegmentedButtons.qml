import QtQuick
import qs.components
import qs.services

// M3 single-select segmented button.
// options: [{ value, label }]; emits selected(value).
Row {
    id: root

    property var options: []
    property var current
    signal selected(var value)

    spacing: -1

    Repeater {
        model: root.options

        Rectangle {
            id: segment

            required property var modelData
            required property int index
            readonly property bool active: modelData.value === root.current
            readonly property bool first: index === 0
            readonly property bool last: index === root.options.length - 1

            implicitWidth: Math.max(content.implicitWidth + Theme.sp(24), 88)
            implicitHeight: Math.max(40, content.implicitHeight + Theme.sp(16))
            color: active ? Theme.m3secondaryContainer : "transparent"
            border.width: 1
            border.color: Theme.m3outline
            topLeftRadius: first ? 20 : 0
            bottomLeftRadius: first ? 20 : 0
            topRightRadius: last ? 20 : 0
            bottomRightRadius: last ? 20 : 0

            Behavior on color {
                CAnim {}
            }

            Row {
                id: content

                anchors.centerIn: parent
                spacing: Theme.sp(8)

                MaterialIcon {
                    visible: segment.active
                    text: "check"
                    size: 18
                    color: Theme.m3onSecondaryContainer
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: segment.modelData.label
                    font.pixelSize: Theme.size.labelLarge
                    font.weight: Font.Medium
                    color: segment.active ? Theme.m3onSecondaryContainer : Theme.m3onSurface
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StateLayer {
                onClicked: root.selected(segment.modelData.value)
            }
        }
    }
}
