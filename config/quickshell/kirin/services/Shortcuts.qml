pragma Singleton

import QtQuick
import Quickshell

// Hyprland's changeable shortcuts (Settings → Shortcuts): the list, their
// defaults, the ones changed (Config.input.shortcuts, { id: "MODS + key" },
// "" for off) and helpers to show and record them. The binds themselves are
// Hyprland's: hypr/modules/keybindings.lua has the same ids and defaults
// (keep them in step), services/HyprSync.qml passes the changes on.
// Combinations are Hyprland's: modifiers SUPER, CTRL, ALT, SHIFT in that
// order, then the key's name ("Q", "SPACE", "left", "minus", "Print"...).
// Groups (`mods: true`) take only modifiers: their keys are fixed.
Singleton {
    id: root

    readonly property var sections: [
        {
            title: "Apps and windows",
            items: [
                {
                    id: "launcher",
                    title: "Open the launcher",
                    icon: "search",
                    keys: "SUPER + SPACE"
                },
                {
                    id: "settings",
                    title: "Open settings",
                    icon: "settings",
                    keys: "SUPER + I"
                },
                {
                    id: "terminal",
                    title: "Open a terminal",
                    icon: "terminal",
                    keys: "SUPER + Q"
                },
                {
                    id: "files",
                    title: "Open the file manager",
                    icon: "folder",
                    keys: "SUPER + E"
                },
                {
                    id: "close",
                    title: "Close the window",
                    icon: "close",
                    keys: "SUPER + C"
                },
                {
                    id: "fullscreen",
                    title: "Fullscreen",
                    icon: "fullscreen",
                    keys: "SUPER + SHIFT + F"
                },
                {
                    id: "arrows",
                    title: "Arrows: focus (tiling), snap and maximize (windows mode)",
                    icon: "open_with",
                    keys: "SUPER",
                    mods: true,
                    suffix: "← → ↑ ↓"
                },
                {
                    id: "window_mode",
                    title: "Switch between tiling and windows mode",
                    icon: "dashboard",
                    keys: "SUPER + CTRL + SHIFT + T"
                }
            ]
        },
        {
            title: "Tiling",
            items: [
                {
                    id: "workspace_go",
                    title: "Go to workspace 1–10",
                    icon: "counter_1",
                    keys: "SUPER",
                    mods: true,
                    suffix: "1 … 0"
                },
                {
                    id: "workspace_move",
                    title: "Move the window to workspace 1–10",
                    icon: "move_down",
                    keys: "SUPER + SHIFT",
                    mods: true,
                    suffix: "1 … 0"
                },
                {
                    id: "wheel_workspaces",
                    title: "Workspaces with the wheel",
                    icon: "mouse",
                    keys: "SUPER",
                    mods: true,
                    suffix: "Wheel"
                },
                {
                    id: "wheel_columns",
                    title: "Scroll the columns with the wheel",
                    icon: "swap_horiz",
                    keys: "SUPER + SHIFT",
                    mods: true,
                    suffix: "Wheel"
                },
                {
                    id: "column_full",
                    title: "Column to the full width",
                    icon: "width_full",
                    keys: "SUPER + F"
                },
                {
                    id: "column_narrower",
                    title: "Narrower column",
                    icon: "remove",
                    keys: "SUPER + minus"
                },
                {
                    id: "column_wider",
                    title: "Wider column",
                    icon: "add",
                    keys: "SUPER + equal"
                },
                {
                    id: "column_center",
                    title: "Centre the column",
                    icon: "align_horizontal_center",
                    keys: "SUPER + X"
                },
                {
                    id: "arrows_column",
                    title: "Move the column",
                    icon: "view_column",
                    keys: "SUPER + CTRL",
                    mods: true,
                    suffix: "← →"
                },
                {
                    id: "arrows_window",
                    title: "Move the window",
                    icon: "drag_pan",
                    keys: "SUPER + SHIFT",
                    mods: true,
                    suffix: "← → ↑ ↓"
                }
            ]
        },
        {
            title: "Screenshots",
            items: [
                {
                    id: "screenshot_area",
                    title: "Screenshot of an area",
                    icon: "screenshot_region",
                    keys: "Print"
                },
                {
                    id: "screenshot_screen",
                    title: "Screenshot of the screen",
                    icon: "screenshot_monitor",
                    keys: "SHIFT + Print"
                }
            ]
        }
    ]

    // Not changeable, shown for reference (and as taken).
    readonly property var fixed: [
        {
            title: "Switch windows",
            keys: "ALT + Tab"
        },
        {
            title: "Switch windows, backwards",
            keys: "ALT + SHIFT + Tab"
        },
        {
            title: "Cancel switching",
            keys: "ALT + Escape"
        }
    ]

    readonly property var items: sections.reduce((all, s) => all.concat(s.items), [])

    function item(id: string): var {
        return items.find(i => i.id === id) ?? null;
    }

    readonly property var changed: Config.input.shortcuts ?? ({})

    // The combination in use ("" when off).
    function keys(id: string): string {
        const c = changed[id];
        return c !== undefined ? c : (item(id)?.keys ?? "");
    }

    function isDefault(id: string): bool {
        return changed[id] === undefined;
    }

    function set(id: string, keys: string): void {
        const next = Object.assign({}, changed);
        if (keys === item(id)?.keys)
            delete next[id];
        else
            next[id] = keys;
        Config.input.shortcuts = next;
    }

    function reset(id: string): void {
        set(id, item(id)?.keys ?? "");
    }

    function resetAll(): void {
        Config.input.shortcuts = {};
    }

    // Every key combination an entry takes (a group: its modifiers with
    // each of its keys), in one spelling, for spotting clashes.
    readonly property var groupKeys: ({
            arrows: ["left", "right", "up", "down"],
            arrows_column: ["left", "right"],
            arrows_window: ["left", "right", "up", "down"],
            workspace_go: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
            workspace_move: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
            wheel_workspaces: ["mouse_down", "mouse_up"],
            wheel_columns: ["mouse_down", "mouse_up"]
        })

    function normalize(keys: string): string {
        const parts = keys.split("+").map(p => p.trim()).filter(p => p);
        const order = ["SUPER", "CTRL", "ALT", "SHIFT"];
        const mods = order.filter(m => parts.some(p => p.toUpperCase() === m));
        const rest = parts.filter(p => !order.includes(p.toUpperCase())).map(p => p.toLowerCase());
        return mods.concat(rest).join("+");
    }

    function taken(id: string): var {
        const k = keys(id);
        if (!k)
            return [];
        const it = item(id);
        if (it?.mods)
            return (groupKeys[id] ?? []).map(key => normalize(`${k} + ${key}`));
        return [normalize(k)];
    }

    // What else uses one of this entry's combinations: titles.
    function clashes(id: string): var {
        const mine = taken(id);
        if (!mine.length)
            return [];
        const out = [];
        for (const it of items) {
            if (it.id !== id && taken(it.id).some(k => mine.includes(k)))
                out.push(it.title);
        }
        for (const f of fixed) {
            if (mine.includes(normalize(f.keys)))
                out.push(f.title);
        }
        return out;
    }

    // For showing: "Super + Shift + F", "Print Screen", "←".
    function pretty(keys: string): string {
        if (!keys)
            return "Off";
        const names = {
            SUPER: "Super",
            CTRL: "Ctrl",
            ALT: "Alt",
            SHIFT: "Shift",
            SPACE: "Space",
            left: "←",
            right: "→",
            up: "↑",
            down: "↓",
            minus: "-",
            equal: "=",
            comma: ",",
            period: ".",
            slash: "/",
            backslash: "\\",
            semicolon: ";",
            apostrophe: "'",
            grave: "`",
            bracketleft: "[",
            bracketright: "]",
            Return: "Enter",
            Escape: "Esc",
            BackSpace: "Backspace",
            Prior: "Page Up",
            Next: "Page Down",
            Print: "Print Screen"
        };
        return keys.split("+").map(p => p.trim()).filter(p => p).map(p => names[p] ?? names[p.toUpperCase()] ?? p).join(" + ");
    }

    // Keys by xkb keycode (the key's place, whatever the layout: a Russian
    // "Й" is Q), as Hyprland names them.
    readonly property var keyNames: {
        const n = {
            9: "Escape",
            20: "minus",
            21: "equal",
            22: "BackSpace",
            23: "Tab",
            34: "bracketleft",
            35: "bracketright",
            36: "Return",
            47: "semicolon",
            48: "apostrophe",
            49: "grave",
            51: "backslash",
            59: "comma",
            60: "period",
            61: "slash",
            65: "SPACE",
            107: "Print",
            110: "Home",
            111: "up",
            112: "Prior",
            113: "left",
            114: "right",
            115: "End",
            116: "down",
            117: "Next",
            118: "Insert",
            119: "Delete",
            95: "F11",
            96: "F12"
        };
        "1234567890".split("").forEach((c, i) => n[10 + i] = c);
        "QWERTYUIOP".split("").forEach((c, i) => n[24 + i] = c);
        "ASDFGHJKL".split("").forEach((c, i) => n[38 + i] = c);
        "ZXCVBNM".split("").forEach((c, i) => n[52 + i] = c);
        for (let i = 0; i < 10; i++)
            n[67 + i] = `F${i + 1}`;
        return n;
    }

    function modsOf(modifiers: int): var {
        const m = [];
        if (modifiers & Qt.MetaModifier)
            m.push("SUPER");
        if (modifiers & Qt.ControlModifier)
            m.push("CTRL");
        if (modifiers & Qt.AltModifier)
            m.push("ALT");
        if (modifiers & Qt.ShiftModifier)
            m.push("SHIFT");
        return m;
    }

    // While recording, Hyprland's binds are set aside (keybindings.lua).
    function captureStart(): void {
        Quickshell.execDetached(["hyprctl", "eval", "kirin_capture_start()"]);
    }

    function captureEnd(): void {
        Quickshell.execDetached(["hyprctl", "eval", "kirin_capture_end()"]);
    }
}
