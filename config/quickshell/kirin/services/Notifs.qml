pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Notification daemon (org.freedesktop.Notifications): popups at the top
// right (modules/notifications/Popups.qml) and the notification centre in
// the bar (modules/bar/Notifications.qml). History lasts the session.
Singleton {
    id: root

    // Newest first.
    readonly property var list: server.trackedNotifications.values.slice().reverse()
    // Shown as popups right now, oldest first.
    property var popups: []
    // Arrived since the centre was last looked at.
    property int unread: 0
    // Arrival time (ms) by notification id; the spec has no timestamp.
    property var times: ({})

    readonly property bool dnd: Config.notifications.dnd

    // Ticks so "5 min ago" stays right.
    property date now: new Date()

    Timer {
        running: root.list.length > 0
        repeat: true
        interval: 30000
        onTriggered: root.now = new Date()
    }

    NotificationServer {
        id: server

        keepOnReload: false
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: n => {
            n.tracked = true;
            const t = Object.assign({}, root.times);
            t[n.id] = Date.now();
            root.times = t;
            root.now = new Date();
            root.unread += 1;
            n.closed.connect(() => root.forget(n));
            // Screenshots (grimblast --notify): the screenshot sound instead.
            const screenshot = /grimblast|screenshot/i.test(n.appName ?? "");
            if (screenshot)
                SoundFx.trigger("screenshot");
            if (!root.dnd || n.urgency === NotificationUrgency.Critical) {
                root.popups = root.popups.filter(p => p !== n).concat([n]);
                if (!(screenshot && SoundFx.enabled("screenshot")))
                    root.sound(n);
            }
        }
    }

    // --- Sound ---------------------------------------------------------------
    // SoundFx (Settings → Sounds). Apps can ask for their own (sound-file,
    // sound-name hints) or none (suppress-sound); muted apps play their own.

    function isSilent(appName: string): bool {
        const name = (appName ?? "").toLowerCase();
        return (Config.notifications.silentApps ?? []).some(a => a.toLowerCase() === name);
    }

    function sound(n: var): void {
        if (n.hints?.["suppress-sound"] || isSilent(n.appName))
            return;
        SoundFx.notify(n.urgency === NotificationUrgency.Critical, n.hints?.["sound-file"] ?? n.hints?.["sound-name"] ?? "");
    }

    // A sample notification through D-Bus like any app's, so it goes the
    // whole way: popup, sound, do not disturb, the centre.
    function sendTest(): void {
        Quickshell.execDetached(["busctl", "--user", "call", "--", "org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "Notify", "susssasa{sv}i", "Kirin", "0", "preferences-desktop-notification", "Test notification", `This is how notifications look and sound. Sent at ${Qt.formatTime(new Date(), "HH:mm:ss")}.`, "2", "ok", "Got it", "0", "-1"]);
    }

    // A notification from kirin itself, through D-Bus like any app's (no
    // notify-send needed). `critical`: shown in do not disturb too, stays.
    function send(appName: string, icon: string, summary: string, body: string, critical: bool): void {
        Quickshell.execDetached(["busctl", "--user", "call", "--", "org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "Notify", "susssasa{sv}i", appName, "0", icon, summary, body, "0", "1", "urgency", "y", critical ? "2" : "1", "-1"]);
    }

    function forget(n: var): void {
        popups = popups.filter(p => p !== n);
    }

    // Milliseconds a popup stays; 0: until dismissed (critical ones).
    function timeout(n: var): int {
        if (n.urgency === NotificationUrgency.Critical)
            return 0;
        // expireTimeout is in milliseconds (as the app sent it); -1/0: ours.
        return n.expireTimeout > 0 ? n.expireTimeout : Config.notifications.timeout * 1000;
    }

    // The popup goes; the notification stays in the centre (unless transient).
    function hidePopup(n: var): void {
        popups = popups.filter(p => p !== n);
        if (n.transient)
            n.expire();
    }

    function dismiss(n: var): void {
        popups = popups.filter(p => p !== n);
        n.dismiss();
    }

    function clear(): void {
        popups = [];
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
        unread = 0;
    }

    // Buttons: every action but the default one (clicking the notification).
    function buttons(n: var): var {
        return (n?.actions ?? []).filter(a => a.identifier !== "default");
    }

    function invoke(n: var, action: var): void {
        action.invoke();
        if (!n.resident)
            dismiss(n);
    }

    // Clicking the notification: its default action, if any, then it goes.
    function activate(n: var): void {
        const action = (n?.actions ?? []).find(a => a.identifier === "default");
        if (action)
            invoke(n, action);
        else
            hidePopup(n);
    }

    function age(n: var): string {
        const t = times[n?.id];
        if (!t)
            return "";
        const minutes = Math.floor((now.getTime() - t) / 60000);
        if (minutes < 1)
            return "now";
        if (minutes < 60)
            return `${minutes} min`;
        if (minutes < 24 * 60)
            return `${Math.floor(minutes / 60)} h`;
        return Qt.formatDateTime(new Date(t), "d MMM");
    }
}
