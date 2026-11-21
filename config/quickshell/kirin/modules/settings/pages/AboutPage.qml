import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services

ColumnLayout {
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
    }
}
