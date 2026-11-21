pragma Singleton

import QtQuick
import Quickshell

// The bar's bottom modules: which exist, their order and which are shown
// (Config.bar.modules / hiddenModules, edited in Settings → Bar).
Singleton {
    id: root

    readonly property var known: [
        {
            id: "notifications",
            label: "Notifications",
            icon: "notifications"
        },
        {
            id: "tray",
            label: "System tray",
            icon: "apps"
        },
        {
            id: "media",
            label: "Media",
            icon: "music_note"
        },
        {
            id: "brightness",
            label: "Brightness",
            icon: "brightness_6"
        },
        {
            id: "volume",
            label: "Sound",
            icon: "volume_up"
        },
        {
            id: "wifi",
            label: "Network",
            icon: "wifi"
        },
        {
            id: "bluetooth",
            label: "Bluetooth",
            icon: "bluetooth"
        },
        {
            id: "battery",
            label: "Battery",
            icon: "battery_full"
        },
        {
            id: "keyboard",
            label: "Keyboard layout",
            icon: "keyboard"
        },
        {
            id: "clock",
            label: "Clock",
            icon: "schedule"
        }
    ]

    // All known ids in the configured order: unknown ones dropped, missing
    // ones (modules added since) put after their neighbour in `known`.
    readonly property var order: {
        const ids = known.map(m => m.id);
        const list = (Config.bar.modules ?? []).filter((id, i, a) => ids.includes(id) && a.indexOf(id) === i);
        ids.forEach((id, i) => {
            if (list.includes(id))
                return;
            const before = ids.slice(0, i).reverse().find(b => list.includes(b));
            list.splice(before ? list.indexOf(before) + 1 : 0, 0, id);
        });
        // Grouped: together, where the first of them is.
        if (!groupOn)
            return list;
        const first = list.findIndex(id => grouped.includes(id));
        const group = list.filter(id => grouped.includes(id));
        const rest = list.filter(id => !grouped.includes(id));
        rest.splice(list.slice(0, first).filter(id => !grouped.includes(id)).length, 0, ...group);
        return rest;
    }
    readonly property var hidden: Config.bar.hiddenModules ?? []
    // As a string first, so the bar only rebuilds when the list really
    // changes (the config file being read again assigns equal arrays).
    readonly property string shownKey: order.filter(id => !hidden.includes(id)).join(",")
    readonly property var shown: shownKey ? shownKey.split(",") : []

    // These share one plate on the bar (Controls.qml): a gear, and they
    // come out above it on hover. Kept together in the order, moved as one
    // (Settings → Bar); among themselves in any order. Off in Settings →
    // Bar: ordinary modules.
    readonly property var grouped: ["brightness", "volume", "wifi", "bluetooth"]
    readonly property bool groupOn: Config.bar.groupControls ?? true
    // The grouped ones in their order (shown or not), and the shown ones.
    readonly property var groupOrder: groupOn ? order.filter(id => grouped.includes(id)) : []
    readonly property var controls: groupOn ? shown.filter(id => grouped.includes(id)) : []

    // A list with the grouped ones as one "controls" entry, if grouped.
    function collapse(list: var): var {
        if (!groupOn)
            return list;
        const out = [];
        list.forEach(id => {
            if (!grouped.includes(id))
                out.push(id);
            else if (!out.includes("controls"))
                out.push("controls");
        });
        return out;
    }

    // What the bar lays out (shown ones), and what Settings → Bar lists.
    readonly property var rows: collapse(shown)
    readonly property var entries: collapse(order)

    function info(id: string): var {
        if (id === "controls")
            return {
                id: id,
                label: "Controls",
                icon: "settings"
            };
        return known.find(m => m.id === id) ?? {
            id: id,
            label: id,
            icon: "widgets"
        };
    }

    function isShown(id: string): bool {
        return !hidden.includes(id);
    }

    function setShown(id: string, show: bool): void {
        const rest = hidden.filter(h => h !== id);
        Config.bar.hiddenModules = show ? rest : rest.concat([id]);
    }

    // Moves a module up (-1) or down (+1).
    function move(id: string, delta: int): void {
        const list = order.slice();
        const from = list.indexOf(id), to = from + delta;
        if (from < 0 || to < 0 || to >= list.length)
            return;
        list.splice(from, 1);
        list.splice(to, 0, id);
        Config.bar.modules = list;
    }

    // Puts an entry (a module, or the "controls" group) at the given
    // position among the entries (dragged in Settings → Bar).
    function moveTo(id: string, index: int): void {
        const list = entries.filter(m => m !== id);
        list.splice(Math.max(0, Math.min(index, list.length)), 0, id);
        Config.bar.modules = expand(list, groupOrder);
    }

    // Entries back to modules: "controls" as the group's (no flatMap in QML).
    function expand(list: var, group: var): var {
        return list.reduce((out, m) => out.concat(m === "controls" ? group : [m]), []);
    }

    // Moves one of the grouped modules within the group.
    function moveInGroup(id: string, index: int): void {
        const group = groupOrder.filter(m => m !== id);
        group.splice(Math.max(0, Math.min(index, group.length)), 0, id);
        Config.bar.modules = expand(entries, group);
    }

    function reset(): void {
        Config.bar.modules = known.map(m => m.id);
        Config.bar.hiddenModules = [];
        Config.bar.groupControls = true;
        Config.bar.moduleSpacing = 10;
    }
}
