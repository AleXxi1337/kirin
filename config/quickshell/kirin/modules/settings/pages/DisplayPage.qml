import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services
import qs.modules.settings

ColumnLayout {
    id: root

    spacing: Theme.sp(24)

    Component.onCompleted: Monitors.refresh()

    // Smoothly scrolls the settings page so `item` is in view near the top.
    function reveal(item: Item): void {
        let flick = parent;
        while (flick && flick.contentY === undefined)
            flick = flick.parent;
        if (!flick)
            return;
        const y = item.mapToItem(flick.contentItem, 0, 0).y - Theme.sp(16);
        scroll.target = flick;
        scroll.to = Math.max(0, Math.min(y, flick.contentHeight - flick.height));
        scroll.restart();
    }

    Anim {
        id: scroll

        property: "contentY"
        type: Anim.Standard
    }

    // A mode or rotation change starts a trial: bring its confirmation into view.
    Connections {
        target: Monitors

        function onTrialStarted(): void {
            // After the banner is laid out.
            Qt.callLater(() => {
                root.reveal(trialBanner);
                bannerIn.restart();
            });
        }
    }

    // After a mode or rotation change: confirm, or it's reverted (Monitors.setOutput).
    Rectangle {
        id: trialBanner

        visible: Monitors.trialActive
        Layout.fillWidth: true
        implicitHeight: trialRow.implicitHeight + Theme.sp(24)
        radius: Theme.rounding.card
        color: Theme.m3tertiaryContainer

        // Pops in to catch the eye.
        ParallelAnimation {
            id: bannerIn

            Anim {
                target: trialBanner
                property: "scale"
                from: 0.94
                to: 1
                type: Anim.DefaultSpatial
            }
            Anim {
                target: trialBanner
                property: "opacity"
                from: 0
                to: 1
                type: Anim.DefaultEffects
            }
        }

        RowLayout {
            id: trialRow

            anchors.fill: parent
            anchors.leftMargin: Theme.sp(16)
            anchors.rightMargin: Theme.sp(12)
            spacing: Theme.sp(16)

            MaterialIcon {
                text: "timer"
                color: Theme.m3onTertiaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: "Keep these display settings?"
                    font.pixelSize: Theme.size.bodyLarge
                    font.weight: Font.Medium
                    color: Theme.m3onTertiaryContainer
                }

                StyledText {
                    text: `Reverting in ${Monitors.trialSeconds} s`
                    color: Theme.m3onTertiaryContainer
                }
            }

            FilledButton {
                icon: "undo"
                text: "Revert"
                onClicked: Monitors.revert()
            }

            FilledButton {
                icon: "check"
                text: "Keep"
                onClicked: Monitors.keep()
            }
        }
    }

    SettingsSection {
        title: "Arrangement"

        SettingsRow {
            icon: "drag_pan"
            title: "Monitor positions"
            subtitle: arrangement.dirty ? "Not applied yet" : "Drag the monitors; they snap to each other's sides, edges and centres. Saved for this combination of monitors."
            trailing: [
                FilledButton {
                    visible: arrangement.dirty
                    icon: "undo"
                    text: "Revert"
                    onClicked: arrangement.reload()
                },
                FilledButton {
                    visible: arrangement.dirty
                    icon: "check"
                    text: "Apply"
                    onClicked: arrangement.apply()
                }
            ]

            MonitorArrangement {
                id: arrangement

                Layout.fillWidth: true
            }
        }
    }

    // Layouts are remembered per combination of monitors.
    SettingsSection {
        title: "Saved layouts"
        visible: Object.keys(Config.display.profiles).length > 0

        Repeater {
            model: Object.keys(Config.display.profiles).sort()

            SettingsRow {
                required property string modelData
                readonly property bool current: modelData === Monitors.profileKey
                readonly property int count: modelData.split(" + ").length

                icon: current ? "check_circle" : "view_quilt"
                // Port suffixes of identical monitors are an implementation detail.
                title: modelData.split(" + ").map(id => id.replace(/@[^@]*$/, "")).join("  +  ")
                subtitle: `${count} ${count === 1 ? "monitor" : "monitors"}${current ? " · in use now" : ""}`
                trailing: FilledButton {
                    icon: "delete"
                    text: "Forget"
                    onClicked: {
                        const profiles = Object.assign({}, Config.display.profiles);
                        delete profiles[modelData];
                        Config.display.profiles = profiles;
                    }
                }
            }
        }
    }

    SettingsSection {
        title: "Scale"

        SettingsRow {
            icon: "zoom_in"
            title: "Scale"
            subtitle: Config.display.physicalSizes ? "Scale of the primary monitor. The others follow, so things are the same physical size on every screen. Fractional scales can make X11 apps blurry." : "Scale of every monitor. Fractional scales can make X11 apps blurry."

            SegmentedButtons {
                current: Config.display.scale
                options: [1, 1.25, 1.5, 1.75, 2].map(v => ({
                            value: v,
                            label: `${v * 100}%`
                        }))
                onSelected: value => Config.display.scale = value
            }
        }

        SettingsRow {
            icon: "straighten"
            title: "Take real monitor sizes into account"
            subtitle: "Each monitor gets the scale that makes things the same physical size as on the primary one, and the arrangement uses their real sizes. Off: one scale for all monitors, arranged by their pixels."
            trailing: ToggleSwitch {
                checked: Config.display.physicalSizes
                onToggled: checked => Config.display.physicalSizes = checked
            }
        }
    }

    SettingsSection {
        title: "Monitors"

        Repeater {
            model: Monitors.active

            SettingsRow {
                id: monitorRow

                required property var modelData
                readonly property var size: Monitors.physicalSize(modelData)
                readonly property var density: Monitors.density(modelData)

                function setSize(width: int, height: int): void {
                    const physical = Object.assign({}, Config.display.physical);
                    physical[modelData.description] = {
                        width,
                        height
                    };
                    Config.display.physical = physical;
                }

                icon: "desktop_windows"
                title: `${modelData.name}${density ? ` · ${density.inches.toFixed(1)}″` : ""}`
                subtitle: [modelData.description, `${modelData.width}×${modelData.height}`, modelData.refreshRate ? `${Math.round(modelData.refreshRate)} Hz` : "", density ? `${Math.round(density.ppi)} PPI` : ""].filter(s => s).join(" · ")
                trailing: [
                    StyledText {
                        text: `${Math.round(Monitors.scaleFor(monitorRow.modelData) * 100)}%`
                        color: Theme.m3onSurfaceVariant
                    },
                    // The primary monitor sets the scale for the others.
                    Rectangle {
                        visible: Monitors.idOf(monitorRow.modelData) === Monitors.primaryId
                        implicitWidth: primaryLabel.implicitWidth + Theme.sp(24)
                        implicitHeight: Math.max(32, primaryLabel.implicitHeight + Theme.sp(12))
                        radius: Theme.rounding.small
                        color: Theme.m3primaryContainer

                        StyledText {
                            id: primaryLabel

                            anchors.centerIn: parent
                            text: "★ Primary"
                            color: Theme.m3onPrimaryContainer
                            font.weight: Font.Medium
                        }
                    },
                    FilledButton {
                        visible: Monitors.idOf(monitorRow.modelData) !== Monitors.primaryId && !Monitors.mirrorSource(monitorRow.modelData)
                        icon: "star"
                        text: "Make primary"
                        onClicked: Monitors.setPrimary(Monitors.idOf(monitorRow.modelData))
                    }
                ]

                // Mode and rotation, as a trial that reverts unless kept.
                Flow {
                    id: modeRow

                    readonly property string id: Monitors.idOf(monitorRow.modelData)
                    readonly property var target: Monitors.target(monitorRow.modelData)
                    readonly property var modes: Monitors.modes(monitorRow.modelData)
                    readonly property string resolution: `${target.width}x${target.height}`

                    Layout.fillWidth: true
                    spacing: Theme.sp(8)

                    Dropdown {
                        options: {
                            const seen = {};
                            return modeRow.modes.filter(m => !seen[`${m.width}x${m.height}`] && (seen[`${m.width}x${m.height}`] = true)).map(m => ({
                                        value: `${m.width}x${m.height}`,
                                        label: `${m.width} × ${m.height}`
                                    }));
                        }
                        current: modeRow.resolution
                        // The fastest refresh rate of the new resolution.
                        onSelected: value => {
                            const best = modeRow.modes.find(m => `${m.width}x${m.height}` === value);
                            if (best && value !== modeRow.resolution)
                                Monitors.setOutput(modeRow.id, {
                                    mode: best.mode
                                });
                        }
                    }

                    Dropdown {
                        options: modeRow.modes.filter(m => `${m.width}x${m.height}` === modeRow.resolution).map(m => ({
                                    value: m.mode,
                                    label: `${m.refresh.toFixed(2)} Hz`
                                }))
                        // Hyprland reports the rate with more decimals than the mode list.
                        current: options.reduce((best, o) => {
                            const rate = parseFloat(o.value.split("@")[1]);
                            return !best || Math.abs(rate - modeRow.target.refreshRate) < Math.abs(parseFloat(best.split("@")[1]) - modeRow.target.refreshRate) ? o.value : best;
                        }, null)
                        onSelected: value => {
                            if (value !== current)
                                Monitors.setOutput(modeRow.id, {
                                    mode: value
                                });
                        }
                    }

                    SegmentedButtons {
                        current: modeRow.target.transform
                        options: [0, 1, 2, 3].map(t => ({
                                    value: t,
                                    label: `${t * 90}°`
                                }))
                        onSelected: value => {
                            if (value !== modeRow.target.transform)
                                Monitors.setOutput(modeRow.id, {
                                    transform: value
                                });
                        }
                    }
                }

                // Mirroring and adaptive sync, also as trials.
                Flow {
                    id: extraRow

                    readonly property string id: Monitors.idOf(monitorRow.modelData)
                    readonly property var target: Monitors.target(monitorRow.modelData)
                    readonly property bool vrrCapable: Monitors.vrrCapable(monitorRow.modelData)

                    Layout.fillWidth: true
                    spacing: Theme.sp(8)

                    // Extend the desktop, or show a copy of another monitor.
                    // Mirrors can't be mirrored, so a monitor others copy
                    // can only extend.
                    Dropdown {
                        readonly property bool isSource: Monitors.active.some(m => m !== monitorRow.modelData && Monitors.mirrorSource(m) === monitorRow.modelData)

                        options: [
                            {
                                value: "",
                                label: "Extend desktop"
                            }
                        ].concat(isSource ? [] : Monitors.active.filter(m => m !== monitorRow.modelData && !Monitors.target(m).mirror).map(m => ({
                                        value: Monitors.idOf(m),
                                        label: `Mirror ${m.name}`
                                    })))
                        current: Monitors.mirrorSource(monitorRow.modelData) ? extraRow.target.mirror : ""
                        onSelected: value => {
                            if (value !== current)
                                Monitors.setOutput(extraRow.id, {
                                    mirror: value
                                });
                        }
                    }

                    SegmentedButtons {
                        enabled: extraRow.vrrCapable
                        opacity: enabled ? 1 : 0.38
                        current: extraRow.vrrCapable ? extraRow.target.vrr : 0
                        options: [
                            {
                                value: 0,
                                label: "VRR off"
                            },
                            {
                                value: 1,
                                label: "On"
                            },
                            {
                                value: 2,
                                label: "Fullscreen"
                            }
                        ]
                        onSelected: value => {
                            if (value !== extraRow.target.vrr)
                                Monitors.setOutput(extraRow.id, {
                                    vrr: value
                                });
                        }
                    }

                    StyledText {
                        visible: !extraRow.vrrCapable
                        height: 40
                        verticalAlignment: Text.AlignVCenter
                        text: "No adaptive sync on this monitor"
                        color: Theme.m3onSurfaceVariant
                        font.pixelSize: Theme.size.labelMedium
                    }
                }

                // Physical size: from EDID, or corrected by hand (only used
                // with real sizes taken into account).
                RowLayout {
                    visible: Config.display.physicalSizes
                    Layout.fillWidth: true
                    spacing: Theme.sp(8)

                    StyledText {
                        text: "Size"
                        color: Theme.m3onSurfaceVariant
                    }

                    NumberField {
                        value: monitorRow.size.width
                        suffix: "mm"
                        from: 1
                        onEdited: value => monitorRow.setSize(value, monitorRow.size.height || Math.round(value * monitorRow.modelData.height / monitorRow.modelData.width))
                    }

                    StyledText {
                        text: "×"
                        color: Theme.m3onSurfaceVariant
                    }

                    NumberField {
                        value: monitorRow.size.height
                        suffix: "mm"
                        from: 1
                        onEdited: value => monitorRow.setSize(monitorRow.size.width || Math.round(value * monitorRow.modelData.width / monitorRow.modelData.height), value)
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: monitorRow.size.manual ? "Set by hand" : monitorRow.size.width > 0 ? "From the monitor (EDID)" : "Unknown — enter it if you know it"
                        color: Theme.m3onSurfaceVariant
                        font.pixelSize: Theme.size.labelMedium
                        elide: Text.ElideRight
                    }

                    FilledButton {
                        visible: monitorRow.size.manual
                        icon: "restart_alt"
                        text: "Use EDID"
                        onClicked: {
                            const physical = Object.assign({}, Config.display.physical);
                            delete physical[monitorRow.modelData.description];
                            Config.display.physical = physical;
                        }
                    }
                }
            }
        }
    }
}
