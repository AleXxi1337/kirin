pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Keyboard, mouse and touchpad: Hyprland's input settings (passed on by
// services/HyprSync.qml, applied at once).
ColumnLayout {
    id: root

    readonly property var input: Config.input

    // Common xkb layouts: id, name.
    readonly property var knownLayouts: [["us", "English (US)"], ["gb", "English (UK)"], ["ru", "Russian"], ["ua", "Ukrainian"], ["by", "Belarusian"], ["kz", "Kazakh"], ["de", "German"], ["fr", "French"], ["es", "Spanish"], ["it", "Italian"], ["pt", "Portuguese"], ["pl", "Polish"], ["cz", "Czech"], ["tr", "Turkish"], ["gr", "Greek"], ["il", "Hebrew"], ["ge", "Georgian"], ["am", "Armenian"], ["az", "Azerbaijani"], ["uz", "Uzbek"], ["jp", "Japanese"], ["kr", "Korean"], ["cn", "Chinese"]]

    function layoutName(id: string): string {
        return knownLayouts.find(l => l[0] === id)?.[1] ?? id;
    }

    function setLayouts(list: var): void {
        input.layouts = list;
    }

    spacing: Theme.sp(24)

    SettingsSection {
        title: "Keyboard"

        SettingsRow {
            icon: "keyboard"
            title: "Layouts"
            subtitle: "The first is on at start: click one to put it first."

            // The layouts in order, each removable (not the last one), and
            // one more to add.
            Flow {
                Layout.fillWidth: true
                spacing: Theme.sp(8)

                Repeater {
                    model: root.input.layouts

                    Rectangle {
                        id: chip

                        required property string modelData
                        required property int index

                        height: Theme.sp(36)
                        width: chipRow.implicitWidth + Theme.sp(24)
                        radius: Theme.rounding.small
                        color: index === 0 ? Theme.m3secondaryContainer : "transparent"
                        border.width: index === 0 ? 0 : 1
                        border.color: Theme.m3outline

                        StateLayer {
                            onClicked: {
                                const rest = root.input.layouts.filter(l => l !== chip.modelData);
                                root.setLayouts([chip.modelData, ...rest]);
                            }
                        }

                        Row {
                            id: chipRow

                            anchors.centerIn: parent
                            spacing: Theme.sp(6)

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.layoutName(chip.modelData)
                                font.pixelSize: Theme.size.labelLarge
                                color: chip.index === 0 ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                            }

                            MaterialIcon {
                                visible: root.input.layouts.length > 1
                                anchors.verticalCenter: parent.verticalCenter
                                text: "close"
                                size: 16
                                color: chip.index === 0 ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setLayouts(root.input.layouts.filter(l => l !== chip.modelData))
                                }
                            }
                        }
                    }
                }

                Dropdown {
                    options: root.knownLayouts.filter(l => !root.input.layouts.includes(l[0])).map(l => ({
                                value: l[0],
                                label: l[1]
                            }))
                    // Not an option: shown as the button's label.
                    current: "Add layout"
                    onSelected: value => {
                        if (value && value !== "Add layout")
                            root.setLayouts([...root.input.layouts, value]);
                    }
                }
            }
        }

        SettingsRow {
            visible: root.input.layouts.length > 1
            icon: "swap_horiz"
            title: "Switch layout with"

            SegmentedButtons {
                current: root.input.switchKeys
                options: [
                    {
                        value: "grp:alt_shift_toggle",
                        label: "Alt+Shift"
                    },
                    {
                        value: "grp:ctrl_shift_toggle",
                        label: "Ctrl+Shift"
                    },
                    {
                        value: "grp:caps_toggle",
                        label: "Caps Lock"
                    },
                    {
                        value: "grp:toggle",
                        label: "Right Alt"
                    }
                ]
                onSelected: value => root.input.switchKeys = value
            }
        }

        SettingsRow {
            icon: "timer"
            title: "Key repeat delay"
            subtitle: "How long a key is held before it repeats."
            trailing: StyledText {
                text: `${root.input.repeatDelay} ms`
                font.features: {
                    "tnum": 1
                }
                color: Theme.m3onSurfaceVariant
            }

            ValueSlider {
                Layout.fillWidth: true
                from: 150
                to: 1000
                stepSize: 25
                value: root.input.repeatDelay
                onMoved: value => root.input.repeatDelay = Math.round(value / 25) * 25
            }
        }

        SettingsRow {
            icon: "speed"
            title: "Key repeat rate"
            subtitle: "Repeats a second while held."
            trailing: StyledText {
                text: `${root.input.repeatRate} /s`
                font.features: {
                    "tnum": 1
                }
                color: Theme.m3onSurfaceVariant
            }

            ValueSlider {
                Layout.fillWidth: true
                from: 10
                to: 60
                stepSize: 1
                value: root.input.repeatRate
                onMoved: value => root.input.repeatRate = Math.round(value)
            }
        }

        SettingsRow {
            icon: "dialpad"
            title: "Num Lock on at start"
            trailing: ToggleSwitch {
                checked: root.input.numlock
                onToggled: checked => root.input.numlock = checked
            }
        }
    }

    SettingsSection {
        title: "Mouse"

        SettingsRow {
            icon: "mouse"
            title: "Pointer speed"
            trailing: StyledText {
                text: root.input.mouseSensitivity > 0 ? `+${root.input.mouseSensitivity.toFixed(1)}` : root.input.mouseSensitivity.toFixed(1)
                font.features: {
                    "tnum": 1
                }
                color: Theme.m3onSurfaceVariant
            }

            ValueSlider {
                Layout.fillWidth: true
                from: -1
                to: 1
                stepSize: 0.1
                value: root.input.mouseSensitivity
                onMoved: value => root.input.mouseSensitivity = Math.round(value * 10) / 10
            }
        }

        SettingsRow {
            icon: "trending_up"
            title: "Acceleration"
            subtitle: "Faster moves go further. Off: the pointer follows the mouse one to one."
            trailing: ToggleSwitch {
                checked: root.input.mouseAcceleration
                onToggled: checked => root.input.mouseAcceleration = checked
            }
        }

        SettingsRow {
            icon: "swap_vert"
            title: "Natural scrolling"
            subtitle: "The content moves with the wheel, as on a phone."
            trailing: ToggleSwitch {
                checked: root.input.mouseNaturalScroll
                onToggled: checked => root.input.mouseNaturalScroll = checked
            }
        }

        SettingsRow {
            icon: "front_hand"
            title: "Left-handed"
            subtitle: "Swaps the left and right buttons."
            trailing: ToggleSwitch {
                checked: root.input.leftHanded
                onToggled: checked => root.input.leftHanded = checked
            }
        }

        SettingsRow {
            icon: "ads_click"
            title: "Focus follows the pointer"
            subtitle: "The window under the pointer gets the keyboard. Off: a click does."
            trailing: ToggleSwitch {
                checked: root.input.focusFollowsMouse
                onToggled: checked => root.input.focusFollowsMouse = checked
            }
        }
    }

    SettingsSection {
        title: "Touchpad"

        SettingsRow {
            icon: "swap_vert"
            title: "Natural scrolling"
            subtitle: "The content moves with the fingers."
            trailing: ToggleSwitch {
                checked: root.input.touchpadNaturalScroll
                onToggled: checked => root.input.touchpadNaturalScroll = checked
            }
        }

        SettingsRow {
            icon: "unfold_more"
            title: "Scroll speed"
            trailing: StyledText {
                text: `${Math.round(root.input.touchpadScrollSpeed * 100)}%`
                font.features: {
                    "tnum": 1
                }
                color: Theme.m3onSurfaceVariant
            }

            ValueSlider {
                Layout.fillWidth: true
                from: 0.1
                to: 2
                stepSize: 0.05
                value: root.input.touchpadScrollSpeed
                onMoved: value => root.input.touchpadScrollSpeed = Math.round(value * 20) / 20
            }
        }

        SettingsRow {
            icon: "touch_app"
            title: "Tap to click"
            trailing: ToggleSwitch {
                checked: root.input.tapToClick
                onToggled: checked => root.input.tapToClick = checked
            }
        }

        SettingsRow {
            icon: "keyboard_hide"
            title: "Off while typing"
            subtitle: "A palm on the touchpad doesn't move the pointer while you type."
            trailing: ToggleSwitch {
                checked: root.input.disableWhileTyping
                onToggled: checked => root.input.disableWhileTyping = checked
            }
        }

        SettingsRow {
            icon: "pan_tool_alt"
            title: "Two-finger click is a right click"
            subtitle: "Off: click the bottom right corner for a right click."
            trailing: ToggleSwitch {
                checked: root.input.twoFingerRightClick
                onToggled: checked => root.input.twoFingerRightClick = checked
            }
        }
    }
}
