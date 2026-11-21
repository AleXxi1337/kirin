pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Screen brightness of the laptop's backlight, shared by the bar and the OSD.
// Goes through brightnessctl with the same curve as the brightness keys
// (hypr/modules/keybindings.lua: -e4), so the percentages match:
// shown = (raw / max) ^ (1/4).
Singleton {
    id: root

    // /sys/class/backlight/<device>
    property string device: ""
    property real raw: 0
    property real max: 0
    readonly property real exponent: 4
    // 0–1 as shown; while dragging, the value being set.
    property real pending: -1
    readonly property real level: pending >= 0 ? pending : max > 0 ? Math.pow(raw / max, 1 / exponent) : 0
    readonly property bool available: device !== "" && max > 0
    // Read often (something showing it is open), not just every 2 s.
    property int watchers: 0

    function setLevel(value: real): void {
        if (!available)
            return;
        value = Math.max(0.01, Math.min(1, value));
        pending = value;
        if (setter.running)
            setter.again = true;
        else
            setter.start();
    }

    // Glides to a level instead of jumping (the brightness keys): many small
    // writes, coalesced by the setter. Steps from the last target, so holding
    // a key keeps adding up.
    property real fadeTarget: -1

    function fadeTo(value: real): void {
        if (!available)
            return;
        value = Math.max(0.01, Math.min(1, value));
        fade.stop();
        fade.from = level;
        fade.to = value;
        fadeTarget = value;
        fade.start();
    }

    function step(delta: real): void {
        fadeTo((fade.running ? fadeTarget : level) + delta);
    }

    property real fadeLevel: 0
    onFadeLevelChanged: {
        if (fade.running)
            setLevel(fadeLevel);
    }

    NumberAnimation {
        id: fade

        target: root
        property: "fadeLevel"
        duration: 220
        easing.type: Easing.OutCubic
        onFinished: root.setLevel(root.fadeTarget)
    }

    // Read the current value now (after the keys changed it).
    function reload(): void {
        rawFile.reload();
    }

    Process {
        running: true
        command: ["sh", "-c", "ls /sys/class/backlight | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: root.device = text.trim()
        }
    }

    FileView {
        path: root.device ? `/sys/class/backlight/${root.device}/max_brightness` : ""
        onLoaded: root.max = parseFloat(text()) || 0
    }

    FileView {
        id: rawFile

        path: root.device ? `/sys/class/backlight/${root.device}/brightness` : ""
        onLoaded: root.raw = parseFloat(text()) || 0
    }

    // sysfs files can't be watched; the keys change it too.
    Timer {
        running: root.available
        repeat: true
        interval: root.watchers > 0 ? 250 : 2000
        onTriggered: rawFile.reload()
    }

    // Writes the latest value; one brightnessctl at a time.
    Process {
        id: setter

        property bool again: false

        function start(): void {
            command = ["brightnessctl", "-d", root.device, "-e4", "-n2", "-q", "set", `${Math.round(root.pending * 100)}%`];
            running = true;
        }

        onExited: {
            if (again) {
                again = false;
                start();
            } else {
                rawFile.reload();
                settle.restart();
            }
        }
    }

    // Show the real value again once writing is done.
    Timer {
        id: settle

        interval: 300
        onTriggered: {
            if (!setter.running)
                root.pending = -1;
        }
    }
}
