pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property var notifications: Config.notifications

    spacing: Theme.sp(24)

    SettingsSection {
        title: "Popups"

        SettingsRow {
            icon: "send"
            title: "Test notification"
            subtitle: Notifs.dnd ? "Do not disturb is on: it only goes to the notification centre." : "Sends a sample one, with the sound."
            trailing: FilledButton {
                icon: "notifications"
                text: "Send"
                onClicked: Notifs.sendTest()
            }
        }

        SettingsRow {
            icon: "do_not_disturb_on"
            title: "Do not disturb"
            subtitle: "No popups and no sound. Notifications still go to the notification centre; critical ones still show."
            trailing: ToggleSwitch {
                checked: root.notifications.dnd
                onToggled: checked => root.notifications.dnd = checked
            }
        }

        SettingsRow {
            icon: "timer"
            title: "Show for"
            subtitle: "When the app doesn't say. Hovering a popup keeps it."

            SegmentedButtons {
                current: root.notifications.timeout
                options: [4, 6, 10, 15].map(n => ({
                            value: n,
                            label: `${n} s`
                        }))
                onSelected: value => root.notifications.timeout = value
            }
        }
    }
}
