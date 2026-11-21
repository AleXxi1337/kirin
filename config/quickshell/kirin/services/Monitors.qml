pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "layout.js" as Layout

// Monitors as Hyprland reports them (`hyprctl monitors -j`). Quickshell's own
// HyprlandMonitor objects can stay empty (all zeros) until some later refresh,
// so the settings read this instead.
Singleton {
    id: root

    // Raw objects from hyprctl: name, description, x, y, width, height, scale,
    // transform, refreshRate, availableModes, ...
    property var list: []
    property bool loaded: false

    function refresh(): void {
        if (proc.running)
            proc.again = true;
        else
            proc.running = true;
    }

    // --- Layout profiles ----------------------------------------------------
    // A saved arrangement belongs to a combination of monitors, as in Windows
    // and macOS. Monitors are told apart by their description (make, model,
    // serial), so they can move between ports; only identical monitors in the
    // same combination fall back to the port: "<description>@<port>".

    function ids(monitors: var): var {
        const counts = {};
        for (const m of monitors)
            counts[m.description] = (counts[m.description] ?? 0) + 1;
        return monitors.map(m => !m.description || counts[m.description] > 1 ? `${m.description || "Unknown"}@${m.name}` : m.description);
    }

    readonly property var active: list.filter(m => !m.disabled)
    readonly property var activeIds: ids(active)
    // The combination that's connected now, e.g. "Dell U2720Q + Lenovo 0x40A9".
    readonly property string profileKey: activeIds.slice().sort().join(" + ")

    function idOf(m: var): string {
        return activeIds[active.indexOf(m)] ?? m.description;
    }

    // Hyprland monitor rule target for a monitor.
    function outputOf(m: var): string {
        return idOf(m).includes("@") ? m.name : `desc:${m.description}`;
    }

    // --- Physical size ------------------------------------------------------
    // From EDID (via Hyprland) unless corrected by hand in the settings.

    function physicalSize(m: var): var {
        const manual = Config.display.physical[m.description];
        if (manual?.width > 0 && manual?.height > 0)
            return {
                width: manual.width,
                height: manual.height,
                manual: true
            };
        return {
            width: m.physicalWidth ?? 0,
            height: m.physicalHeight ?? 0,
            manual: false
        };
    }

    // Diagonal in inches and pixel density, or null when the size is unknown.
    function density(m: var): var {
        const size = physicalSize(m);
        if (!(size.width > 0 && size.height > 0))
            return null;
        const inches = Math.hypot(size.width, size.height) / 25.4;
        return {
            inches,
            ppi: Math.hypot(m.width, m.height) / inches
        };
    }

    // Physical size in mm as drawn by the arrangement editor: rotated like the
    // monitor, and assuming 96 dpi when unknown.
    function physicalExtent(m: var): var {
        // Real sizes ignored (Config.display.physicalSizes off): the
        // monitor's size in logical pixels at the common scale, as if at 96
        // dpi, so the arrangement goes by pixels.
        if (!Config.display.physicalSizes) {
            const px = logicalSize(m, validScale(m, Config.display.scale || 1));
            return {
                w: px.w * 25.4 / 96,
                h: px.h * 25.4 / 96
            };
        }
        const physical = physicalSize(m);
        const rotated = (m.transform ?? 0) % 2 === 1;
        let w = rotated ? physical.height : physical.width;
        let h = rotated ? physical.width : physical.height;
        if (!(w > 0 && h > 0)) {
            const px = logicalSize(m, 1);
            w = px.w * 25.4 / 96;
            h = px.h * 25.4 / 96;
        }
        return {
            w,
            h
        };
    }

    // --- Primary monitor and per-monitor scale -----------------------------
    // Display scale (Settings → Display) is the primary monitor's scale. With
    // real sizes taken into account (Config.display.physicalSizes), the
    // others get the scale that makes things the same physical size as on
    // the primary: primary scale × their PPI / primary PPI; without, the same
    // scale as the primary.

    readonly property var profile: Config.display.profiles[profileKey] ?? null

    // The built-in screen by default, else the first one. A mirroring
    // monitor can't be primary.
    readonly property string primaryId: {
        const saved = profile?.primary;
        const ids = extended.map(m => idOf(m));
        if (saved && ids.includes(saved))
            return saved;
        const internal = extended.findIndex(m => /^(eDP|LVDS|DSI)/.test(m.name));
        return ids[internal >= 0 ? internal : 0] ?? "";
    }
    readonly property var primary: active[activeIds.indexOf(primaryId)] ?? null

    function setPrimary(id: string): void {
        const profiles = Object.assign({}, Config.display.profiles);
        profiles[profileKey] = Object.assign({}, profiles[profileKey] ?? {}, {
            primary: id
        });
        Config.display.profiles = profiles;
    }

    // Nearest scale Hyprland accepts for the monitor: a multiple of 1/120 that
    // gives a whole-pixel logical size. 0.25–4 is only a sanity range; within
    // it the scale is whatever keeps sizes physically right.
    function validScale(m: var, target: real): real {
        target = Math.max(0.25, Math.min(4, target));
        let best = 120;
        for (let k = 30; k <= 480; k++) {
            if ((m.width * 120) % k !== 0 || (m.height * 120) % k !== 0)
                continue;
            if (Math.abs(k / 120 - target) < Math.abs(best / 120 - target))
                best = k;
        }
        return best / 120;
    }

    // The scale kirin gives a monitor, for its chosen mode.
    function scaleFor(m: var): real {
        const base = Config.display.scale || 1;
        const t = target(m);
        if (!primary || m === primary || !Config.display.physicalSizes)
            return validScale(t, base);
        const d = density(t);
        const dp = density(target(primary));
        if (!d || !dp)
            return validScale(t, base);
        return validScale(t, base * d.ppi / dp.ppi);
    }

    // --- Mode, rotation, VRR, mirroring --------------------------------------
    // Chosen per monitor in the profile of the combination:
    // profile.outputs = { "<id>": { mode: "1920x1080@60.00", transform: 0-3,
    //                               vrr: 0-2, mirror: "<id of source>" } }.

    // "1920x1080@60.01Hz" → { width, height, refresh, mode: "1920x1080@60.01" }
    function parseMode(text: var): var {
        const match = /^(\d+)x(\d+)@([\d.]+)/.exec(text ?? "");
        return match ? {
            width: +match[1],
            height: +match[2],
            refresh: +match[3],
            mode: `${match[1]}x${match[2]}@${match[3]}`
        } : null;
    }

    // The monitor's modes without duplicates, biggest and fastest first.
    function modes(m: var): var {
        const seen = {};
        return (m.availableModes ?? []).map(parseMode).filter(x => x && !seen[x.mode] && (seen[x.mode] = true)).sort((a, b) => b.width * b.height - a.width * a.height || b.refresh - a.refresh);
    }

    // The monitor as kirin sets it up: chosen mode and rotation applied to
    // Hyprland's description of it. Without a choice: the current mode
    // (Hyprland's "preferred") and no rotation.
    function target(m: var): var {
        const chosen = profile?.outputs?.[idOf(m)] ?? {};
        const mode = parseMode(chosen.mode);
        return Object.assign({}, m, {
            width: mode?.width ?? m.width,
            height: mode?.height ?? m.height,
            refreshRate: mode?.refresh ?? m.refreshRate,
            mode: mode?.mode ?? "preferred",
            transform: chosen.transform ?? 0,
            vrr: chosen.vrr ?? 0,
            mirror: chosen.mirror ?? ""
        });
    }

    // Adaptive sync: 0 off, 1 on, 2 only for fullscreen apps (games, video).
    function vrrCapable(m: var): bool {
        return m?.hardwareDetails?.vrrCapable === true;
    }

    // The connected monitor that m shows a copy of, or null. A mirror can't
    // be mirrored, and a monitor can't mirror itself.
    function mirrorSource(m: var): var {
        const id = target(m).mirror;
        if (!id)
            return null;
        const source = active[activeIds.indexOf(id)];
        return source && source !== m && !target(source).mirror ? source : null;
    }

    // Monitors that extend the desktop (not mirroring another one); only
    // these are arranged.
    readonly property var extended: active.filter(m => !mirrorSource(m))

    // The saved millimetre layout for these monitors (ids, extents in mm), or
    // null when the combination has none. A monitor whose size changed since
    // (rotated, size corrected) keeps its centre; one without a saved place
    // (it was mirroring) goes to the right of the others.
    // Arrangements are kept apart for real sizes ("physical", mm) and pixels
    // ("pixels"): Config.display.physicalSizes picks one. Without its own yet,
    // the other one is carried over: which side each monitor is on and how
    // it's aligned there (layout.js relayout), at the sizes of this one.
    readonly property string layoutKey: Config.display.physicalSizes ? "physical" : "pixels"

    function placePhysical(ids: var, extents: var): var {
        const saved = profile?.[layoutKey];
        if (!saved || !ids.some(id => saved[id])) {
            const other = profile?.[Config.display.physicalSizes ? "pixels" : "physical"];
            if (!other || !ids.every(id => other[id]))
                return null;
            const pos = Layout.relayout(ids.map((id, i) => ({
                            x: other[id].x,
                            y: other[id].y,
                            w: other[id].w,
                            h: other[id].h,
                            W: extents[i].w,
                            H: extents[i].h
                        })), 2);
            return pos.map((p, i) => ({
                        x: p.x,
                        y: p.y,
                        w: extents[i].w,
                        h: extents[i].h
                    }));
        }
        const out = ids.map((id, i) => saved[id] ? {
                x: saved[id].x + (saved[id].w - extents[i].w) / 2,
                y: saved[id].y + (saved[id].h - extents[i].h) / 2,
                w: extents[i].w,
                h: extents[i].h
            } : null);
        let right = Math.max(...out.filter(p => p).map(p => p.x + p.w));
        const top = Math.min(...out.filter(p => p).map(p => p.y));
        out.forEach((p, i) => {
            if (p)
                return;
            out[i] = {
                x: right,
                y: top,
                w: extents[i].w,
                h: extents[i].h
            };
            right += extents[i].w;
        });
        return out;
    }

    // Changes a monitor's mode/rotation for the connected combination, as a
    // trial: unless keep() is called within 15 s it's reverted, in case the
    // monitor can't show it.
    function setOutput(id: string, change: var): void {
        if (!trialBackup)
            trialBackup = JSON.parse(JSON.stringify(Config.display.profiles));
        const profiles = Object.assign({}, Config.display.profiles);
        const profile = Object.assign({}, profiles[profileKey] ?? {});
        const outputs = Object.assign({}, profile.outputs ?? {});
        outputs[id] = Object.assign({}, outputs[id] ?? {}, change);
        profile.outputs = outputs;
        profiles[profileKey] = profile;
        Config.display.profiles = profiles;
        trialSeconds = 15;
        trialTimer.restart();
        trialStarted();
    }

    // Emitted on every trial change, so the settings can show the confirmation.
    signal trialStarted

    property var trialBackup: null
    property int trialSeconds: 0
    readonly property bool trialActive: trialBackup !== null

    function keep(): void {
        trialTimer.stop();
        trialBackup = null;
        trialSeconds = 0;
    }

    function revert(): void {
        if (trialBackup)
            Config.display.profiles = trialBackup;
        keep();
    }

    Timer {
        id: trialTimer

        interval: 1000
        repeat: true
        onTriggered: {
            root.trialSeconds--;
            if (root.trialSeconds <= 0)
                root.revert();
        }
    }

    // Size in logical pixels, as used for positions; at the monitor's current
    // scale unless one is given.
    function logicalSize(m: var, scaleOverride: var): var {
        const scale = scaleOverride || m.scale || 1;
        const rotated = (m.transform ?? 0) % 2 === 1;
        const w = Math.round(m.width / scale);
        const h = Math.round(m.height / scale);
        return rotated ? {
            w: h,
            h: w
        } : {
            w,
            h
        };
    }

    Component.onCompleted: refresh()

    Process {
        id: proc

        property bool again: false

        command: ["hyprctl", "monitors", "all", "-j"]
        onRunningChanged: {
            if (!running && again) {
                again = false;
                running = true;
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.list = JSON.parse(text);
                    root.loaded = true;
                } catch (e) {
                    console.warn("kirin: can't read hyprctl monitors");
                }
            }
        }
    }

    // Monitor added/removed/changed: read again. Short delay so Hyprland has
    // finished reconfiguring.
    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name.startsWith("monitor") || event.name === "configreloaded")
                debounce.restart();
        }
    }

    Timer {
        id: debounce

        interval: 300
        onTriggered: root.refresh()
    }
}
