pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Power profiles (power-profiles-daemon, or tuned with its ppd API; read
// through Quickshell's UPower module) and switching them automatically on
// battery (Settings → Power).
Singleton {
    id: root

    // Whether a power profiles service owns the D-Bus name; without it the
    // profile can't change. Checked again periodically and after a failure.
    property bool available: false

    // Why the last switch failed (the daemon's message), or "" when it worked.
    // Kept until the next switch or until the profile changes.
    property string error: ""
    // Profile a failed switch asked for, -1 otherwise.
    property int failed: -1

    readonly property int profile: PowerProfiles.profile
    // Performance needs hardware/driver support; desktops without it get two.
    readonly property var options: [
        {
            value: PowerProfile.PowerSaver,
            label: "Power saver",
            short: "Saver",
            icon: "energy_savings_leaf",
            description: "Longer battery life, slower and quieter"
        },
        {
            value: PowerProfile.Balanced,
            label: "Balanced",
            short: "Balanced",
            icon: "balance",
            description: "Speed when needed, saving otherwise"
        },
        {
            value: PowerProfile.Performance,
            label: "Performance",
            short: "Fast",
            icon: "speed",
            description: "Full speed, more heat and power use"
        }
    ].filter(o => o.value !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)

    readonly property string busName: "org.freedesktop.UPower.PowerProfiles"

    function label(value: int): string {
        return options.find(o => o.value === value)?.label ?? "";
    }

    // Through busctl rather than PowerProfiles.profile, so the daemon's error
    // comes back (the property setter fails silently).
    function set(value: int): void {
        if (!available)
            return;
        const name = value === PowerProfile.PowerSaver ? "power-saver" : value === PowerProfile.Performance ? "performance" : "balanced";
        switcher.target = value;
        switcher.command = ["busctl", "--system", "set-property", busName, "/org/freedesktop/UPower/PowerProfiles", busName, "ActiveProfile", "s", name];
        switcher.running = true;
    }

    function check(): void {
        checker.running = true;
    }

    // --- Automatic power saver ----------------------------------------------
    // Only on transitions (unplugged, dropped below the low level), so a
    // profile picked by hand afterwards is respected. When plugged in again,
    // the profile from before comes back, unless it was changed by hand since.

    readonly property UPowerDevice battery: UPower.displayDevice
    readonly property bool hasBattery: !!battery && battery.ready && battery.isLaptopBattery && battery.isPresent
    // Not "onBattery": QML takes names starting with "on" for signal handlers,
    // and such a property's binding never updated.
    readonly property bool unplugged: hasBattery && UPower.onBattery
    readonly property bool low: unplugged && battery.percentage * 100 < Config.power.lowLevel

    // Profile to restore when plugged in; -1 when kirin didn't switch.
    property int restoreTo: -1
    property int switchedTo: -1

    function saver(): void {
        if (!available || profile === PowerProfile.PowerSaver)
            return;
        if (restoreTo < 0)
            restoreTo = profile;
        switchedTo = PowerProfile.PowerSaver;
        set(PowerProfile.PowerSaver);
    }

    onUnpluggedChanged: {
        // "Charge to 100% once": unplugged, the limit comes back.
        if (unplugged && Config.power.fullChargeOnce) {
            Config.power.fullChargeOnce = false;
            setLimit(true);
        }
        SoundFx.trigger(unplugged ? "unplug" : "plug");
        // Plugged in: the battery warnings come again next time.
        if (!unplugged)
            warned = [];
        if (unplugged) {
            if (Config.power.saverOnBattery)
                saver();
        } else if (restoreTo >= 0) {
            const previous = restoreTo;
            restoreTo = -1;
            switchedTo = -1;
            set(previous);
        }
    }

    onLowChanged: {
        if (low)
            SoundFx.trigger("battery");
        if (low && Config.power.saverWhenLow)
            saver();
    }

    // --- Battery running out -------------------------------------------------
    // While working, only a notification (and its sound) at each of these
    // levels, once per discharge: nothing else is done. Asleep, the machine
    // hibernates once the battery runs low (nixos-config modules/sleep.nix);
    // UPower hibernates it at 2% as a last resort.
    readonly property var warnLevels: [10, 5]
    readonly property int percent: hasBattery ? Math.round(battery.percentage * 100) : 100
    // Levels already warned of this discharge.
    property var warned: []

    onPercentChanged: {
        if (!unplugged)
            return;
        for (const level of warnLevels) {
            if (percent <= level && !warned.includes(level)) {
                warned = warned.concat([level]);
                const critical = level === Math.min(...warnLevels);
                Notifs.send("Battery", critical ? "battery-caution" : "battery-low", `Battery at ${percent}%`, critical ? "Plug in now: it will hibernate on its own at 2%." : "Plug in soon.", critical);
                break;
            }
        }
    }

    // Changed by hand while switched: keep that choice when plugged in.
    onProfileChanged: {
        error = "";
        failed = -1;
        if (switchedTo >= 0 && profile !== switchedTo) {
            restoreTo = -1;
            switchedTo = -1;
        }
    }

    Process {
        id: switcher

        property int target: -1

        stderr: StdioCollector {
            id: switchError
        }
        onExited: code => {
            if (code === 0) {
                root.error = "";
                root.failed = -1;
                return;
            }
            // "Failed to set property ActiveProfile on interface …: <reason>"
            const reason = switchError.text.trim().replace(/^Failed to set property [^:]*: /, "");
            root.failed = target;
            root.error = reason || "The power profile service refused the change";
            console.warn(`kirin: switching the power profile failed: ${reason}`);
            root.check();
        }
    }

    // The battery's wear, from the kernel (UPower's combined device doesn't
    // have it): how much it holds when full against how much it held new,
    // and charge cycles (0: not reported). Read when asked (Settings →
    // Power), it changes slowly.
    property var health: null

    function readHealth(): void {
        healthReader.running = true;
    }

    Process {
        id: healthReader

        // Energy (µWh) or, on some batteries, charge (µAh); the first battery.
        command: ["sh", `${Quickshell.shellDir}/scripts/battery-health.sh`]
        stdout: StdioCollector {
            onStreamFinished: {
                const [full, design, cycles, unit] = text.trim().split(" ");
                const f = Number(full) / 1e6, d = Number(design) / 1e6;
                root.health = d > 0 ? {
                    full: f,
                    design: d,
                    percent: Math.round(f / d * 100),
                    cycles: Number(cycles) || 0,
                    unit: unit
                } : null;
            }
        }
    }

    // Charge limit ("Preserve battery health"), through UPower (1.90.5+):
    // it writes the laptop's own threshold (charge_control_*_threshold) and
    // keeps it across reboots; an active session may switch it without a
    // password. Only for a battery that has one (many laptops don't):
    // `limit` stays null otherwise and Settings shows nothing.
    //   { path, native, enabled, start, end }
    property var limit: null
    // The last switch didn't take (shown in Settings).
    property string limitError: ""
    // On in UPower, yet the battery's own threshold says otherwise: it
    // didn't take (checked on every read, not only right after a switch).
    readonly property bool limitMismatch: !!limit && limit.enabled && limit.kernelEnd >= 0 && limit.kernelEnd !== limit.end

    function readLimit(): void {
        limitReader.running = true;
    }

    // Turns the limit on or off, then reads back whether it took.
    function setLimit(on: bool): void {
        if (!limit)
            return;
        limitError = "";
        limitSetter.want = on;
        limitSetter.command = ["busctl", "--system", "call", "org.freedesktop.UPower", limit.path, "org.freedesktop.UPower.Device", "EnableChargeThreshold", "b", on ? "true" : "false"];
        limitSetter.running = true;
    }

    // Lifted until unplugged (then on again), for a full battery once.
    function chargeFullOnce(on: bool): void {
        Config.power.fullChargeOnce = on;
        setLimit(!on);
    }

    Process {
        id: limitReader

        // The first device UPower says has a limit: its path, kernel name,
        // whether on, and the thresholds; the kernel's own end threshold to
        // check against.
        command: ["sh", `${Quickshell.shellDir}/scripts/charge-limit.sh`]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(" ");
                root.limit = f.length >= 5 ? {
                    path: f[0],
                    native: f[1],
                    enabled: f[2] === "true",
                    start: Number(f[3]),
                    end: Number(f[4]),
                    kernelEnd: f[5] === "-" ? -1 : Number(f[5])
                } : null;
                limitSetter.check();
                // Didn't take: the thresholds put right as root (NixOS:
                // kirin-charge-limit.service, nix/battery.nix), once per
                // mismatch; elsewhere there's no such service and it stays.
                if (!root.limitMismatch)
                    limitFixer.tried = false;
                else if (!limitFixer.tried) {
                    limitFixer.tried = true;
                    limitFixer.running = true;
                }
            }
        }
    }

    Process {
        id: limitFixer

        property bool tried: false

        command: ["systemctl", "start", "kirin-charge-limit.service"]
        onExited: code => {
            if (code === 0)
                root.limitError = "";
            root.readLimit();
        }
    }

    Process {
        id: limitSetter

        property bool want: false
        property bool pending: false

        // After a switch: the state read again, checked against what was
        // wanted (and, with the limit on, the kernel's threshold).
        function check(): void {
            if (!pending)
                return;
            pending = false;
            const l = root.limit;
            if (!l)
                root.limitError = "The battery no longer reports a charge limit.";
            else if (l.enabled !== want)
                root.limitError = "UPower didn't apply it.";
            else if (want && l.kernelEnd >= 0 && l.kernelEnd !== l.end)
                root.limitError = `The battery took ${l.kernelEnd}% instead of ${l.end}%.`;
        }

        stderr: StdioCollector {
            id: limitSetError
        }
        onExited: code => {
            if (code !== 0) {
                root.limitError = limitSetError.text.trim() || "UPower refused.";
                root.readLimit();
                return;
            }
            pending = true;
            root.readLimit();
        }
    }

    Component.onCompleted: readLimit()

    // Any service with the ppd D-Bus API (power-profiles-daemon, tuned-ppd).
    Process {
        id: checker

        running: true
        command: ["busctl", "--system", "status", root.busName]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => root.available = code === 0
    }

    Timer {
        running: true
        repeat: true
        interval: 15000
        onTriggered: root.check()
    }
}
