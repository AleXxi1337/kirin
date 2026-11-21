pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import ".."

ColumnLayout {
    id: root

    spacing: Theme.sp(24)

    SettingsSection {
        title: "Modules"

        SettingsRow {
            icon: "settings"
            title: "Group controls"
            subtitle: "Brightness, sound, network and Bluetooth behind a gear in the bar, moved as one."
            trailing: ToggleSwitch {
                checked: BarModules.groupOn
                onToggled: checked => Config.bar.groupControls = checked
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.sp(16)
            Layout.rightMargin: Theme.sp(16)
            Layout.topMargin: Theme.sp(8)
            Layout.bottomMargin: Theme.sp(4)
            text: "Drag to reorder, top to bottom as in the bar."
            color: Theme.m3onSurfaceVariant
            wrapMode: Text.Wrap
        }

        ModuleList {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            ids: BarModules.entries
            onMoved: (id, to) => BarModules.moveTo(id, to)
        }
    }

    SettingsSection {
        title: "Layout"

        SettingsRow {
            icon: "format_line_spacing"
            title: "Space between modules"
            subtitle: "The bar's top and bottom margins stay the same."
            trailing: StyledText {
                text: `${Config.bar.moduleSpacing} px`
                font.features: {
                    "tnum": 1
                }
                color: Theme.m3onSurfaceVariant
            }

            ValueSlider {
                Layout.fillWidth: true
                from: 0
                to: 32
                stepSize: 1
                value: Config.bar.moduleSpacing
                onMoved: value => Config.bar.moduleSpacing = Math.round(value)
            }
        }
    }

    SettingsSection {
        title: "Tray"

        SettingsRow {
            icon: "more_horiz"
            title: "Apps in the bar"
            subtitle: "With more tray apps than this, they all go into a card behind ⋯."

            SegmentedButtons {
                current: Config.bar.trayVisible
                options: [1, 2, 3, 4, 5].map(n => ({
                            value: n,
                            label: `${n}`
                        })).concat([
                    {
                        value: 0,
                        label: "All"
                    }
                ])
                onSelected: value => Config.bar.trayVisible = value
            }
        }
    }

    SettingsSection {
        title: "Reset"

        SettingsRow {
            icon: "restart_alt"
            title: "Default modules"
            subtitle: "All modules on, in the original order, grouped controls, 10 px apart."
            trailing: FilledButton {
                text: "Reset"
                onClicked: BarModules.reset()
            }
        }
    }
}
