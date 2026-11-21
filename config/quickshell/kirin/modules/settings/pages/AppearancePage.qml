pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property var appearance: Config.appearance

    // Seed colours offered when the scheme doesn't follow the wallpaper.
    readonly property var accents: ["#6750a4", "#0061a4", "#006a6a", "#006e1c", "#5c6300", "#8b5000", "#b3261e", "#984061"]

    spacing: Theme.sp(24)

    // Palette preview.
    SettingsSection {
        title: "Palette"

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Theme.sp(16)
            spacing: Theme.sp(12)

            Repeater {
                model: [
                    {
                        name: "Primary",
                        bg: Theme.m3primary,
                        fg: Theme.m3onPrimary
                    },
                    {
                        name: "Secondary",
                        bg: Theme.m3secondaryContainer,
                        fg: Theme.m3onSecondaryContainer
                    },
                    {
                        name: "Tertiary",
                        bg: Theme.m3tertiaryContainer,
                        fg: Theme.m3onTertiaryContainer
                    },
                    {
                        name: "Surface",
                        bg: Theme.m3surfaceContainerHighest,
                        fg: Theme.m3onSurface
                    }
                ]

                Rectangle {
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: 72
                    radius: Theme.rounding.large
                    color: modelData.bg

                    StyledText {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: Theme.sp(12)
                        text: parent.modelData.name
                        color: parent.modelData.fg
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }

    SettingsSection {
        title: "Colors"

        SettingsRow {
            icon: "palette"
            title: "Source"
            subtitle: Scheme.generating ? "Generating…" : "Generate the color scheme from the wallpaper or from a color you pick"

            SegmentedButtons {
                current: root.appearance.source
                options: [
                    {
                        value: "wallpaper",
                        label: "Wallpaper"
                    },
                    {
                        value: "color",
                        label: "Custom color"
                    }
                ]
                onSelected: value => root.appearance.source = value
            }
        }

        SettingsRow {
            visible: root.appearance.source === "color"
            icon: "colorize"
            title: "Accent color"

            Flow {
                Layout.fillWidth: true
                spacing: Theme.sp(12)

                Repeater {
                    model: root.accents

                    Rectangle {
                        id: swatch

                        required property string modelData
                        readonly property bool active: root.appearance.color.toLowerCase() === modelData

                        width: 40
                        height: 40
                        radius: 20
                        color: modelData
                        border.width: active ? 3 : 0
                        border.color: Theme.m3onSurface

                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: swatch.active
                            text: "check"
                            size: 20
                            color: "white"
                        }

                        StateLayer {
                            color: "white"
                            onClicked: root.appearance.color = swatch.modelData
                        }
                    }
                }
            }
        }

        SettingsRow {
            icon: "dark_mode"
            title: "Mode"

            SegmentedButtons {
                current: root.appearance.mode
                options: [
                    {
                        value: "dark",
                        label: "Dark"
                    },
                    {
                        value: "light",
                        label: "Light"
                    }
                ]
                onSelected: value => root.appearance.mode = value
            }
        }

        SettingsRow {
            icon: "style"
            title: "Style"
            subtitle: "How colorful the scheme is"

            ChipGroup {
                Layout.fillWidth: true
                current: root.appearance.variant
                options: [
                    {
                        value: "tonal-spot",
                        label: "Tonal spot"
                    },
                    {
                        value: "vibrant",
                        label: "Vibrant"
                    },
                    {
                        value: "expressive",
                        label: "Expressive"
                    },
                    {
                        value: "fidelity",
                        label: "Fidelity"
                    },
                    {
                        value: "content",
                        label: "Content"
                    },
                    {
                        value: "rainbow",
                        label: "Rainbow"
                    },
                    {
                        value: "fruit-salad",
                        label: "Fruit salad"
                    },
                    {
                        value: "neutral",
                        label: "Neutral"
                    },
                    {
                        value: "monochrome",
                        label: "Monochrome"
                    }
                ]
                onSelected: value => root.appearance.variant = value
            }
        }
    }

    SettingsSection {
        title: "Text"

        SettingsRow {
            id: fontRow

            property bool picking: false

            icon: "font_download"
            title: "Font"
            subtitle: root.appearance.fontFamily === "sans-serif" ? "System default" : root.appearance.fontFamily
            trailing: FilledButton {
                icon: fontRow.picking ? "close" : "edit"
                text: fontRow.picking ? "Done" : "Change"
                onClicked: {
                    fontRow.picking = !fontRow.picking;
                    fontSearch.text = "";
                }
            }

            // Font picker: search field and the installed families, each shown in itself.
            ColumnLayout {
                visible: fontRow.picking
                Layout.fillWidth: true
                spacing: Theme.sp(8)

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Math.max(48, fontSearch.implicitHeight + Theme.sp(24))
                    radius: Theme.rounding.extraLarge
                    color: Theme.m3surfaceContainerHighest

                    MaterialIcon {
                        id: fontSearchIcon

                        anchors.left: parent.left
                        anchors.leftMargin: Theme.sp(16)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "search"
                        color: Theme.m3onSurfaceVariant
                    }

                    TextInput {
                        id: fontSearch

                        anchors.left: fontSearchIcon.right
                        anchors.leftMargin: Theme.sp(12)
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.sp(16)
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.m3onSurface
                        font.family: Theme.font.family
                        font.pixelSize: Theme.size.bodyLarge
                        clip: true

                        StyledText {
                            visible: !fontSearch.text
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search fonts"
                            color: Theme.m3onSurfaceVariant
                            font.pixelSize: Theme.size.bodyLarge
                        }
                    }
                }

                ListView {
                    id: fontList

                    readonly property var families: {
                        const q = fontSearch.text.trim().toLowerCase();
                        const all = Qt.fontFamilies().filter(f => !f.startsWith("Material Symbols") && (!q || f.toLowerCase().includes(q)));
                        return q ? all : ["sans-serif", ...all];
                    }

                    Layout.fillWidth: true
                    Layout.preferredHeight: 280
                    clip: true
                    boundsBehavior: Flickable.DragAndOvershootBounds

                    TouchpadScroll {
                        flickable: fontList
                    }
                    model: families

                    delegate: Rectangle {
                        id: fontItem

                        required property string modelData
                        readonly property bool active: root.appearance.fontFamily === modelData

                        width: ListView.view.width
                        height: Math.max(44, label.implicitHeight + Theme.sp(16))
                        radius: Theme.rounding.medium
                        color: active ? Theme.m3secondaryContainer : "transparent"

                        StyledText {
                            id: label

                            anchors.left: parent.left
                            anchors.leftMargin: Theme.sp(16)
                            anchors.right: check.left
                            anchors.rightMargin: Theme.sp(8)
                            anchors.verticalCenter: parent.verticalCenter
                            text: fontItem.modelData === "sans-serif" ? "System default" : fontItem.modelData
                            font.family: fontItem.modelData
                            font.pixelSize: Theme.size.bodyLarge
                            elide: Text.ElideRight
                            color: fontItem.active ? Theme.m3onSecondaryContainer : Theme.m3onSurface
                        }

                        MaterialIcon {
                            id: check

                            anchors.right: parent.right
                            anchors.rightMargin: Theme.sp(16)
                            anchors.verticalCenter: parent.verticalCenter
                            visible: fontItem.active
                            text: "check"
                            color: Theme.m3onSecondaryContainer
                        }

                        StateLayer {
                            onClicked: root.appearance.fontFamily = fontItem.modelData
                        }
                    }
                }
            }
        }

        SettingsRow {
            icon: "format_size"
            title: "Text size"
            subtitle: "Body text; headings and labels scale with it"
            trailing: StyledText {
                text: `${root.appearance.fontSize} pt`
                color: Theme.m3onSurfaceVariant
            }

            ValueSlider {
                Layout.fillWidth: true
                from: 8
                to: 16
                stepSize: 0.5
                value: root.appearance.fontSize
                onMoved: value => root.appearance.fontSize = value
            }
        }
    }

    SettingsSection {
        title: "Layout"

        SettingsRow {
            icon: "padding"
            title: "Spacing"
            subtitle: "Paddings and gaps in shell windows"
            trailing: StyledText {
                text: `${Math.round(root.appearance.spacing * 100)}%`
                color: Theme.m3onSurfaceVariant
            }

            ValueSlider {
                Layout.fillWidth: true
                from: 0.5
                to: 1.5
                stepSize: 0.05
                value: root.appearance.spacing
                onMoved: value => root.appearance.spacing = Math.round(value * 100) / 100
            }
        }

        SettingsRow {
            icon: "animation"
            title: "Animation speed"
            subtitle: "Shell and window animations; Off disables them"
            trailing: StyledText {
                text: root.appearance.animationSpeed > 0 ? `${root.appearance.animationSpeed}×` : "Off"
                color: Theme.m3onSurfaceVariant
            }

            ValueSlider {
                Layout.fillWidth: true
                from: 0
                to: 2
                stepSize: 0.25
                value: root.appearance.animationSpeed
                onMoved: value => root.appearance.animationSpeed = value
            }
        }

        SettingsRow {
            icon: "rounded_corner"
            title: "Corner radius"
            trailing: StyledText {
                text: `${Math.round(root.appearance.rounding * 100)}%`
                color: Theme.m3onSurfaceVariant
            }

            ValueSlider {
                Layout.fillWidth: true
                from: 0
                to: 1.5
                stepSize: 0.05
                value: root.appearance.rounding
                onMoved: value => root.appearance.rounding = Math.round(value * 100) / 100
            }
        }

        SettingsRow {
            icon: "interests"
            title: "Icon shape"
            subtitle: "Backgrounds of icons in notifications and the launcher, from square to round"
            trailing: Row {
                spacing: Theme.sp(8)

                // Preview at the current shape.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 28
                    radius: Theme.iconRadius(width)
                    color: Theme.m3primaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "notifications"
                        fill: true
                        size: 16
                        color: Theme.m3onPrimaryContainer
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: `${Math.round(root.appearance.iconRoundness * 100)}%`
                    color: Theme.m3onSurfaceVariant
                }
            }

            ValueSlider {
                Layout.fillWidth: true
                from: 0
                to: 1
                stepSize: 0.05
                value: root.appearance.iconRoundness
                onMoved: value => root.appearance.iconRoundness = Math.round(value * 100) / 100
            }
        }
    }
}
