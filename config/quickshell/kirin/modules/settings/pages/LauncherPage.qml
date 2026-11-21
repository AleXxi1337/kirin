import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property var launcher: Config.launcher

    spacing: Theme.sp(24)

    SettingsSection {
        title: "Search"

        SettingsRow {
            icon: "folder_open"
            title: "Search files"
            subtitle: "Find files and folders in your home directory with fd and fzf. Hidden and git-ignored files are skipped."
            trailing: ToggleSwitch {
                checked: root.launcher.files
                onToggled: checked => root.launcher.files = checked
            }
        }

        SettingsRow {
            icon: "travel_explore"
            title: "Web search"
            subtitle: "Offered as the last result"

            SegmentedButtons {
                current: root.launcher.webSearch
                options: [
                    {
                        value: "google",
                        label: "Google"
                    },
                    {
                        value: "duckduckgo",
                        label: "DuckDuckGo"
                    },
                    {
                        value: "none",
                        label: "Off"
                    }
                ]
                onSelected: value => root.launcher.webSearch = value
            }
        }
    }

    SettingsSection {
        title: "Shortcuts"

        SettingsRow {
            icon: "keyboard"
            title: "Open launcher"
            trailing: StyledText {
                // As set in Shortcuts.
                text: {
                    Shortcuts.changed;
                    return Shortcuts.pretty(Shortcuts.keys("launcher"));
                }
                color: Theme.m3onSurfaceVariant
            }
        }

        SettingsRow {
            icon: "keyboard_return"
            title: "Show file in folder"
            trailing: StyledText {
                text: "Ctrl + Enter"
                color: Theme.m3onSurfaceVariant
            }
        }
    }
}
