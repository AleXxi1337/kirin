pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland

// What happens while nobody uses the machine (Settings → Power), like
// macOS: on battery the screen dims, then turns off, then the machine locks
// (the lock screen does that on its way to sleep: modules/lock/Lock.qml)
// and sleeps; asleep, it hibernates once the battery runs low (systemd,
// nixos-config modules/sleep.nix). On mains, nothing. Any input undoes the
// dimming and turns the screen back on. Apps asking to keep the screen on
// (video, calls: Wayland idle inhibitors) hold it all off.
Singleton {
    id: root

    readonly property var settings: Config.power.idle
    // On battery only (on mains too while trying the steps out).
    readonly property bool active: Power.unplugged || settings.onMains

    // Minutes from the last input to each step; 0 if it never comes. A step
    // turned off (0) is skipped: the next one counts from the one before.
    readonly property real dimAt: Math.max(0, settings.dimAfter)
    readonly property real offAt: settings.offAfter > 0 ? dimAt + settings.offAfter : 0
    readonly property real sleepAt: settings.sleepAfter > 0 ? dimAt + Math.max(0, settings.offAfter) + settings.sleepAfter : 0

    // The screen on or off. Back on, the cursor is made anew: after DPMS
    // Hyprland's hardware cursor stayed invisible, so for a moment it's
    // drawn in software, then back to how it was set.
    // kirin turned the screen off (and must turn it on).
    property bool screenOff: false

    function screen(on: bool): void {
        screenOff = !on;
        const lua = on ? `hl.dispatch(hl.dsp.dpms({ action = "on" }))
            local was = hl.get_config("cursor.no_hardware_cursors")
            hl.config({ cursor = { no_hardware_cursors = 1 } })
            hl.timer(function() hl.config({ cursor = { no_hardware_cursors = was } }) end, { timeout = 300, type = "oneshot" })` : `hl.dispatch(hl.dsp.dpms({ action = "off" }))`;
        Quickshell.execDetached(["hyprctl", "eval", lua]);
    }

    // Plugged in mid-way: everything back at once.
    onActiveChanged: {
        if (active)
            return;
        if (restore >= 0) {
            Backlight.fadeTo(restore);
            restore = -1;
        }
        if (screenOff)
            screen(true);
    }

    // --- Dim -----------------------------------------------------------------

    // The brightness to go back to; -1: not dimmed.
    property real restore: -1

    IdleMonitor {
        id: dim

        enabled: root.active && root.dimAt > 0
        respectInhibitors: true
        timeout: Math.round(root.dimAt * 60)

        onIsIdleChanged: {
            if (isIdle) {
                if (Backlight.available && Backlight.level > root.settings.dimLevel) {
                    root.restore = Backlight.level;
                    Backlight.fadeTo(root.settings.dimLevel);
                }
            } else if (root.restore >= 0) {
                Backlight.fadeTo(root.restore);
                root.restore = -1;
            }
        }
    }

    // --- Screen off ----------------------------------------------------------

    IdleMonitor {
        id: off

        enabled: root.active && root.offAt > 0
        respectInhibitors: true
        timeout: Math.round(root.offAt * 60)

        onIsIdleChanged: root.screen(!isIdle)
    }

    // --- Sleep ---------------------------------------------------------------

    IdleMonitor {
        id: sleepMonitor

        enabled: root.active && root.sleepAt > 0
        respectInhibitors: true
        timeout: Math.round(root.sleepAt * 60)

        onIsIdleChanged: {
            if (isIdle)
                root.sleep();
        }
    }

    // Sleeps the way the lid and the power button do (logind's action is
    // suspend-then-hibernate where hibernation is set up); the lock screen
    // comes on first, on logind's signal.
    function sleep(): void {
        Quickshell.execDetached(["sh", "-c", "systemctl suspend-then-hibernate 2>/dev/null || systemctl suspend"]);
    }
}
