pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Updating kirin (Settings → Update).
//
// Two parts, two versions:
//   - the shell: the git checkout in ~/.kirin ($KIRIN_DIR), on any system;
//   - the system (NixOS with kirin's module): what nix/update.nix builds,
//     the commit it was built from in /etc/kirin/system.json. Only there:
//     elsewhere (another distribution, NixOS without the module) the
//     system's settings don't show and an update is the checkout's alone.
// Checked once a day (and when the settings open): `git fetch`, then how
// the checkout and the system compare with the branch it tracks.
//
// Updating on NixOS: the system first (kirin-update.service: the flake's
// kirin input, a rebuild, the cleanup), then the checkout moves to the
// very commit the system was built from, so the two never differ. With
// "One-click system update" on (a flag only root sets: `pkexec
// kirin-auto-update`) the Update button runs that without a password; off,
// the page shows the commands. Nothing updates on its own. Elsewhere: the checkout moves to the branch's latest.
// Never with changes in the checkout: files changed (stash them) or commits
// of its own (for git, by hand).
Singleton {
    id: root

    readonly property string dir: Quickshell.env("KIRIN_DIR") || `${Quickshell.env("HOME")}/.kirin`
    readonly property string statePath: `${Wallpaper.stateDir}/update.json`

    // NixOS with kirin's module: { rev, flake, host }; null elsewhere.
    property var system: null
    readonly property bool managed: system !== null
    property bool autoUpdate: false
    // The system's flake can be changed without sudo (the user's own, like
    // ~/nixos-config): `nix flake update` as them, so flake.lock stays theirs.
    property bool flakeWritable: false

    // The checkout.
    property bool present: false
    // Copied offline at the first login: files, no commits.
    property bool noHistory: false
    property string head: ""
    property string upstream: ""
    property string remote: ""
    property int dirty: 0
    property int ahead: 0
    property int behind: 0
    // Commits to come: { rev, time, subject }.
    property var commits: []
    // The update touches the system (nix/, plugins/, cli/, install/).
    property bool systemChanges: false
    property bool fetchFailed: false

    property bool checking: false
    property real lastCheck: 0
    property string notifiedRev: ""

    property bool updating: false
    // The update's steps, in order: { id, label, state: "pending" |
    // "active" | "done" | "failed", log }. The system's follow its
    // service's "==> " lines (nix/update.nix); each keeps its own output.
    property var stages: []
    // How far along, 0..1: the steps weighted by how long they take.
    readonly property real progress: {
        let total = 0, done = 0;
        for (const st of stages) {
            const w = stageWeights[st.id] ?? 1;
            total += w;
            if (st.state === "done")
                done += w;
            else if (st.state === "active")
                done += w / 2;
        }
        return total > 0 ? done / total : 0;
    }
    readonly property var stageWeights: ({
            flake: 1,
            build: 6,
            switch: 2,
            cleanup: 2,
            shell: 1,
            restart: 1
        })
    property string error: ""
    // Hyprland (or its plugin) changed under the session: log out to finish.
    property bool needsRelogin: false

    readonly property bool shellBehind: remote !== "" && head !== remote
    readonly property bool systemBehind: managed && remote !== "" && system.rev !== remote
    readonly property bool available: !noHistory && (shellBehind || systemBehind)
    // Nothing of the user's in the way.
    readonly property bool clean: dirty === 0 && ahead === 0

    function shortRev(rev: string): string {
        return rev ? rev.slice(0, 7) : "";
    }

    // --- Checking ---------------------------------------------------------------

    function check(): void {
        if (checking || updating)
            return;
        checking = true;
        systemFile.reload();
        flagCheck.running = true;
        checker.running = true;
    }

    FileView {
        id: systemFile

        path: "/etc/kirin/system.json"
        printErrors: false
        onLoaded: {
            try {
                root.system = JSON.parse(text());
                flakeAccess.running = true;
            } catch (e) {
                root.system = null;
            }
        }
        onLoadFailed: root.system = null
    }

    Process {
        id: flagCheck

        command: ["test", "-e", "/var/lib/kirin/auto-update"]
        onExited: code => root.autoUpdate = code === 0
    }

    Process {
        id: flakeAccess

        command: ["test", "-w", `${root.system?.flake ?? "/nonexistent"}/flake.lock`]
        onExited: code => root.flakeWritable = code === 0
    }

    Process {
        id: checker

        environment: ({
                DIR: root.dir,
                SYSREV: root.system?.rev ?? ""
            })
        command: ["sh", "-c", `
            cd "$DIR" 2>/dev/null && [ -f install/manifest.toml ] || { echo "@absent"; exit 0; }
            git rev-parse -q --verify HEAD >/dev/null 2>&1 || { echo "@nohistory"; exit 0; }
            GIT_TERMINAL_PROMPT=0 timeout 60 git fetch --quiet origin 2>/dev/null || echo "@fetchfailed"
            up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo origin/main)
            echo "@upstream $up"
            echo "@head $(git rev-parse HEAD)"
            echo "@remote $(git rev-parse -q --verify "$up" 2>/dev/null)"
            echo "@dirty $(git status --porcelain | wc -l)"
            echo "@ahead $(git rev-list --count "$up..HEAD" 2>/dev/null || echo 0)"
            echo "@behind $(git rev-list --count "HEAD..$up" 2>/dev/null || echo 0)"
            from=$(git rev-parse HEAD)
            [ -n "$SYSREV" ] && git cat-file -e "$SYSREV^{commit}" 2>/dev/null && [ "$(git rev-list --count "$SYSREV..$from" 2>/dev/null)" = 0 ] && from=$SYSREV
            if [ -n "$SYSREV" ] && ! git cat-file -e "$SYSREV^{commit}" 2>/dev/null; then echo "@system unknown"; fi
            echo "@files"
            git diff --name-only "$from" "$up" 2>/dev/null
            echo "@commits"
            git log --format='%h%x09%ct%x09%s' "$from..$up" 2>/dev/null | head -50
        `]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        onExited: {
            root.checking = false;
            root.lastCheck = Date.now();
            root.saveState();
            root.afterCheck();
        }
    }

    function parse(text: string): void {
        present = !text.includes("@absent");
        noHistory = text.includes("@nohistory");
        fetchFailed = text.includes("@fetchfailed");
        if (!present || noHistory) {
            commits = [];
            return;
        }
        let section = "";
        const files = [];
        const list = [];
        let systemUnknown = false;
        for (const line of text.split("\n")) {
            if (line === "@files" || line === "@commits") {
                section = line;
                continue;
            }
            const m = line.match(/^@(\w+)\s*(.*)$/);
            if (m) {
                const v = m[2].trim();
                switch (m[1]) {
                case "upstream":
                    upstream = v;
                    break;
                case "head":
                    head = v;
                    break;
                case "remote":
                    remote = v;
                    break;
                case "dirty":
                    dirty = parseInt(v) || 0;
                    break;
                case "ahead":
                    ahead = parseInt(v) || 0;
                    break;
                case "behind":
                    behind = parseInt(v) || 0;
                    break;
                case "system":
                    systemUnknown = true;
                    break;
                }
                continue;
            }
            if (!line)
                continue;
            if (section === "@files")
                files.push(line);
            else if (section === "@commits") {
                const [rev, time, ...subject] = line.split("\t");
                list.push({
                    rev,
                    time: parseInt(time) * 1000,
                    subject: subject.join("\t")
                });
            }
        }
        commits = list;
        systemChanges = managed && (systemUnknown || files.some(f => /^(nix|plugins|cli|install)\//.test(f) || f === "flake.nix" || f === "flake.lock"));
    }

    // Once a check is done: a notification for a new version (once each).
    // Updating is always the user's: the Update button.
    function afterCheck(): void {
        if (!available || remote === notifiedRev)
            return;
        notifiedRev = remote;
        saveState();
        Quickshell.execDetached(["notify-send", "-a", "Kirin", "-i", "system-software-update", "Update available", clean ? `${commits.length || "New"} changes to kirin. Settings → Update.` : "kirin has an update, but ~/.kirin has changes of yours. Settings → Update."]);
    }

    // --- Updating -----------------------------------------------------------------

    // The Hyprland and plugin the session runs, to tell if an update
    // changed them.
    property string hyprlandBefore: ""
    property string pluginBefore: ""

    function update(): void {
        if (updating || !clean || !available)
            return;
        updating = true;
        error = "";
        const system = managed && systemBehind;
        const list = [];
        if (system) {
            list.push({ id: "flake", label: "Updating kirin in the system's flake" });
            list.push({ id: "build", label: "Building the system" });
            list.push({ id: "switch", label: "Switching to the new system" });
            if (Config.update.cleanup)
                list.push({ id: "cleanup", label: "Cleaning up old systems" });
        }
        list.push({ id: "shell", label: `Updating the shell (${dir.replace(Quickshell.env("HOME"), "~")})` });
        list.push({ id: "restart", label: "Restarting the shell" });
        stages = list.map(st => Object.assign(st, { state: "pending", log: "" }));
        if (system) {
            setStage("flake", "active");
            stamps.running = true;
            journal.running = true;
            systemUpdate.running = true;
        } else {
            moveCheckout(remote);
        }
    }

    // A step's state; making one active finishes the ones before it.
    function setStage(id: string, state: string): void {
        const i = stages.findIndex(st => st.id === id);
        if (i < 0)
            return;
        stages = stages.map((st, j) => {
            const copy = Object.assign({}, st);
            if (j === i)
                copy.state = state;
            else if (j < i && state === "active" && st.state !== "failed")
                copy.state = "done";
            return copy;
        });
    }

    function stageLog(id: string, line: string): void {
        stages = stages.map(st => {
            if (st.id !== id)
                return st;
            const lines = (st.log + line + "\n").split("\n");
            return Object.assign({}, st, { log: lines.slice(-200).join("\n") });
        });
    }

    // The active step (where output goes), or the first.
    function activeStage(): string {
        const st = stages.find(st => st.state === "active");
        return st ? st.id : (stages[0]?.id ?? "");
    }

    // The step that went wrong, and the update stops there.
    function failStage(message: string): void {
        setStage(activeStage(), "failed");
        updating = false;
        error = message;
    }

    // The service's "==> " lines: which step it's at.
    readonly property var markers: [["==> Updating kirin", "flake"], ["==> Building", "build"], ["==> Switching", "switch"], ["==> Keeping the last", "cleanup"]]

    Process {
        id: stamps

        command: ["sh", "-c", "readlink -f /run/current-system/sw/bin/Hyprland; cat /etc/kirin/plugins.lua 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                root.hyprlandBefore = lines[0] ?? "";
                root.pluginBefore = lines.slice(1).join("\n");
            }
        }
    }

    // The system: as root (with auto update on, no password; else polkit
    // asks).
    Process {
        id: systemUpdate

        command: ["systemctl", "start", "kirin-update.service"]
        stderr: StdioCollector {
            id: systemErr
        }
        onExited: code => {
            journal.running = false;
            if (code !== 0) {
                root.failStage(systemErr.text.trim() || "The system update failed: see the log (journalctl -u kirin-update).");
                return;
            }
            root.setStage("shell", "active");
            afterSystem.running = true;
        }
    }

    // Its progress, line by line.
    Process {
        id: journal

        command: ["journalctl", "-fu", "kirin-update.service", "-n", "0", "-o", "cat"]
        stdout: SplitParser {
            onRead: line => {
                const marker = root.markers.find(m => line.startsWith(m[0]));
                if (marker)
                    root.setStage(marker[1], "active");
                root.stageLog(root.activeStage(), line);
            }
        }
    }

    // Built: the checkout goes to the system's commit; did Hyprland change?
    Process {
        id: afterSystem

        command: ["sh", "-c", "cat /etc/kirin/system.json; echo; readlink -f /run/current-system/sw/bin/Hyprland; cat /etc/kirin/plugins.lua 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                try {
                    root.system = JSON.parse(lines[0]);
                } catch (e) {}
                const hyprland = lines[1] ?? "";
                const plugin = lines.slice(2).join("\n");
                root.needsRelogin = (root.hyprlandBefore !== "" && hyprland !== root.hyprlandBefore) || (root.pluginBefore !== "" && plugin !== root.pluginBefore);
                root.moveCheckout(root.system?.rev ?? root.remote);
            }
        }
    }

    function moveCheckout(rev: string): void {
        setStage("shell", "active");
        mover.target = rev;
        mover.running = true;
    }

    // Fast-forward only: with nothing of the user's in the way it always is.
    Process {
        id: mover

        property string target: ""

        command: ["git", "-C", root.dir, "merge", "--ff-only", "--quiet", target]
        stderr: StdioCollector {
            id: moverErr
        }
        onExited: code => {
            const message = moverErr.text.trim();
            if (message)
                root.stageLog("shell", message);
            if (code !== 0) {
                root.failStage(message || "Couldn't update ~/.kirin.");
                root.check();
                return;
            }
            root.updating = false;
            root.setStage("restart", "active");
            root.check();
            // The new shell (Hyprland picks its config up by itself).
            restartTimer.start();
        }
    }

    Timer {
        id: restartTimer

        interval: 1500
        onTriggered: Quickshell.reload(true)
    }

    // --- The checkout's own changes ---------------------------------------------

    function stash(): void {
        stasher.running = true;
    }

    Process {
        id: stasher

        command: ["git", "-C", root.dir, "stash", "push", "--include-untracked", "--quiet", "-m", "kirin: before updating"]
        onExited: root.check()
    }

    // Offline copy, no history: becomes the branch's checkout (what was
    // copied is the same files).
    function connect(): void {
        connector.running = true;
    }

    Process {
        id: connector

        environment: ({
                DIR: root.dir
            })
        command: ["sh", "-c", "cd \"$DIR\" && GIT_TERMINAL_PROMPT=0 git fetch --quiet origin && git reset --quiet --hard origin/main && git branch --quiet -M main && git branch --quiet -u origin/main"]
        stderr: StdioCollector {
            id: connectorErr
        }
        onExited: code => {
            if (code !== 0)
                root.error = connectorErr.text.trim() || "Couldn't reach the repository.";
            root.check();
        }
    }

    // --- NixOS settings -----------------------------------------------------------

    function setAutoUpdate(on: bool): void {
        autoToggle.command = ["pkexec", "/run/current-system/sw/bin/kirin-auto-update", on ? "on" : "off"];
        autoToggle.running = true;
    }

    Process {
        id: autoToggle

        onExited: flagCheck.running = true
    }

    property bool cleaning: false
    property string cleanupResult: ""

    function cleanupNow(): void {
        if (cleaning)
            return;
        cleaning = true;
        cleanupResult = "";
        cleaner.running = true;
    }

    Process {
        id: cleaner

        command: ["sh", "-c", "systemctl start kirin-cleanup.service && journalctl -u kirin-cleanup.service -n 30 -o cat --no-pager | grep -i 'freed' | tail -1"]
        stdout: StdioCollector {
            id: cleanerOut
        }
        onExited: code => {
            root.cleaning = false;
            root.cleanupResult = code === 0 ? (cleanerOut.text.trim() || "Done") : "Didn't run";
        }
    }

    // --- State: the last check, the version notified about ---------------------

    FileView {
        id: state

        path: root.statePath
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.lastCheck = s.lastCheck ?? 0;
                root.notifiedRev = s.notifiedRev ?? "";
            } catch (e) {}
        }
    }

    function saveState(): void {
        state.setText(JSON.stringify({
            lastCheck,
            notifiedRev
        }) + "\n");
    }

    // Once a day: looked at hourly, checked when a day has passed (and a
    // couple of minutes after starting, for the network to be up).
    readonly property bool running: true

    Timer {
        running: true
        interval: 2 * 60 * 1000
        onTriggered: {
            if (Date.now() - root.lastCheck > 24 * 3600 * 1000)
                root.check();
        }
    }

    Timer {
        running: true
        repeat: true
        interval: 3600 * 1000
        onTriggered: {
            if (Date.now() - root.lastCheck > 24 * 3600 * 1000)
                root.check();
        }
    }

    Component.onCompleted: {
        systemFile.reload();
        flagCheck.running = true;
    }
}
