import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Search backend for the launcher. Apps and system commands are matched with
// fzf against an index file, files with fzf against a list made by fd.
// `results` is a flat list; section headers are items of kind "header".
Item {
    id: root

    property string query
    property var results: []

    readonly property string cacheDir: `${Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"}/kirin`
    readonly property string indexPath: `${cacheDir}/launcher-index.tsv`
    readonly property string filesPath: `${cacheDir}/launcher-files.txt`
    readonly property string home: Quickshell.env("HOME")

    property bool indexReady: false
    property bool filesReady: false

    // DesktopEntry by id, filled together with the index.
    property var apps: ({})
    // Raw fzf hits for the current query.
    property var appHits: []
    property var fileHits: []

    readonly property var engines: ({
            google: "https://www.google.com/search?q=%s",
            duckduckgo: "https://duckduckgo.com/?q=%s"
        })

    // Typed as "/name": switch the launcher into another mode.
    readonly property var slashCommands: [
        {
            name: "wallpaper",
            description: "Choose a wallpaper",
            icon: "wallpaper"
        },
        {
            name: "clipboard",
            description: "Clipboard history",
            icon: "content_paste"
        }
    ]

    // "/clipboard [filter]": the clipboard history instead of search results.
    readonly property bool clipboardMode: /^\/clipboard(\s|$)/.test(query.trim() + " ")
    onClipboardModeChanged: {
        if (clipboardMode)
            Clipboard.refresh();
    }

    Connections {
        target: Clipboard

        function onEntriesChanged(): void {
            if (root.clipboardMode)
                root.rebuild();
        }

        function onThumbsChanged(): void {
            if (root.clipboardMode)
                root.rebuild();
        }

        function onAvailableChanged(): void {
            if (root.clipboardMode)
                root.rebuild();
        }
    }

    // Kirin's own apps (desktop entries): listed with the system commands.
    readonly property var systemApps: ["kirin-settings"]

    // Commands of their own (none now: logging out, sleep and power are in
    // the bar's power menu). { id, name, keywords, icon, command }.
    readonly property var commands: []

    onQueryChanged: debounce.restart()
    onAppHitsChanged: rebuild()
    onFileHitsChanged: rebuild()
    onIndexReadyChanged: run()
    onFilesReadyChanged: run()

    Component.onCompleted: mkdir.running = true

    Timer {
        id: debounce

        interval: 40
        onTriggered: root.run()
    }

    // --- Indexing -----------------------------------------------------------

    function clean(text: string): string {
        return (text ?? "").replace(/[\t\n]/g, " ");
    }

    function buildIndex(): void {
        const map = {};
        const lines = [];
        for (const entry of DesktopEntries.applications.values) {
            if (entry.noDisplay)
                continue;
            map[entry.id] = entry;
            lines.push([`app:${entry.id}`, entry.name, entry.genericName, (entry.keywords ?? []).join(" ")].map(clean).join("\t"));
        }
        for (const cmd of commands)
            lines.push([`cmd:${cmd.id}`, cmd.name, "", cmd.keywords].join("\t"));

        apps = map;
        const content = lines.join("\n") + "\n";
        // FileView skips writing unchanged content, and then never emits saved().
        if (indexFile.text() === content) {
            indexReady = true;
            run();
        } else {
            indexFile.setText(content);
        }
        if (!query.trim())
            rebuild();
    }

    // Desktop entries load asynchronously; keep the index in sync with them.
    Connections {
        target: DesktopEntries.applications

        function onValuesChanged(): void {
            if (!mkdir.running)
                root.buildIndex();
        }
    }

    Process {
        id: mkdir

        command: ["mkdir", "-p", root.cacheDir]
        onExited: {
            root.buildIndex();
            if (Config.launcher.files)
                fd.running = true;
        }
    }

    FileView {
        id: indexFile

        path: root.indexPath
        printErrors: false
        onSaved: {
            root.indexReady = true;
            root.run();
        }
    }

    // Lists files and folders in $HOME, respecting .gitignore and skipping hidden ones.
    Process {
        id: fd

        command: ["sh", "-c", 'fd . "$HOME" --type f --type d --exclude node_modules > "$1.tmp" && mv "$1.tmp" "$1"', "sh", root.filesPath]
        onExited: root.filesReady = true
    }

    // --- Querying -----------------------------------------------------------

    // A Process can't be restarted while it runs, so the newest request waits
    // for the current one to exit (see onRunningChanged below).
    function restart(proc: var, command: var): void {
        proc.pending = {
            command,
            query
        };
        if (!proc.running)
            start(proc);
    }

    function start(proc: var): void {
        proc.forQuery = proc.pending.query;
        proc.command = proc.pending.command;
        proc.pending = null;
        proc.running = true;
    }

    function run(): void {
        const q = query.trim();
        if (!q || q.startsWith("/")) {
            appHits = [];
            fileHits = [];
            return;
        }
        if (indexReady)
            restart(appSearch, ["sh", "-c", 'fzf --filter "$1" --delimiter "\t" --nth 2.. < "$2" | head -n 40', "sh", q, indexPath]);
        if (filesReady && Config.launcher.files)
            restart(fileSearch, ["sh", "-c", 'fzf --filter "$1" --scheme=path < "$2" | head -n 30', "sh", q, filesPath]);
    }

    Process {
        id: appSearch

        property string forQuery
        property var pending: null

        onRunningChanged: {
            if (!running && pending)
                root.start(this);
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (appSearch.forQuery === root.query && !appSearch.pending)
                    root.appHits = text.split("\n").filter(l => l).map(l => l.split("\t")[0]);
            }
        }
    }

    Process {
        id: fileSearch

        property string forQuery
        property var pending: null

        onRunningChanged: {
            if (!running && pending)
                root.start(this);
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (fileSearch.forQuery === root.query && !fileSearch.pending)
                    root.fileHits = text.split("\n").filter(l => l);
            }
        }
    }

    // --- Usage --------------------------------------------------------------

    // Launch counts per app id; frequent apps rank higher and fill the empty state.
    property var usage: {
        try {
            return JSON.parse(usageFile.text()).apps ?? {};
        } catch (e) {
            return {};
        }
    }

    FileView {
        id: usageFile

        path: `${Wallpaper.stateDir}/launcher.json`
        printErrors: false
    }

    function recordUse(id: string): void {
        const apps = Object.assign({}, usage);
        apps[id] = (apps[id] ?? 0) + 1;
        usageFile.setText(JSON.stringify({ apps }, null, 2) + "\n");
    }

    // --- Results ------------------------------------------------------------

    function calculate(q: string): string {
        if (!/^[\d\s+\-*/().,%^]+$/.test(q) || !/\d/.test(q) || !/[+\-*/%^]/.test(q))
            return "";
        try {
            const value = Function(`"use strict"; return (${q.replace(/\^/g, "**").replace(/,/g, ".")});`)();
            if (typeof value !== "number" || !isFinite(value))
                return "";
            return String(Number(value.toPrecision(12)));
        } catch (e) {
            return "";
        }
    }

    function appItem(entry: var): var {
        return {
            kind: "app",
            id: entry.id,
            title: entry.name,
            subtitle: entry.genericName || entry.comment || "Application",
            appIcon: entry.icon
        };
    }

    function shortPath(path: string): string {
        return path.startsWith(home) ? "~" + path.slice(home.length) : path;
    }

    function rebuild(): void {
        const q = query.trim();
        const out = [];
        const header = title => out.push({
                kind: "header",
                title
            });

        if (!q) {
            const frequent = Object.entries(usage).sort((a, b) => b[1] - a[1]).map(([id]) => apps[id]).filter(e => e).slice(0, 8);
            if (frequent.length) {
                header("Frequently Used");
                frequent.forEach(e => out.push(appItem(e)));
            }
            results = out;
            return;
        }

        if (clipboardMode) {
            const filter = q.replace(/^\/clipboard\s*/, "").toLowerCase();
            if (!Clipboard.available) {
                header("cliphist isn't installed");
            } else {
                const hits = Clipboard.entries.filter(e => !filter || e.text.toLowerCase().includes(filter) || e.info.toLowerCase().includes(filter));
                header(hits.length ? "Clipboard  ·  Enter to copy, Delete to remove" : Clipboard.loading ? "Loading…" : filter ? "Nothing found" : "Clipboard is empty");
                hits.slice(0, 100).forEach(e => out.push({
                            kind: "clip",
                            line: e.line,
                            // One line of text: newlines and runs of spaces collapsed.
                            title: e.image ? "Image" : e.text.replace(/\s+/g, " ").trim() || "(whitespace)",
                            subtitle: e.image ? e.info : `${e.text.length} characters`,
                            icon: e.image ? "image" : "notes",
                            thumb: e.image ? (Clipboard.thumbs[e.id] ?? "") : ""
                        }));
            }
            results = out;
            return;
        }

        if (q.startsWith("/")) {
            const name = q.slice(1).split(" ")[0].toLowerCase();
            const matches = slashCommands.filter(c => c.name.startsWith(name));
            if (matches.length) {
                header("Commands");
                matches.forEach(c => out.push({
                            kind: "slash",
                            title: `/${c.name}`,
                            subtitle: c.description,
                            icon: c.icon,
                            insert: `/${c.name} `
                        }));
            }
            results = out;
            return;
        }

        const calc = calculate(q);
        if (calc) {
            header("Calculator");
            out.push({
                kind: "calc",
                title: calc,
                subtitle: `${q} =  ·  Enter to copy`,
                icon: "calculate"
            });
        }

        // fzf rank, nudged by how often the app is launched.
        const ranked = appHits.map((key, rank) => ({
                    key,
                    score: rank - Math.min(usage[key.slice(4)] ?? 0, 10) * 0.5
                })).sort((a, b) => a.score - b.score);

        const appItems = [];
        const cmdItems = [];
        for (const {
            key
        } of ranked) {
            const id = key.slice(4);
            if (key.startsWith("app:") && apps[id] && systemApps.includes(id)) {
                // Kirin's own apps go with the system commands.
                const e = apps[id];
                cmdItems.push(Object.assign(appItem(e), {
                    subtitle: "System",
                    match: [e.name, e.genericName, (e.keywords ?? []).join(" ")].join(" ")
                }));
            } else if (key.startsWith("app:") && apps[id])
                appItems.push(appItem(apps[id]));
            else if (key.startsWith("cmd:")) {
                const cmd = commands.find(c => c.id === id);
                if (cmd)
                    cmdItems.push({
                        kind: "cmd",
                        id,
                        title: cmd.name,
                        subtitle: "System",
                        icon: cmd.icon,
                        match: `${cmd.name} ${cmd.keywords}`
                    });
            }
        }

        // Kirin's own commands come first when they plainly match: the name
        // has the query in it, or a word of it or of its keywords starts with
        // it ("settings" finds Kirin Settings before apps with settings in
        // them). Fuzzy matches only ("te" in "quiT sEssion") stay after the
        // apps, or "te" for Telegram would offer to log out first.
        const ql = q.toLowerCase();
        const plain = item => {
            if (item.title.toLowerCase().includes(ql))
                return true;
            return (item.match ?? "").toLowerCase().split(/\s+/).some(w => w.startsWith(ql));
        };
        const systemFirst = cmdItems.some(plain);
        if (systemFirst)
            cmdItems.sort((a, b) => (plain(b) ? 1 : 0) - (plain(a) ? 1 : 0));

        // Spotlight-style top hit: the best plain command, else the best app,
        // else the best command.
        const top = systemFirst ? cmdItems.shift() : appItems.length ? appItems.shift() : cmdItems.shift();
        if (top) {
            header("Top Hit");
            out.push(top);
        }
        const systemSection = () => {
            if (cmdItems.length) {
                header("System");
                cmdItems.slice(0, 3).forEach(i => out.push(i));
            }
        };
        if (systemFirst)
            systemSection();
        if (appItems.length) {
            header("Applications");
            appItems.slice(0, 6).forEach(i => out.push(i));
        }
        if (!systemFirst)
            systemSection();

        if (Config.launcher.files && fileHits.length) {
            header("Files");
            for (const path of fileHits.slice(0, 8)) {
                const isDir = path.endsWith("/");
                const clean = isDir ? path.slice(0, -1) : path;
                const slash = clean.lastIndexOf("/");
                out.push({
                    kind: "file",
                    path: clean,
                    title: clean.slice(slash + 1),
                    subtitle: shortPath(clean.slice(0, slash)) || "/",
                    icon: isDir ? "folder" : "description"
                });
            }
        }

        const engine = engines[Config.launcher.webSearch];
        if (engine) {
            header("Web");
            out.push({
                kind: "web",
                title: `Search the web for “${q}”`,
                subtitle: Config.launcher.webSearch === "google" ? "Google" : "DuckDuckGo",
                icon: "travel_explore",
                url: engine.replace("%s", encodeURIComponent(q))
            });
        }

        results = out;
    }

    // Runs a result. `alt` (Ctrl+Enter) shows a file in its folder instead.
    function activate(item: var, alt: bool): void {
        switch (item.kind) {
        case "app":
            recordUse(item.id);
            Apps.launch(apps[item.id]);
            break;
        case "cmd":
            Apps.run(commands.find(c => c.id === item.id).command, "");
            break;
        case "file":
            Apps.open(alt ? item.path.slice(0, item.path.lastIndexOf("/")) || "/" : item.path);
            break;
        case "calc":
            Quickshell.execDetached(["wl-copy", item.title]);
            break;
        case "clip":
            Clipboard.copy(item.line);
            break;
        case "web":
            Apps.open(item.url);
            break;
        }
    }
}
