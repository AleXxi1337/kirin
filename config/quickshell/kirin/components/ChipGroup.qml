import QtQuick
import qs.components
import qs.services

// Single-select row of M3 filter chips that wraps onto new lines.
// options: [{ value, label }]; emits selected(value).
Flow {
    id: root

    property var options: []
    property var current
    signal selected(var value)

    spacing: Theme.sp(8)

    Repeater {
        model: root.options

        Rectangle {
            id: chip

            required property var modelData
            readonly property bool active: modelData.value === root.current

            implicitWidth: content.implicitWidth + Theme.sp(active ? 24 : 32)
            implicitHeight: Math.max(32, content.implicitHeight + Theme.sp(12))
            radius: Theme.rounding.small
            color: active ? Theme.m3secondaryContainer : "transparent"
            border.width: active ? 0 : 1
            border.color: Theme.m3outlineVariant

            Behavior on implicitWidth {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            Row {
                id: content

                anchors.centerIn: parent
                spacing: Theme.sp(8)

                MaterialIcon {
                    visible: chip.active
                    text: "check"
                    size: 18
                    color: Theme.m3onSecondaryContainer
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: chip.modelData.label
                    font.pixelSize: Theme.size.labelLarge
                    font.weight: Font.Medium
                    color: chip.active ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StateLayer {
                onClicked: root.selected(chip.modelData.value)
            }
        }
    }
}
