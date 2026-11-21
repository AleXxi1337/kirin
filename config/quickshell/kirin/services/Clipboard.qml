pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Clipboard history through cliphist (installed by home/user.nix). kirin runs
// the recorder itself (wl-paste --watch cliphist store) while it's up, so no
// Hyprland exec-once is needed. The launcher shows it as "/clipboard".
Singleton {
    id: root

    property bool available: false
    // Newest first: { line, id, text, image, info }. `line` is cliphist's own
    // "id<TAB>preview", which decode/delete take.
    property var entries: []
    property bool loading: false
    // Image entry id -> thumbnail file, once made.
    property var thumbs: ({})

    readonly property string thumbDir: `${Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"}/kirin/clipboard`

    function refresh(): void {
        if (!available)
            return;
        loading = true;
        lister.running = false;
        lister.running = true;
    }

    // Puts an entry back on the clipboard.
    function copy(line: string): void {
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "sh", line]);
    }

    function remove(line: string): void {
        entries = entries.filter(e => e.line !== line);
        const id = line.slice(0, line.indexOf("\t"));
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist delete; rm -f \"$2/$3.png\"", "sh", line, thumbDir, id]);
    }

    // "[[ binary data 120 KiB png 1920x1080 ]]" -> "PNG · 1920×1080 · 120 KiB"
    function parse(line: string): var {
        const tab = line.indexOf("\t");
        const id = tab >= 0 ? line.slice(0, tab) : line;
        const preview = tab >= 0 ? line.slice(tab + 1) : "";
        const m = preview.match(/^\[\[ binary data (.+?) (\w+) (\d+x\d+) \]\]$/);
        if (m)
            return {
                line,
                id,
                image: true,
                text: "Image",
                info: `${m[2].toUpperCase()} · ${m[3].replace("x", "×")} · ${m[1]}`
            };
        return {
            line,
            id,
            image: false,
            text: preview,
            info: ""
        };
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v cliphist >/dev/null"]
        onExited: code => root.available = code === 0
    }

    // The recorder; started again if it stops (Wayland hiccup, cliphist update).
    Process {
        id: recorder

        running: root.available
        // One recorder: the one of a previous kirin (restarted, crashed)
        // keeps running otherwise. Its pid is kept in a file, and only that
        // process is stopped, if it still is wl-paste.
        command: ["sh", "-c", "f=\"${XDG_RUNTIME_DIR:-/tmp}/kirin-cliphist.pid\"; p=$(cat \"$f\" 2>/dev/null); [ -n \"$p\" ] && grep -qa wl-paste /proc/$p/cmdline 2>/dev/null && kill $p; echo $$ > \"$f\"; exec wl-paste --watch cliphist store"]
        onExited: restart.start()
    }

    Timer {
        id: restart

        interval: 3000
        onTriggered: recorder.running = root.available
    }

    Process {
        id: lister

        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = text.split("\n").filter(l => l).map(l => root.parse(l));
                root.loading = false;
                // Thumbnails for the newest images.
                thumbnailer.queue = root.entries.filter(e => e.image && !root.thumbs[e.id]).slice(0, 30).map(e => e.line);
                thumbnailer.next();
            }
        }
    }

    // Decodes image entries to files, one at a time, for the launcher's rows.
    Process {
        id: thumbnailer

        property var queue: []
        property string current: ""

        function next(): void {
            if (running || queue.length === 0)
                return;
            current = queue[0];
            queue = queue.slice(1);
            const id = current.slice(0, current.indexOf("\t"));
            command = ["sh", "-c", "mkdir -p \"$2\" && f=\"$2/$3.png\" && { [ -s \"$f\" ] || printf '%s' \"$1\" | cliphist decode | magick - -thumbnail '160x160>' \"$f\"; } && echo \"$f\"", "sh", current, root.thumbDir, id];
            running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                const file = text.trim();
                if (file) {
                    const id = thumbnailer.current.slice(0, thumbnailer.current.indexOf("\t"));
                    const t = Object.assign({}, root.thumbs);
                    t[id] = file;
                    root.thumbs = t;
                }
            }
        }
        onExited: Qt.callLater(next)
    }
}
