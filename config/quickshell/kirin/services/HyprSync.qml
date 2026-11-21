pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "layout.js" as Layout

// Pushes the settings that affect Hyprland (monitor scales, positions, modes,
// mirroring, VRR, animation speed, keyboard/mouse/touchpad)
// from the config into Hyprland: live through hyprctl, and saved to
// ~/.local/state/kirin/hyprland.lua, which the Hyprland config
// (modules/settings.lua) reads on start.
Singleton {
    id: root

    readonly property string luaPath: `${Wallpaper.stateDir}/hyprland.lua`

    readonly property real scale: Config.display.scale
    readonly property real animationSpeed: Config.appearance.animationSpeed
    // Scale and position for each connected monitor. Scales follow the
    // primary monitor (Monitors.scaleFor). Positions come from the profile's
    // millimetre layout, converted to logical pixels at those scales, so the
    // arrangement stays right when scales change; without a profile Hyprland
    // places the monitors itself.
    readonly property var monitors: {
        const profile = Monitors.profile;
        // Only monitors that extend the desktop are laid out; mirrors just
        // copy their source.
        const list = Monitors.extended;
        const ids = list.map(m => Monitors.idOf(m));
        // As kirin sets them up: chosen mode and rotation.
        const targets = list.map(m => Monitors.target(m));
        const scales = list.map(m => Monitors.scaleFor(m));
        const sizes = targets.map((t, i) => Monitors.logicalSize(t, scales[i]));
        // Physical sizes for the chosen rotation; the saved layout gives positions.
        const extents = targets.map(t => Monitors.physicalExtent(t));

        // The profile's millimetre layout; older profiles only have pixel
        // positions (saved at 100% scale), which are converted to millimetres.
        let placed = Monitors.placePhysical(ids, extents);
        if (!placed && profile?.monitors && ids.every(id => profile.monitors[id])) {
            const mm = list.map(m => Monitors.physicalExtent(m));
            const px = list.map(m => Monitors.logicalSize(m, 1));
            placed = Layout.relayout(ids.map((id, i) => ({
                            x: profile.monitors[id].x,
                            y: profile.monitors[id].y,
                            w: px[i].w,
                            h: px[i].h,
                            W: mm[i].w,
                            H: mm[i].h
                        })), 2).map((p, i) => ({
                        x: p.x + (mm[i].w - extents[i].w) / 2,
                        y: p.y + (mm[i].h - extents[i].h) / 2,
                        w: extents[i].w,
                        h: extents[i].h
                    }));
        }

        const pos = placed ? Layout.relayout(placed.map((p, i) => Object.assign({}, p, {
                            W: sizes[i].w,
                            H: sizes[i].h
                        })), 1) : null;

        const out = {};
        list.forEach((m, i) => out[Monitors.outputOf(m)] = Object.assign({
                scale: scales[i],
                mode: targets[i].mode,
                transform: targets[i].transform,
                vrr: targets[i].vrr
            }, pos ? pos[i] : {}));
        for (const m of Monitors.active) {
            const source = Monitors.mirrorSource(m);
            if (!source)
                continue;
            const t = Monitors.target(m);
            out[Monitors.outputOf(m)] = {
                scale: Monitors.scaleFor(m),
                mode: t.mode,
                transform: t.transform,
                vrr: t.vrr,
                mirror: source.name
            };
        }
        return out;
    }

    // Keyboard, mouse and touchpad (Settings → Input), as Hyprland's input
    // section (Lua), applied over hypr/modules/input.lua.
    readonly property string inputLua: {
        const i = Config.input;
        const str = v => JSON.stringify(String(v));
        const lines = [
            `kb_layout = ${str((i.layouts ?? ["us"]).join(","))}`,
            `kb_options = ${str(i.switchKeys ?? "")}`,
            `repeat_rate = ${Math.round(i.repeatRate)}`,
            `repeat_delay = ${Math.round(i.repeatDelay)}`,
            `numlock_by_default = ${!!i.numlock}`,
            `sensitivity = ${Math.max(-1, Math.min(1, i.mouseSensitivity)).toFixed(2)}`,
            `accel_profile = ${str(i.mouseAcceleration ? "adaptive" : "flat")}`,
            `natural_scroll = ${!!i.mouseNaturalScroll}`,
            `left_handed = ${!!i.leftHanded}`,
            `follow_mouse = ${i.focusFollowsMouse ? 1 : 0}`,
            `touchpad = { natural_scroll = ${!!i.touchpadNaturalScroll}, scroll_factor = ${Math.max(0.05, i.touchpadScrollSpeed).toFixed(2)}, tap_to_click = ${!!i.tapToClick}, disable_while_typing = ${!!i.disableWhileTyping}, clickfinger_behavior = ${!!i.twoFingerRightClick} }`
        ];
        return `{ ${lines.join(", ")} }`;
    }

    onInputLuaChanged: apply()

    // Shortcuts changed from their defaults, for keybindings.lua.
    readonly property string shortcutsLua: {
        const changed = Config.input.shortcuts ?? {};
        const lines = Object.keys(changed).sort().map(id => `[${JSON.stringify(id)}] = ${JSON.stringify(String(changed[id]))}`);
        return `{ ${lines.join(", ")} }`;
    }

    onShortcutsLuaChanged: apply()

    // Port name of the primary monitor (Settings → Display).
    readonly property string primary: Monitors.primary?.name ?? ""

    onPrimaryChanged: apply()
    onScaleChanged: apply()
    onAnimationSpeedChanged: apply()
    onMonitorsChanged: apply()

    function apply(): void {
        // Wait for the monitor list too, or the file would lose the positions.
        if (!Config.loaded || !Monitors.loaded || !(scale > 0))
            return;
        // JSON string literals are valid Lua strings for the names used here.
        const monitorLines = Object.entries(monitors ?? {}).map(([output, m]) => {
            const position = m.x === undefined ? "" : ` x = ${Math.round(m.x)}, y = ${Math.round(m.y)},`;
            const mirror = m.mirror ? ` mirror = ${JSON.stringify(m.mirror)},` : "";
            return `    [${JSON.stringify(output)}] = {${position}${mirror} scale = ${m.scale}, mode = ${JSON.stringify(m.mode)}, transform = ${m.transform}, vrr = ${m.vrr} },`;
        });
        file.setText(["-- Generated by kirin from config.json. Do not edit.", "return {", `  scale = ${scale},`, `  animation_speed = ${Math.max(0, animationSpeed)},`, `  primary = ${JSON.stringify(primary)},`, `  input = ${inputLua},`, `  shortcuts = ${shortcutsLua},`, "  monitors = {", ...monitorLines, "  },", "}", ""].join("\n"));
    }

    FileView {
        id: file

        path: root.luaPath
        printErrors: false
        // Unchanged content is not rewritten, so only real changes reach Hyprland.
        onSaved: {
            Quickshell.execDetached(["hyprctl", "eval", `kirin_apply_settings(dofile("${root.luaPath}"))`]);
            // Hyprland doesn't announce mode/rotation/position changes.
            refreshTimer.restart();
        }
    }

    Timer {
        id: refreshTimer

        interval: 500
        onTriggered: Monitors.refresh()
    }

    Connections {
        target: Config

        function onLoadedChanged(): void {
            root.apply();
        }
    }

    Connections {
        target: Monitors

        function onLoadedChanged(): void {
            root.apply();
        }
    }
}
