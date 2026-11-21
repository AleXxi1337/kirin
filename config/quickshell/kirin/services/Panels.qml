pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Lets shell parts open each other, e.g. the bar opening a settings page.
Singleton {
    // Settings.qml listens and opens the page with this label ("Power", ...).
    signal settingsRequested(string page)

    function openSettings(page: string): void {
        settingsRequested(page);
    }

    // The bar card that's on screen (open, or still fading out); only one
    // at a time (modules/bar/BarCard.qml).
    property var barCard: null

    // Started at logging in (hypr/modules/autostart.lua leaves this file
    // for it): read at once, before anything shows, and removed, so a
    // restart later doesn't count. A file, not an environment variable:
    // apps started from kirin would carry that on.
    FileView {
        id: loginMark

        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/kirin-login`
        blockLoading: true
        printErrors: false
    }

    readonly property bool atLogin: loginMark.text().trim() === "1"

    Component.onCompleted: {
        if (atLogin)
            Quickshell.execDetached(["rm", "-f", loginMark.path]);
    }

    // At logging in, until the lock screen is up: the desktop stays black
    // (the background holds it) and the bar away, so nothing shows before
    // the lock screen (modules/lock/Lock.qml).
    property bool loginHold: atLogin

    // The lock screen is coming (or going): the bar slides away to the left
    // first, and comes back after unlocking (modules/lock/Lock.qml).
    property bool locking: atLogin

    // Room the media card takes at the bottom right of the primary monitor
    // (its height and gap, as it comes and goes): notification popups stay
    // above it (modules/media, modules/notifications).
    property real mediaReserve: 0

    // The media card pinned at the bottom right (no window over it): the
    // bar's media icon hides then. And the bar's media card open: the one at
    // the bottom right goes away (modules/media, modules/bar/MediaButton).
    property bool mediaPinned: false
    property bool mediaCardOpen: false

}
