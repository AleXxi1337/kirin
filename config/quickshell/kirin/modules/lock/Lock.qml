pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.services

// The lock screen (ext-session-lock): the look is LockView, on every
// monitor; this is the session, the password check (PAM) and the state the
// views share. Two stages: "clock" (the wallpaper, the time and date, like
// a locked phone) and "password" (blurred, a field to type into). Any key
// or click goes from the first to the second; Escape, or a while without
// typing, goes back.
//
//   qs -c kirin ipc call lock lock
//
// PAM service: "kirin" when the system has one (/etc/pam.d/kirin), else
// one a screen locker installed (hyprlock, swaylock), else "login".
Scope {
    id: root

    // Shared by the views on all monitors.
    QtObject {
        id: ctx

        // "clock" or "password".
        property string stage: "clock"
        // What's typed; never shown, only its length.
        property string buffer: ""
        readonly property bool checking: pam.active
        // Counts wrong passwords: views shake on each change.
        property int failures: 0
        property string message: ""
        property bool capsLock: false
        property string layout: ""
        // The views play their way out, then the session unlocks.
        property bool unlocking: false
        // Going to sleep: the views go dark instead of showing the clock;
        // waking, it lifts and the clock comes in.
        property bool asleep: false
        // Locked by going to sleep (the lid, the power button, idle): woken
        // up, it's straight at the password. Locked by hand or at logging
        // in: the clock first.
        property bool fromSleep: false
        // Locked at logging in: it starts black and the dark lifts onto
        // the clock, as on waking from sleep.
        property bool fromBoot: false

        function wake(): void {
            // Without a password (Settings → Power): straight in.
            if (Config.power.noPassword) {
                if (!unlocking)
                    unlocking = true;
                return;
            }
            if (stage !== "password")
                stage = "password";
            idle.restart();
        }

        function sleep(): void {
            buffer = "";
            message = "";
            stage = "clock";
        }

        function submit(): void {
            if (buffer.length === 0 || checking || unlocking)
                return;
            message = "";
            pam.start();
        }

        function handleKey(event: var): void {
            root.readKeyboard();
            if (unlocking || asleep)
                return;
            // The power button (and sleep, volume, brightness, media keys)
            // isn't someone at the keyboard: no waking, no typing. The power
            // button's own press puts the machine to sleep (logind).
            if (root.serviceKeys.includes(event.key))
                return;
            // The key that wakes it only wakes it.
            if (stage === "clock") {
                wake();
                return;
            }
            idle.restart();
            if (checking)
                return;
            if (event.key === Qt.Key_Escape) {
                sleep();
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                submit();
            } else if (event.key === Qt.Key_Backspace) {
                buffer = event.modifiers & Qt.ControlModifier ? "" : buffer.slice(0, -1);
            } else if (root.printable(event.text)) {
                buffer += event.text;
                message = "";
            }
        }
    }

    readonly property var serviceKeys: [Qt.Key_PowerOff, Qt.Key_PowerDown, Qt.Key_Sleep, Qt.Key_Suspend, Qt.Key_Hibernate, Qt.Key_WakeUp, Qt.Key_Standby, Qt.Key_VolumeUp, Qt.Key_VolumeDown, Qt.Key_VolumeMute, Qt.Key_MicMute, Qt.Key_MonBrightnessUp, Qt.Key_MonBrightnessDown, Qt.Key_KeyboardBrightnessUp, Qt.Key_KeyboardBrightnessDown, Qt.Key_KeyboardLightOnOff, Qt.Key_MediaPlay, Qt.Key_MediaPause, Qt.Key_MediaTogglePlayPause, Qt.Key_MediaStop, Qt.Key_MediaNext, Qt.Key_MediaPrevious, Qt.Key_Display, Qt.Key_TouchpadToggle, Qt.Key_WLAN, Qt.Key_Bluetooth]

    function printable(text: string): bool {
        return /^[^\x00-\x1F\x7F-\x9F]+$/.test(text ?? "");
    }

    // --- Locking and unlocking, with the desktop clearing first ---------------
    // Locking: the bar slides away and every monitor moves to an empty
    // workspace of its own (name:kirin-lock-<monitor>), so the windows go
    // with Hyprland's workspace animation and only the wallpaper is left;
    // then the lock screen comes in over that same wallpaper. Unlocking:
    // the lock screen goes, the monitors return to their workspaces and the
    // bar slides back. The windows themselves aren't touched, so their
    // layout stays as it was.

    // Before locking: [{ monitor, workspace }] and the focused monitor.
    property var saved: []
    property string savedFocus: ""
    // Between the call and the lock (the desktop clearing).
    property bool clearing: false

    function lock(): void {
        if (session.locked || clearing)
            return;
        ctx.stage = "clock";
        ctx.buffer = "";
        ctx.message = "";
        ctx.unlocking = false;
        ctx.asleep = false;
        ctx.fromSleep = false;
        readKeyboard();
        clearing = true;
        Panels.barCard?.close();
        Panels.locking = true;
        monitors.running = true;
    }

    // Lua for Hyprland: show `workspace` on `monitor`.
    function show(monitor: string, workspace: string): string {
        const ws = /^\d+$/.test(workspace) ? workspace : JSON.stringify(`name:${workspace}`);
        return `hl.dispatch(hl.dsp.focus({ monitor = ${JSON.stringify(monitor)} })); hl.dispatch(hl.dsp.focus({ workspace = ${ws} }));`;
    }

    // Lua table: monitor -> the workspace it showed before locking.
    function homesLua(): string {
        const items = saved.map(s => `[${JSON.stringify(s.monitor)}] = ${/^\d+$/.test(s.workspace) ? s.workspace : JSON.stringify(`name:${s.workspace}`)}`);
        return `{ ${items.join(", ")} }`;
    }

    function refocus(): string {
        return savedFocus ? `hl.dispatch(hl.dsp.focus({ monitor = ${JSON.stringify(savedFocus)} }));` : "";
    }

    Process {
        id: monitors

        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try {
                    list = JSON.parse(text);
                } catch (e) {}
                root.saved = list.filter(m => m.activeWorkspace?.name && !m.activeWorkspace.name.startsWith("kirin-lock")).map(m => ({
                            monitor: m.name,
                            workspace: m.activeWorkspace.name
                        }));
                root.savedFocus = list.find(m => m.focused)?.name ?? "";
                // Then Hyprland keeps them there and sends a window that opens
                // meanwhile back to its own (hypr/modules/lock.lua): the lock
                // screen is see-through.
                const lua = list.map(m => root.show(m.name, `kirin-lock-${m.name}`)).join(" ") + root.refocus() + ` kirin_lock_guard(${root.homesLua()})`;
                if (lua)
                    Quickshell.execDetached(["hyprctl", "eval", lua]);
                cleared.restart();
            }
        }
    }

    // The windows have slid away (Hyprland's workspace animation): lock.
    // At logging in there's nothing to slide away: at once, black.
    Timer {
        id: cleared

        interval: ctx.fromBoot ? 30 : 520
        onTriggered: {
            root.clearing = false;
            session.locked = true;
            loginGiveUp.stop();
            if (ctx.fromBoot)
                bootReveal.restart();
        }
    }

    // At logging in: the lock screen up (black) on every monitor, then the
    // dark lifts.
    Timer {
        id: bootReveal

        interval: 600
        onTriggered: {
            ctx.fromBoot = false;
            Panels.loginHold = false;
        }
    }

    // Started at logging in: locked straight away.
    Component.onCompleted: {
        if (Panels.atLogin) {
            lockAtLogin();
            loginGiveUp.start();
        }
    }

    // The lock screen never came up (the compositor refused it, say): the
    // desktop back rather than black for good.
    Timer {
        id: loginGiveUp

        interval: 8000
        onTriggered: {
            if (session.locked)
                return;
            console.warn("kirin: the lock screen didn't come up at login");
            root.clearing = false;
            ctx.fromBoot = false;
            Panels.loginHold = false;
            Panels.locking = false;
        }
    }

    // Locked when the session starts (hypr/modules/autostart.lua).
    function lockAtLogin(): void {
        if (session.locked || clearing)
            return;
        lock();
        ctx.fromBoot = true;
    }

    function unlocked(): void {
        // Once, though every monitor's view reports it.
        if (!session.locked)
            return;
        session.locked = false;
        const lua = "kirin_lock_guard(nil); " + root.saved.map(s => root.show(s.monitor, s.workspace)).join(" ") + root.refocus();
        if (lua)
            Quickshell.execDetached(["hyprctl", "eval", lua]);
        barBack.restart();
    }

    // The bar follows the windows back in.
    Timer {
        id: barBack

        // After the lock screen's windows have gone (closing them holds the
        // shell up a moment): the bar's slide isn't caught in that.
        interval: 300
        onTriggered: Panels.locking = false
    }

    // Back to the clock after a while without typing.
    Timer {
        id: idle

        interval: 30000
        onTriggered: {
            // Back to the clock, unless locked by sleep: that stays at the
            // password.
            if (!ctx.checking && !ctx.fromSleep)
                ctx.sleep();
        }
    }

    WlSessionLock {
        id: session

        WlSessionLockSurface {
            id: surface

            // See-through: Hyprland draws the desktop under it
            // (misc.session_lock_xray), the wallpaper going on as it was.
            color: "transparent"

            LockView {
                anchors.fill: parent
                ctx: ctx
                screen: surface.screen
                main: !Monitors.primary || surface.screen?.name === Monitors.primary.name
                onUnlocked: root.unlocked()
            }
        }
    }

    // --- Password ------------------------------------------------------------

    property string pamService: "login"

    Process {
        running: true
        command: ["sh", "-c", "for s in kirin hyprlock swaylock; do [ -e /etc/pam.d/$s ] && echo $s && exit; done; echo login"]
        stdout: StdioCollector {
            onStreamFinished: root.pamService = text.trim() || "login"
        }
    }

    PamContext {
        id: pam

        config: root.pamService

        onResponseRequiredChanged: {
            if (!responseRequired)
                return;
            respond(ctx.buffer);
        }

        onCompleted: result => {
            ctx.buffer = "";
            if (result === PamResult.Success) {
                ctx.unlocking = true;
                SoundFx.trigger("unlock");
                return;
            }
            ctx.failures += 1;
            ctx.message = result === PamResult.MaxTries ? "Too many attempts" : result === PamResult.Error ? "Couldn't check the password" : "Wrong password";
        }
    }

    // --- Keyboard: Caps Lock and the layout ------------------------------------

    function readKeyboard(): void {
        keyboard.running = false;
        keyboard.running = true;
    }

    Process {
        id: keyboard

        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const keyboards = JSON.parse(text).keyboards ?? [];
                    const main = keyboards.find(k => k.main) ?? keyboards[0];
                    ctx.capsLock = keyboards.some(k => k.capsLock);
                    const name = main?.active_keymap ?? "";
                    ctx.layout = /russian/i.test(name) ? "ru" : name ? name.slice(0, 2).toLowerCase() : "";
                } catch (e) {}
            }
        }
    }

    // --- Locked before any sleep -------------------------------------------------
    // The lid, the power button, kirin's idle rules (services/Idle.qml) or
    // anything else that sleeps the machine: logind waits for kirin (up to
    // InhibitDelayMaxSec, nixos-config modules/sleep.nix) while it holds a
    // sleep delay. On logind's PrepareForSleep the screen locks, animation
    // and all, then the delay is let go and the machine sleeps. Waking, the
    // delay is taken again and the lock screen shows its clock.

    Process {
        id: sleepDelay

        running: true
        // Both go when kirin does (--pdeathsig): left behind, they'd hold
        // every sleep up for logind's whole delay.
        command: ["setpriv", "--pdeathsig", "TERM", "systemd-inhibit", "--what=sleep", "--who=kirin", "--why=Locking the screen first", "--mode=delay", "setpriv", "--pdeathsig", "TERM", "sleep", "infinity"]
    }

    // logind's signals: "… PrepareForSleep (true,)" going to sleep,
    // "(false,)" back.
    Process {
        id: sleepWatch

        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
        stdout: SplitParser {
            onRead: line => {
                if (!line.includes("PrepareForSleep"))
                    return;
                if (line.includes("(true,)"))
                    root.beforeSleep();
                else if (line.includes("(false,)"))
                    root.afterSleep();
            }
        }
        // Watching goes on if gdbus ever ends.
        onExited: watchAgain.restart()
    }

    Timer {
        id: watchAgain

        interval: 2000
        onTriggered: sleepWatch.running = true
    }

    // When sleep began, and whether it was locked before (then it stays
    // locked whatever: Settings → Power → Password after sleep).
    property real sleptAt: 0
    property bool lockedBeforeSleep: false

    function beforeSleep(): void {
        sleptAt = Date.now();
        lockedBeforeSleep = session.locked || clearing;
        // The windows and the bar go (locking), then it goes dark; already
        // locked, only the dark.
        sleepWait.need = session.locked ? 700 : 1450;
        if (!session.locked && !clearing) {
            lock();
            ctx.fromSleep = true;
        }
        ctx.asleep = true;
        sleepWait.waited = 0;
        sleepWait.restart();
    }

    // Locked and gone dark: sleep may go on. Not past 3.5 s whatever happens
    // (logind gives 5).
    Timer {
        id: sleepWait

        property int waited: 0
        property int need: 1300

        interval: 100
        repeat: true
        onTriggered: {
            waited += interval;
            if ((session.locked && waited >= need) || waited >= 3500) {
                stop();
                root.letSleep();
            }
        }
    }

    function letSleep(): void {
        // Woken up, at the password: turned to it now that it's all dark
        // (at once, no swipe), not before, where its blur came in sharply
        // over the windows going away.
        if (ctx.fromSleep) {
            ctx.stage = "password";
            ctx.buffer = "";
            ctx.message = "";
        }
        sleepDelay.running = false;
    }

    function afterSleep(): void {
        sleepDelay.running = true;
        ctx.asleep = false;
        if (!session.locked || ctx.unlocking)
            return;
        // Locked by sleep and no password wanted: the password stage is
        // skipped, so it opens.
        if (ctx.fromSleep && Config.power.noPassword) {
            ctx.unlocking = true;
            return;
        }
        // A short sleep (and not locked before it): no password, the lock
        // screen goes by itself, as after one.
        const grace = Config.power.passwordAfterSleep * 60 * 1000;
        if (!lockedBeforeSleep && grace > 0 && Date.now() - sleptAt < grace) {
            ctx.unlocking = true;
            return;
        }
        // Locked by sleep: at the password, nothing typed. Locked by hand
        // before it: the clock.
        if (ctx.fromSleep) {
            ctx.buffer = "";
            ctx.message = "";
            idle.restart();
        } else {
            ctx.sleep();
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            root.lock();
        }

        // At logging in: from black, as on waking.
        function boot(): void {
            root.lockAtLogin();
        }

        function isLocked(): bool {
            return session.locked;
        }
    }
}
