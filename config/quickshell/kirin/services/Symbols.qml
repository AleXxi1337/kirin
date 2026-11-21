pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// One-colour app icons for the bar: Papirus's symbolic set. Found in
// share/kirin/symbols (nixos-config's pkgs/papirus-symbolic.nix, just that
// set) or in the Papirus icon theme as distributions package it
// (share/icons/Papirus*/<size>/symbolic). `paths`: icon name (without .svg)
// -> file.
Singleton {
    id: root

    property var paths: ({})
    readonly property bool available: Object.keys(paths).length > 0

    function find(name: string): string {
        return paths[name] ?? "";
    }

    Process {
        running: true
        command: ["sh", "-c", `IFS=:
            for d in "\${XDG_DATA_HOME:-$HOME/.local/share}" \${XDG_DATA_DIRS:-/usr/local/share:/usr/share:/run/current-system/sw/share}; do
                # -L: folders may be links (NixOS profiles link into the store).
                for s in "$d/kirin/symbols" "$d"/icons/Papirus/24x24/symbolic "$d"/icons/Papirus-Dark/24x24/symbolic "$d"/icons/Papirus/16x16/symbolic; do
                    [ -d "$s" ] && find -L "$s" -name '*.svg'
                done
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = {};
                for (const file of text.split("\n")) {
                    const name = file.slice(file.lastIndexOf("/") + 1).replace(/\.svg$/, "");
                    if (name && !p[name])
                        p[name] = file;
                }
                root.paths = p;
            }
        }
    }
}
