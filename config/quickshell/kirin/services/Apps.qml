pragma Singleton

import QtQuick
import Quickshell

// Starts apps and opens files for the user. Quickshell from nixpkgs runs in
// a wrapper that points Qt at its own Qt build (plugin and QML paths, extra
// libraries); apps started from it would inherit that, and Qt apps built
// against another Qt (Telegram, Happ, ...) crash loading those plugins. So
// everything started on the user's behalf goes through here, without them.
Singleton {
    id: root

    // null removes the variable.
    readonly property var cleanEnvironment: ({
            QT_PLUGIN_PATH: null,
            QML_IMPORT_PATH: null,
            QML2_IMPORT_PATH: null,
            NIXPKGS_QT6_QML_IMPORT_PATH: null,
            NIXPKGS_QT5_QML_IMPORT_PATH: null,
            LD_LIBRARY_PATH: null
        })

    function run(command: var, workingDirectory: string): void {
        Quickshell.execDetached({
            command,
            environment: cleanEnvironment,
            workingDirectory: workingDirectory || Quickshell.env("HOME")
        });
    }

    // A desktop entry, by its Exec command (DesktopEntry.execute() would use
    // D-Bus activation for some apps, which fails when they don't install the
    // service file, as Telegram's package does).
    function launch(entry: DesktopEntry): void {
        const command = entry.command;
        if (!command?.length)
            return;
        run(entry.runInTerminal ? ["kitty", "-e", ...command] : command, entry.workingDirectory);
    }

    function open(target: string): void {
        run(["xdg-open", target], "");
    }
}
