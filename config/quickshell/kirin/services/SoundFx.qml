pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

// All of kirin's sounds (Settings → Sounds): the sound theme (installed in
// share/sounds/<theme>/stereo), one volume, and per event whether it plays
// and which sound. By default an event plays the first of its `defaults`
// the theme has (freedesktop filling the gaps); a sound picked in the
// settings (Config.sounds.choice) replaces that. Played through PipeWire.
Singleton {
    id: root

    // Installed themes: [{ id, label, files: { sound name: path } }], the
    // user's own (~/.local/share) first; the first of a name wins.
    property var themes: []
    readonly property var theme: themes.find(t => t.id === Config.sounds.theme) ?? themes.find(t => t.id === "freedesktop") ?? null
    readonly property var fallback: themes.find(t => t.id === "freedesktop") ?? null

    // Events, in the order the settings list them. `defaults`: sound names
    // in order of preference (themes name things differently); `on`: plays
    // unless turned off.
    readonly property var events: [
        {
            id: "notification",
            label: "Notification",
            icon: "notifications",
            defaults: ["message-new-instant", "message", "message-new-email", "bell"],
            on: true
        },
        {
            id: "critical",
            label: "Critical notification",
            icon: "priority_high",
            defaults: ["dialog-warning", "dialog-error", "message-attention", "bell"],
            on: true
        },
        {
            id: "plug",
            label: "Charger plugged in",
            icon: "power",
            defaults: ["power-plug", "device-added"],
            on: true
        },
        {
            id: "unplug",
            label: "Charger unplugged",
            icon: "power_off",
            defaults: ["power-unplug", "device-removed"],
            on: true
        },
        {
            id: "battery",
            label: "Battery low",
            icon: "battery_alert",
            defaults: ["battery-low", "battery-caution", "dialog-warning"],
            on: true
        },
        {
            id: "bt-connect",
            label: "Bluetooth device connected",
            icon: "bluetooth_connected",
            defaults: ["device-added", "service-login"],
            on: true
        },
        {
            id: "bt-disconnect",
            label: "Bluetooth device disconnected",
            icon: "bluetooth_disabled",
            defaults: ["device-removed", "service-logout"],
            on: true
        },
        {
            id: "screenshot",
            label: "Screenshot",
            icon: "screenshot_region",
            defaults: ["screen-capture", "camera-shutter"],
            on: true
        },
        {
            id: "unlock",
            label: "Unlocked",
            icon: "lock_open",
            defaults: ["desktop-login", "service-login", "system-ready"],
            on: true
        },
        {
            id: "volume",
            label: "Volume keys",
            icon: "volume_up",
            defaults: ["audio-volume-change"],
            on: false
        },
        {
            id: "net-up",
            label: "Network connected",
            icon: "wifi",
            defaults: ["network-connectivity-established", "service-login"],
            on: false
        },
        {
            id: "net-down",
            label: "Network lost",
            icon: "wifi_off",
            defaults: ["network-connectivity-lost", "service-logout"],
            on: false
        }
    ]

    function info(id: string): var {
        return events.find(e => e.id === id) ?? null;
    }

    function enabled(id: string): bool {
        return Config.sounds.events?.[id] ?? info(id)?.on ?? false;
    }

    function setEnabled(id: string, on: bool): void {
        const e = Object.assign({}, Config.sounds.events ?? {});
        e[id] = on;
        Config.sounds.events = e;
    }

    // The sound picked for an event, "" for its default.
    function choice(id: string): string {
        return Config.sounds.choice?.[id] ?? "";
    }

    function setChoice(id: string, sound: string): void {
        const c = Object.assign({}, Config.sounds.choice ?? {});
        if (sound)
            c[id] = sound;
        else
            delete c[id];
        Config.sounds.choice = c;
    }

    // Name of the default sound of an event in the current theme.
    function defaultName(id: string): string {
        return (info(id)?.defaults ?? []).find(n => resolve(n) !== "") ?? "";
    }

    // File an event plays: the picked sound, else the default.
    function fileFor(id: string): string {
        return resolve(choice(id)) || resolve(defaultName(id));
    }

    // Everything back to the defaults; the theme stays.
    function reset(): void {
        Config.sounds.events = ({});
        Config.sounds.choice = ({});
        Config.sounds.volume = 0.6;
    }

    // Sound names to pick from: the theme's, then freedesktop's it lacks.
    readonly property var names: {
        const own = Object.keys(theme?.files ?? {}).sort();
        const extra = Object.keys(fallback?.files ?? {}).filter(n => !own.includes(n)).sort();
        return own.concat(extra);
    }

    function label(name: string): string {
        return name.charAt(0).toUpperCase() + name.slice(1).replace(/-/g, " ");
    }

    // Path of a sound: a file as is, a name from the theme, else from
    // freedesktop, else "".
    function resolve(sound: string): string {
        const name = (sound ?? "").replace(/^file:\/\//, "");
        if (!name)
            return "";
        if (name.startsWith("/"))
            return name;
        return theme?.files[name] ?? fallback?.files[name] ?? "";
    }

    // application.name of kirin's own sound streams.
    readonly property string streamName: "kirin-sounds"

    function playFile(file: string): void {
        if (!file)
            return;
        if (Config.sounds.muted)
            return;
        const v = Math.max(0, Math.min(1, Config.sounds.volume)).toFixed(2);
        // Marked as kirin's, so the volume card's mixer doesn't list it as
        // an app (it'd come and go with each sound).
        Quickshell.execDetached(["pw-play", "--volume", v, "--properties", `{ "node.name": "${root.streamName}", "application.name": "${root.streamName}", "media.role": "Notification" }`, file]);
    }

    // Held keys, flapping devices, bursts of notifications: at most one
    // sound per event in `gap` ms.
    property var lastPlayed: ({})

    function throttled(id: string, gap: int): bool {
        const now = Date.now();
        if (now - (lastPlayed[id] ?? 0) < gap)
            return true;
        lastPlayed[id] = now;
        return false;
    }

    // An event happened: its sound, if it's on.
    function trigger(id: string): void {
        if (!ready || !enabled(id) || throttled(id, 120))
            return;
        playFile(fileFor(id));
    }

    // A notification's sound (Notifs): an app may name its own.
    function notify(critical: bool, own: string): void {
        const id = critical ? "critical" : "notification";
        if (!enabled(id) || throttled("notification", 800))
            return;
        playFile(resolve(own) || fileFor(id));
    }

    // The settings' ▶: an event's sound, whether it's on or not.
    function preview(id: string): void {
        playFile(fileFor(id));
    }

    // State settling after kirin starts (devices, battery, network report
    // in) isn't an event.
    property bool ready: false

    Timer {
        running: true
        interval: 5000
        onTriggered: root.ready = true
    }

    // --- Themes --------------------------------------------------------------

    function scan(): void {
        scanner.running = false;
        scanner.running = true;
    }

    Component.onCompleted: scan()

    Process {
        id: scanner

        // "T<tab>id<tab>name" per theme, "F<tab>id<tab>sound<tab>path" per file.
        command: ["sh", "-c", `IFS=:
            for d in "\${XDG_DATA_HOME:-$HOME/.local/share}" \${XDG_DATA_DIRS:-/usr/local/share:/usr/share:/run/current-system/sw/share}; do
                for t in "$d"/sounds/*/; do
                    [ -d "$t" ] || continue
                    id=$(basename "$t")
                    name=$(sed -n 's/^Name=//p' "$t/index.theme" 2>/dev/null | head -n1)
                    printf 'T\\t%s\\t%s\\n' "$id" "\${name:-$id}"
                    for f in "$t"stereo/*; do
                        case "$f" in *.oga|*.ogg|*.wav|*.flac) ;; *) continue ;; esac
                        n=$(basename "$f"); printf 'F\\t%s\\t%s\\t%s\\n' "$id" "\${n%.*}" "$f"
                    done
                done
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const byId = {};
                const order = [];
                for (const line of text.split("\n")) {
                    const [kind, id, a, b] = line.split("\t");
                    if (kind === "T" && !byId[id]) {
                        byId[id] = {
                            id,
                            label: id === "freedesktop" ? "Freedesktop" : a,
                            files: {}
                        };
                        order.push(id);
                    } else if (kind === "F" && byId[id] && !byId[id].files[a]) {
                        byId[id].files[a] = b;
                    }
                }
                // Only themes with sounds (some dirs are just metadata).
                root.themes = order.map(id => byId[id]).filter(t => Object.keys(t.files).length > 0);
            }
        }
    }

    // --- Event sources that live here ----------------------------------------
    // Others call trigger(): Power (charger, battery), Osd (volume keys),
    // Notifs (screenshots: grimblast's notification), Lock (unlocked).

    // Bluetooth devices connecting and disconnecting.
    Variants {
        model: Bluetooth.devices.values

        Connections {
            required property BluetoothDevice modelData

            target: modelData

            function onConnectedChanged(): void {
                root.trigger(modelData.connected ? "bt-connect" : "bt-disconnect");
            }
        }
    }

    // Network: full connectivity reached or lost.
    property string connectivity: Network.connectivity
    property string lastConnectivity: ""

    onConnectivityChanged: {
        const was = lastConnectivity;
        lastConnectivity = connectivity;
        if (connectivity === "full" && was && was !== "full")
            trigger("net-up");
        else if (was === "full" && connectivity !== "full" && connectivity !== "unknown")
            trigger("net-down");
    }
}
