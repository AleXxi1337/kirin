import QtQuick
import qs.services

// Small M3 filled text field for whole numbers, with an optional suffix
// ("mm"). Emits edited(value) when editing finishes with a valid number.
Rectangle {
    id: root

    property int value
    property string suffix
    property int from: 0
    property int to: 100000
    signal edited(int value)

    implicitWidth: Math.max(Theme.sp(72), row.implicitWidth + Theme.sp(24))
    implicitHeight: Math.max(36, input.implicitHeight + Theme.sp(16))
    radius: Theme.rounding.small
    color: Theme.m3surfaceContainerHighest
    border.width: input.activeFocus ? 2 : 0
    border.color: Theme.m3primary

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Theme.sp(4)

        TextInput {
            id: input

            text: String(root.value)
            color: Theme.m3onSurface
            selectionColor: Theme.m3primary
            selectedTextColor: Theme.m3onPrimary
            font.family: Theme.font.family
            font.pixelSize: Theme.size.bodyLarge
            horizontalAlignment: TextInput.AlignRight
            selectByMouse: true
            validator: IntValidator {
                bottom: root.from
                top: root.to
            }
            onEditingFinished: {
                const v = parseInt(text);
                if (!isNaN(v) && v !== root.value)
                    root.edited(v);
                text = Qt.binding(() => String(root.value));
            }
        }

        StyledText {
            visible: root.suffix
            anchors.baseline: input.baseline
            text: root.suffix
            color: Theme.m3onSurfaceVariant
        }
    }
}
