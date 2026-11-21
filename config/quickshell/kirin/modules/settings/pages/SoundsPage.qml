pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// All of kirin's sounds: theme, volume, each event's sound (on/off, which
// one, listen), apps whose notifications stay silent, and a reset.
ColumnLayout {
    id: root

    readonly property var silent: Config.notifications.silentApps ?? []
    // Apps that sent something this session and aren't muted: offered to add.
    readonly property var recentApps: {
        const names = [];
        for (const n of Notifs.list) {
            const name = n.appName ?? "";
            if (name && !names.includes(name) && !Notifs.isSilent(name))
                names.push(name);
        }
        return names;
    }

    function setSilent(list: var): void {
        Config.notifications.silentApps = list;
    }

    spacing: Theme.sp(24)

    // Themes installed since kirin started (e.g. after a rebuild) show up.
    Component.onCompleted: SoundFx.scan()

    component RoundButton: Rectangle {
        id: button

        property string icon
        signal clicked

        implicitWidth: 36
        implicitHeight: 36
        radius: 18
        color: "transparent"

        MaterialIcon {
            anchors.centerIn: parent
            text: button.icon
            fill: true
            size: 22
            color: Theme.m3onSurfaceVariant
        }

        StateLayer {
            onClicked: button.clicked()
        }
    }

    // Pill with a label and a trailing icon (remove / add).
    component AppChip: Rectangle {
        id: chip

        property string label
        property string icon
        property bool filled: false
        signal clicked

        implicitWidth: chipRow.implicitWidth + Theme.sp(12) + Theme.sp(6)
        implicitHeight: 32
        radius: Theme.rounding.small
        color: filled ? Theme.m3secondaryContainer : "transparent"
        border.width: filled ? 0 : 1
        border.color: Theme.m3outline

        Row {
            id: chipRow

            anchors.left: parent.left
            anchors.leftMargin: Theme.sp(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.sp(6)

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                font.pixelSize: Theme.size.labelLarge
                font.weight: Font.Medium
                color: chip.filled ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
            }

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.icon
                size: 18
                color: chip.filled ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
            }
        }

        StateLayer {
            onClicked: chip.clicked()
        }
    }

    SettingsSection {
        title: "General"

        SettingsRow {
            icon: "library_music"
            title: "Sound theme"
            subtitle: "Installed in share/sounds, e.g. kdePackages.ocean-sound-theme. Sounds it lacks come from Freedesktop."
            trailing: Dropdown {
                options: SoundFx.themes.map(t => ({
                            value: t.id,
                            label: t.label
                        }))
                current: SoundFx.theme?.id ?? ""
                onSelected: value => {
                    Config.sounds.theme = value;
                    SoundFx.preview("notification");
                }
            }
        }
    }

    SettingsSection {
        title: "Events"

        // One row per event: which sound, listen, on/off.
        Repeater {
            model: SoundFx.events

            SettingsRow {
                id: eventRow

                required property var modelData
                readonly property string id_: modelData.id
                readonly property bool on: SoundFx.enabled(id_)
                readonly property string defaultName: SoundFx.defaultName(id_)

                icon: modelData.icon
                title: modelData.label
                subtitle: SoundFx.fileFor(id_) ? "" : "No sound for it in this theme; pick one"
                trailing: [
                    Dropdown {
                        implicitWidth: Theme.sp(280)
                        opacity: eventRow.on ? 1 : 0.5
                        // "Default" follows the theme; the rest pin a sound.
                        options: [
                            {
                                value: "",
                                label: eventRow.defaultName ? `Default · ${SoundFx.label(eventRow.defaultName)}` : "Default · none"
                            }
                        ].concat(SoundFx.names.map(n => ({
                                    value: n,
                                    label: SoundFx.label(n)
                                })))
                        current: SoundFx.choice(eventRow.id_)
                        onSelected: value => {
                            SoundFx.setChoice(eventRow.id_, value);
                            SoundFx.preview(eventRow.id_);
                        }
                    },
                    RoundButton {
                        icon: "play_arrow"
                        onClicked: SoundFx.preview(eventRow.id_)
                    },
                    ToggleSwitch {
                        checked: eventRow.on
                        onToggled: checked => SoundFx.setEnabled(eventRow.id_, checked)
                    }
                ]
            }
        }
    }

    SettingsSection {
        title: "Muted apps"

        SettingsRow {
            icon: "notifications_paused"
            title: "No notification sound from"
            subtitle: "For apps that play their own sound (Telegram, Discord), so it isn't heard twice. Their popups still show."

            Flow {
                Layout.fillWidth: true
                spacing: Theme.sp(8)

                Repeater {
                    model: root.silent

                    AppChip {
                        required property string modelData

                        label: modelData
                        icon: "close"
                        filled: true
                        onClicked: root.setSilent(root.silent.filter(a => a !== modelData))
                    }
                }

                StyledText {
                    visible: root.silent.length === 0
                    text: "None"
                    color: Theme.m3onSurfaceVariant
                }
            }
        }

        SettingsRow {
            visible: root.recentApps.length > 0
            icon: "add_alert"
            title: "Add"
            subtitle: "Apps that sent notifications since kirin started."

            Flow {
                Layout.fillWidth: true
                spacing: Theme.sp(8)

                Repeater {
                    model: root.recentApps

                    AppChip {
                        required property string modelData

                        label: modelData
                        icon: "add"
                        onClicked: root.setSilent(root.silent.concat([modelData]))
                    }
                }
            }
        }
    }

    SettingsSection {
        title: "Reset"

        SettingsRow {
            icon: "restart_alt"
            title: "Default sounds"
            subtitle: "Every event back to its default sound and on/off, volume to 60%. The theme and muted apps stay."
            trailing: FilledButton {
                text: "Reset"
                onClicked: SoundFx.reset()
            }
        }
    }
}
