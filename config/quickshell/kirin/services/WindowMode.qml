pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// How Hyprland is set to work (hypr/modules/winmode.lua, Super+Ctrl+Shift+T):
// "tiling" (columns, workspaces) or "windows" (a desktop: floating windows,
// one workspace per monitor, a taskbar on the bar). Read from the file
// winmode.lua keeps, followed as it changes.
Singleton {
    id: root

    readonly property string mode: file.text().trim() === "windows" ? "windows" : "tiling"
    readonly property bool windows: mode === "windows"

    FileView {
        id: file

        path: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/kirin/window-mode`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
}
