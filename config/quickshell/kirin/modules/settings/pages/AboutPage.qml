import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services

ColumnLayout {
    id: root

    // The factory reset asked for once: confirming it.
    property bool confirmReset: false

    spacing: Theme.sp(24)

    SettingsSection {
        title: "Configuration"

        SettingsRow {
            icon: "description"
            title: "Config file"
            subtitle: Config.path
            trailing: FilledButton {
                icon: "open_in_new"
                text: "Open"
                onClicked: Apps.open(Config.path)
            }
        }

        SettingsRow {
            icon: "refresh"
            title: "Restart shell"
            subtitle: "Reload kirin's QML files, e.g. after editing the code"
            trailing: FilledButton {
                icon: "restart_alt"
                text: "Restart"
                onClicked: Quickshell.reload(true)
            }
        }

        SettingsRow {
            icon: "settings_backup_restore"
            title: "Factory settings"
            subtitle: root.confirmReset ? "Every setting goes back to its default: appearance, bar, display arrangements, input, shortcuts, sounds, power… The shell restarts. Your wallpaper, files and window places stay." : "All of kirin's settings back to their defaults"
            trailing: [
                FilledButton {
                    visible: !root.confirmReset
                    icon: "settings_backup_restore"
                    text: "Reset"
                    onClicked: root.confirmReset = true
                },
                FilledButton {
                    visible: root.confirmReset
                    text: "Cancel"
                    onClicked: root.confirmReset = false
                },
                FilledButton {
                    visible: root.confirmReset
                    danger: true
                    icon: "warning"
                    text: "Reset everything"
                    onClicked: Config.resetToDefaults()
                }
            ]
        }
    }
}
