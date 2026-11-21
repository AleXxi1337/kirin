import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// The media card (modules/media) and the song on the lock screen.
ColumnLayout {
    id: root

    readonly property var media: Config.media

    spacing: Theme.sp(24)

    SettingsSection {
        title: "Player"

        SettingsRow {
            icon: "music_note"
            title: "Media card"
            subtitle: "What's playing at the bottom right of the main monitor: cover, title, controls."
            trailing: ToggleSwitch {
                checked: root.media.enabled
                onToggled: checked => root.media.enabled = checked
            }
        }

        SettingsRow {
            enabled: root.media.enabled
            opacity: enabled ? 1 : 0.38
            icon: "desktop_windows"
            title: "When nothing covers it"
            subtitle: "Always there while no window is over its place: on an empty desktop, or with the windows elsewhere on the screen."
            trailing: ToggleSwitch {
                checked: root.media.onEmptyDesktop
                onToggled: checked => root.media.onEmptyDesktop = checked
            }
        }

        SettingsRow {
            enabled: root.media.enabled && root.media.onEmptyDesktop
            opacity: enabled ? 1 : 0.38
            icon: "pause_circle"
            title: "Paused, it stays"
            subtitle: "Uncovered, after the music is paused."

            SegmentedButtons {
                current: root.media.pausedMinutes
                options: [1, 5, 15, 0].map(n => ({
                            value: n,
                            label: n ? `${n} min` : "Always"
                        }))
                onSelected: value => root.media.pausedMinutes = value
            }
        }

        SettingsRow {
            enabled: root.media.enabled
            opacity: enabled ? 1 : 0.38
            icon: "timer"
            title: "With windows open"
            subtitle: "Shown this long when the song changes or a media key is pressed, and just before a song ends. The pointer on it keeps it."

            SegmentedButtons {
                current: root.media.showSeconds
                options: [5, 10, 15, 30].map(n => ({
                            value: n,
                            label: `${n} s`
                        }))
                onSelected: value => root.media.showSeconds = value
            }
        }
    }

    SettingsSection {
        title: "Lock screen"

        SettingsRow {
            icon: "lock"
            title: "Song on the lock screen"
            subtitle: "The artist and title under the clock."
            trailing: ToggleSwitch {
                checked: root.media.lockScreen
                onToggled: checked => root.media.lockScreen = checked
            }
        }
    }
}
