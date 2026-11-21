//@ pragma UseQApplication
// Icons for tray apps, menus and the launcher (installed by home/user.nix).
//@ pragma IconTheme Colloid-Dark

import QtQuick
import Quickshell
import qs.modules.background
import qs.modules.bar
import qs.modules.launcher
import qs.modules.lock
import qs.modules.media
import qs.modules.notifications
import qs.modules.osd
import qs.modules.settings
import qs.modules.snap
import qs.modules.switcher
import qs.services

ShellRoot {
    // Singletons are created lazily; start the colour scheme service right away.
    Component.onCompleted: {
        Scheme.update();
        HyprSync.apply();
        // Automatic power saver runs without the bar/settings open.
        Power.available;
        // Clipboard history records from the start.
        Clipboard.available;
        // Takes org.freedesktop.Notifications right away.
        Notifs.unread;
        // Idle rules (dim, screen off, sleep) from the start.
        Idle.active;
        // Apps' streams at full volume (Spotify starts at 1%).
        StreamVolume.running;
        // Wi-Fi and Bluetooth back on or off as they were.
        Radios.running;
        // Checks for updates once a day.
        Updates.running;
    }

    Background {}
    Bar {}
    Settings {}
    Launcher {}
    Osd {}
    Popups {}
    MediaPlayer {}
    Lock {}
    SnapPreview {}
    Switcher {}
}
