import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property var power: Config.power

    spacing: Theme.sp(24)

    SettingsSection {
        title: "Power mode"

        SettingsRow {
            icon: Power.options.find(o => o.value === Power.profile)?.icon ?? "bolt"
            title: "Power profile"
            subtitle: {
                if (!Power.available)
                    return "No power profile service is running. Enable services.power-profiles-daemon (or services.tuned with ppdSupport) in NixOS.";
                if (Power.error !== "")
                    return `Couldn't switch to ${Power.label(Power.failed)}: ${Power.error}`;
                return Power.options.find(o => o.value === Power.profile)?.description ?? "";
            }

            SegmentedButtons {
                visible: Power.available
                current: Power.profile
                options: Power.options.map(o => ({
                            value: o.value,
                            label: o.label
                        }))
                onSelected: value => Power.set(value)
            }
        }
    }

    SettingsSection {
        visible: Power.hasBattery
        title: "On battery"

        SettingsRow {
            icon: "power_off"
            title: "Power saver when unplugged"
            subtitle: "The previous profile comes back when plugged in, unless you change it in between."
            trailing: ToggleSwitch {
                checked: root.power.saverOnBattery
                onToggled: checked => root.power.saverOnBattery = checked
            }
        }

        SettingsRow {
            icon: "battery_alert"
            title: "Power saver on low battery"
            subtitle: `Below ${root.power.lowLevel}%, also when \"Power saver when unplugged\" is off.`
            trailing: ToggleSwitch {
                checked: root.power.saverWhenLow
                onToggled: checked => root.power.saverWhenLow = checked
            }

            SegmentedButtons {
                visible: root.power.saverWhenLow
                current: root.power.lowLevel
                options: [10, 15, 20, 30].map(n => ({
                            value: n,
                            label: `${n}%`
                        }))
                onSelected: value => root.power.lowLevel = value
            }
        }
    }

    SettingsSection {
        title: "Battery health"
        visible: Power.hasBattery && (Power.health !== null || Power.limit !== null)

        Component.onCompleted: {
            Power.readHealth();
            Power.readLimit();
        }

        // Only where the laptop has a charge limit (UPower finds one).
        SettingsRow {
            visible: Power.limit !== null
            icon: "battery_saver"
            title: "Preserve battery health"
            subtitle: {
                const l = Power.limit;
                if (!l)
                    return "";
                if (Power.limitError)
                    return `Couldn't change it: ${Power.limitError}`;
                if (Power.limitMismatch)
                    return `On, but the battery didn't take it: it still charges to ${l.kernelEnd}%.`;
                if (Config.power.fullChargeOnce)
                    return "Charging to 100% this time; the limit comes back when you unplug.";
                return `Stops charging at ${l.end}%: kept full on the charger, a battery wears out sooner.`;
            }
            trailing: ToggleSwitch {
                checked: (Power.limit?.enabled ?? false) || Config.power.fullChargeOnce
                onToggled: checked => {
                    Config.power.fullChargeOnce = false;
                    Power.setLimit(checked);
                }
            }
        }

        SettingsRow {
            visible: Power.limit !== null && ((Power.limit?.enabled ?? false) || Config.power.fullChargeOnce)
            icon: "battery_charging_full"
            title: "Charge to 100% once"
            subtitle: "For a trip: the limit is lifted until you unplug the charger."
            trailing: FilledButton {
                text: Config.power.fullChargeOnce ? "Cancel" : "Charge"
                onClicked: Power.chargeFullOnce(!Config.power.fullChargeOnce)
            }
        }

        SettingsRow {
            icon: "battery_profile"
            title: "Health"
            subtitle: {
                const h = Power.health;
                if (!h)
                    return "";
                const state = h.percent >= 80 ? "Normal wear" : h.percent >= 60 ? "Worn: noticeably less time on battery" : "Heavily worn: consider replacing it";
                return `${state}. It holds ${h.full.toFixed(1)} ${h.unit} when full, ${h.design.toFixed(1)} ${h.unit} when new.`;
            }
            trailing: StyledText {
                text: `${Power.health?.percent ?? 0}%`
                font.pixelSize: Theme.size.titleMedium
                font.weight: Font.Medium
                font.features: {
                    "tnum": 1
                }
                color: (Power.health?.percent ?? 100) < 60 ? Theme.m3error : Theme.m3onSurface
            }
        }

        SettingsRow {
            visible: (Power.health?.cycles ?? 0) > 0
            icon: "autorenew"
            title: "Charge cycles"
            subtitle: "Full charges used up, counted in parts. Laptop batteries are usually rated for 500–1000."
            trailing: StyledText {
                text: `${Power.health?.cycles ?? 0}`
                font.features: {
                    "tnum": 1
                }
                color: Theme.m3onSurfaceVariant
            }
        }
    }

    SettingsSection {
        title: "Lock screen"

        SettingsRow {
            icon: "lock_open"
            title: "No password"
            subtitle: "The lock screen still shows its clock (on logging in, locking from the power menu, before sleep); a key or a click opens it. Anyone with the laptop gets in."
            trailing: ToggleSwitch {
                checked: root.power.noPassword
                onToggled: checked => root.power.noPassword = checked
            }
        }
    }

    SettingsSection {
        title: "Sleep"

        SettingsRow {
            enabled: !root.power.noPassword
            opacity: enabled ? 1 : 0.38
            icon: "lock_clock"
            title: "Password after sleep"
            subtitle: "The screen locks before any sleep. Woken sooner than this, it opens by itself; locked before the sleep, it always asks."

            SegmentedButtons {
                current: root.power.passwordAfterSleep
                options: [0, 1, 5, 15].map(n => ({
                            value: n,
                            label: n ? `${n} min` : "At once"
                        }))
                onSelected: value => root.power.passwordAfterSleep = value
            }
        }
    }

    SettingsSection {
        title: "When idle on battery"

        // A summary of the steps, in minutes from the last input.
        SettingsRow {
            icon: "schedule"
            title: "What happens"
            subtitle: {
                const steps = [];
                if (Idle.dimAt > 0)
                    steps.push(`at ${Idle.dimAt} min the screen dims`);
                if (Idle.offAt > 0)
                    steps.push(`at ${Idle.offAt} it turns off`);
                if (Idle.sleepAt > 0)
                    steps.push(`at ${Idle.sleepAt} the laptop locks and sleeps, and hibernates once its battery runs low`);
                const text = steps.length ? steps.join(", ") : "nothing";
                return `${text.charAt(0).toUpperCase()}${text.slice(1)}. On mains, nothing. Videos and calls keep it awake.`;
            }
        }

        SettingsRow {
            icon: "brightness_medium"
            title: "Dim the screen after"

            SegmentedButtons {
                current: root.power.idle.dimAfter
                options: [0, 5, 10, 15, 30].map(n => ({
                            value: n,
                            label: n ? `${n} min` : "Never"
                        }))
                onSelected: value => root.power.idle.dimAfter = value
            }
        }

        SettingsRow {
            icon: "brightness_low"
            title: "Dimmed to"
            enabled: root.power.idle.dimAfter > 0
            opacity: enabled ? 1 : 0.38

            SegmentedButtons {
                current: Math.round(root.power.idle.dimLevel * 100)
                options: [10, 20, 30, 50].map(n => ({
                            value: n,
                            label: `${n}%`
                        }))
                onSelected: value => root.power.idle.dimLevel = value / 100
            }
        }

        SettingsRow {
            icon: "desktop_access_disabled"
            title: "Then turn the screen off after"

            SegmentedButtons {
                current: root.power.idle.offAfter
                options: [0, 1, 2, 5, 10].map(n => ({
                            value: n,
                            label: n ? `${n} min` : "Never"
                        }))
                onSelected: value => root.power.idle.offAfter = value
            }
        }

        SettingsRow {
            icon: "bedtime"
            title: "Then lock and sleep after"
            subtitle: "The lid and the power button sleep too; with another monitor connected, closing the lid only turns the laptop's screen off."

            SegmentedButtons {
                current: root.power.idle.sleepAfter
                options: [0, 5, 15, 30, 60].map(n => ({
                            value: n,
                            label: n ? `${n} min` : "Never"
                        }))
                onSelected: value => root.power.idle.sleepAfter = value
            }
        }
    }
}
