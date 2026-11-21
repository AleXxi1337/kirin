pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Hyprland's shortcuts (services/Shortcuts.qml): each with its keys; a click
// on them records new ones (Esc cancels, Backspace turns it off). Groups
// (the arrows, workspace numbers, the wheel) take only modifiers. A clash
// with another shortcut is shown under its title.
ColumnLayout {
    id: root

    // The entry being recorded ("" when none): one at a time.
    property string recording: ""

    spacing: Theme.sp(24)

    Repeater {
        model: Shortcuts.sections

        SettingsSection {
            id: section

            required property var modelData

            title: modelData.title

            Repeater {
                model: section.modelData.items

                SettingsRow {
                    id: row

                    required property var modelData
                    readonly property string keys: {
                        Shortcuts.changed;
                        return Shortcuts.keys(modelData.id);
                    }
                    readonly property var clashes: {
                        Shortcuts.changed;
                        return Shortcuts.clashes(modelData.id);
                    }
                    readonly property bool changedHere: {
                        Shortcuts.changed;
                        return !Shortcuts.isDefault(modelData.id);
                    }

                    icon: modelData.icon
                    title: modelData.title
                    subtitle: clashes.length ? `Also used by: ${clashes.join(", ")}` : modelData.mods ? "Only the modifiers change" : ""

                    trailing: RowLayout {
                        spacing: Theme.sp(4)

                        // Back to the default.
                        Rectangle {
                            visible: row.changedHere
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: width / 2
                            color: "transparent"

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "restart_alt"
                                size: 20
                                color: Theme.m3onSurfaceVariant
                            }

                            StateLayer {
                                onClicked: Shortcuts.reset(row.modelData.id)
                            }
                        }

                        KeyButton {
                            entry: row.modelData
                            keys: row.keys
                            clash: row.clashes.length > 0
                        }
                    }
                }
            }
        }
    }

    SettingsSection {
        title: "Not changeable"

        Repeater {
            model: Shortcuts.fixed

            SettingsRow {
                required property var modelData

                icon: "lock"
                title: modelData.title
                trailing: StyledText {
                    text: Shortcuts.pretty(modelData.keys)
                    color: Theme.m3onSurfaceVariant
                }
            }
        }

        SettingsRow {
            icon: "lock"
            title: "Volume, brightness, media"
            trailing: StyledText {
                text: "Media keys"
                color: Theme.m3onSurfaceVariant
            }
        }
    }

    FilledButton {
        Layout.alignment: Qt.AlignRight
        icon: "restart_alt"
        text: "Reset all to defaults"
        onClicked: Shortcuts.resetAll()
    }

    // The keys as a chip; clicked, it records new ones.
    component KeyButton: Rectangle {
        id: button

        required property var entry
        property string keys
        property bool clash: false
        readonly property bool active: root.recording === entry.id

        function start(): void {
            root.recording = entry.id;
            forceActiveFocus();
            Shortcuts.captureStart();
        }

        function stop(): void {
            if (root.recording === entry.id)
                root.recording = "";
            Shortcuts.captureEnd();
        }

        implicitWidth: Math.max(Theme.sp(120), label.implicitWidth + Theme.sp(28))
        implicitHeight: Math.max(36, label.implicitHeight + Theme.sp(14))
        radius: Theme.rounding.small
        color: active ? Theme.m3primaryContainer : Theme.m3surfaceContainerHighest
        border.width: active || clash ? 2 : 0
        border.color: active ? Theme.m3primary : Theme.m3error

        Behavior on color {
            CAnim {}
        }

        StyledText {
            id: label

            anchors.centerIn: parent
            text: button.active ? (button.entry.mods ? "Hold modifiers, press a key" : "Press keys…") : button.keys ? Shortcuts.pretty(button.keys) + (button.entry.suffix ? `  ${button.entry.suffix}` : "") : "Off"
            color: button.active ? Theme.m3onPrimaryContainer : button.keys ? Theme.m3onSurface : Theme.m3onSurfaceVariant
            font.weight: Font.Medium
        }

        StateLayer {
            onClicked: button.active ? button.stop() : button.start()
        }

        // Losing the keyboard ends it.
        onActiveFocusChanged: {
            if (!activeFocus && active)
                stop();
        }

        Keys.onPressed: event => {
            if (!active)
                return;
            event.accepted = true;
            const k = event.key;
            // Modifiers alone: wait for the key.
            if ([Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Hyper_L, Qt.Key_Hyper_R].includes(k))
                return;
            const mods = Shortcuts.modsOf(event.modifiers);
            if (k === Qt.Key_Escape && mods.length === 0) {
                stop();
                return;
            }
            if (k === Qt.Key_Backspace && mods.length === 0) {
                Shortcuts.set(entry.id, "");
                stop();
                return;
            }
            if (entry.mods) {
                // A group: its modifiers (some needed: bare arrows or numbers
                // would be taken from apps).
                if (mods.length === 0)
                    return;
                Shortcuts.set(entry.id, mods.join(" + "));
                stop();
                return;
            }
            const name = Shortcuts.keyNames[event.nativeScanCode];
            if (!name)
                return;
            // A bare letter or digit would be taken from typing.
            if (mods.length === 0 && !/^(F\d+|Print|Insert|Delete|Home|End|Prior|Next)$/.test(name))
                return;
            Shortcuts.set(entry.id, mods.concat([name]).join(" + "));
            stop();
        }
    }
}
