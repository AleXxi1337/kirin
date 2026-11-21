pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower

// Current wallpaper. The path lives in a state file so it survives restarts
// and can be changed from outside: `qs -c kirin ipc call wallpaper set <path>`.
Singleton {
    id: root

    readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/kirin`
    readonly property string saved: state.text().trim()

    // The saved wallpaper.
    property string current
    // A wallpaper being tried out (launcher picker); not saved. Empty when none.
    property string preview
    // What the desktop shows and the colours follow: the preview, else the saved one.
    property string displayed

    // Where the next transition circle starts, as a fraction of the desktop.
    // Picked before `displayed` changes so every monitor reveals from the same point.
    property point revealPoint: Qt.point(0.5, 0.5)

    onSavedChanged: current = saved
    onCurrentChanged: {
        prepare([current]);
        shrink(current, true);
        // A committed preview: it's saved now, nothing left to preview.
        if (preview === current)
            preview = "";
        refresh();
    }
    onPreviewChanged: refresh()
    Component.onCompleted: {
        current = saved;
        displayed = current;
        takeSlot(displayed);
    }

    // Tried out in the picker: only whether a copy is there already; none is
    // made for every video looked at (the original plays).
    onDisplayedChanged: {
        cleanupTimer.restart();
        takeSlot(displayed);
        // Its picture (a video's first frame), however it got here: the
        // slide showing it waits for that.
        prepare([displayed]);
        shrink(displayed, false);
        // A new video starts at its beginning.
        timelineStart = Date.now();
        timelineHeld = 0;
    }

    function refresh(): void {
        const next = preview || current;
        if (next === displayed)
            return;
        revealPoint = Qt.point(Math.random(), Math.random());
        displayed = next;
    }

    // Replays the transition onto the current wallpaper (preview in settings).
    signal replayRequested

    function replay(): void {
        revealPoint = Qt.point(Math.random(), Math.random());
        replayRequested();
    }

    // Bounding box of all monitors in the global layout. The wallpaper is
    // stretched over it and each monitor shows its own part.
    readonly property rect desktop: {
        const screens = Quickshell.screens;
        if (screens.length === 0)
            return Qt.rect(0, 0, 0, 0);
        let x1 = Infinity, y1 = Infinity, x2 = -Infinity, y2 = -Infinity;
        for (const s of screens) {
            x1 = Math.min(x1, s.x);
            y1 = Math.min(y1, s.y);
            x2 = Math.max(x2, s.x + s.width);
            y2 = Math.max(y2, s.y + s.height);
        }
        return Qt.rect(x1, y1, x2 - x1, y2 - y1);
    }

    // Wallpapers are drawn from a copy cached at the size the screens need
    // (a high quality JPEG): decoding a big original took over a second
    // before each transition could start. Made in the background, for the
    // current wallpaper and for all of them while the picker is open; until
    // a copy is there the original is used.
    // kirin's scripts (scripts/ next to shell.qml; `kirin` the CLI runs
    // some of them too).
    function script(name: string): string {
        return `${Quickshell.shellDir}/scripts/${name}`;
    }

    readonly property string scaledDir: `${Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"}/kirin/wallpapers`
    // Device pixels the largest slide covers ("WxH").
    readonly property string renderSize: {
        let w = 0, h = 0;
        for (const s of Quickshell.screens) {
            const dpr = s.devicePixelRatio || 1;
            w = Math.max(w, (Config.wallpaper.span ? desktop.width : s.width) * dpr);
            h = Math.max(h, (Config.wallpaper.span ? desktop.height : s.height) * dpr);
        }
        return `${Math.ceil(w)}x${Math.ceil(h)}`;
    }
    // Image path -> its cached copy, and the size it was made at. A copy at
    // an older size stays in use until the new one is there: nothing goes
    // blank while monitors come and go.
    property var scaled: ({})
    property var scaledSizes: ({})

    // A monitor plugged in changes the size a few times in a row: copies
    // for the size it settles at.
    onRenderSizeChanged: {
        sizeSettled.restart();
    }

    Timer {
        id: sizeSettled

        interval: 500
        onTriggered: {
            root.rememberSize(root.renderSize);
            root.prepare([root.current, root.displayed]);
            cleanupTimer.restart();
        }
    }

    // --- Video wallpapers ------------------------------------------------------
    // A video (mp4, webm, …) plays on the desktop (modules/background); what
    // needs a picture (the colours, the picker, the lock screen, the moment
    // before it plays) gets its first frame, made at the screens' size like
    // the copies of images.
    //
    // Shrinking (Settings → Wallpaper → Animated wallpapers): the video picked
    // is copied once to a smaller size and frame rate (H.264, decoded in
    // hardware), for the battery; until the copy is there the original
    // plays. The size is the smallest of:
    //   - what covers the screens (the canvas they span, or the largest one):
    //     more is cropped away and never seen;
    //   - the picked resolution's number of pixels (HD 0.9 MP, Full HD 2.1,
    //     2K 3.7, 4K 8.3), whatever the video's shape: a 4:3 or 21:9 video
    //     costs as much to play as a 16:9 one of that resolution;
    //   - the video's own size (never enlarged).
    // The shape never changes. The frame rate is only ever lowered.

    function isVideo(path: string): bool {
        return /\.(mp4|m4v|webm|mkv|mov)$/i.test(path ?? "");
    }

    // A picture of this wallpaper: the image itself, or a video's first
    // frame once it's made ("" until then).
    function imageFor(path: string): string {
        return isVideo(path) ? scaled[path] ?? "" : path;
    }

    readonly property var video: Config.wallpaper.video
    readonly property bool shrinking: video.shrink
    readonly property var resolutions: ({
            hd: 1280 * 720,
            fhd: 1920 * 1080,
            qhd: 2560 * 1440,
            uhd: 3840 * 2160
        })
    readonly property int maxPixels: resolutions[video.resolution] ?? resolutions.fhd
    readonly property int maxFps: Math.max(1, video.fps)
    // What a copy depends on; a change makes new copies.
    readonly property string copyParams: `${renderSize}-${video.resolution}-${maxFps}`

    // The video to play: the copy if there is one; "" until it's known
    // whether there is one (quick, unless a copy is being made for the first
    // time: then the original plays meanwhile), so playback doesn't start on
    // the original only to restart on the copy.
    function videoFor(path: string): string {
        if (!shrinking)
            return path;
        return videos[path] ?? (decided[path] ? path : "");
    }

    // --- When videos play -----------------------------------------------------
    // Always, no setting:
    //   - a monitor with a fullscreen window (a game, covering even the bar)
    //     pauses its video;
    //   - on a laptop, the power profile decides the rest: performance plays;
    //     balanced pauses once every monitor is covered by windows (while
    //     one is free, all play, in step); power saver pauses.
    // A computer without a battery plays otherwise.

    // Per monitor name, on the workspace it shows: 0 the wallpaper is seen;
    // 1 covered, the bar aside (a tiled window: tiled ones fill the screen
    // together, gaps aside; a maximized one; or a floating one over most of
    // the screen); 2 a fullscreen window, over the bar too.
    readonly property var coverage: {
        const out = {};
        for (const m of Hyprland.monitors.values) {
            const area = (m.width / (m.scale || 1)) * (m.height / (m.scale || 1));
            out[m.name] = (m.activeWorkspace?.toplevels.values ?? []).reduce((level, t) => {
                const w = t.lastIpcObject;
                if (!w)
                    return level;
                if ((w.fullscreen ?? 0) >= 2)
                    return 2;
                const size = w.size ?? [0, 0];
                const covers = !w.floating || (w.fullscreen ?? 0) >= 1 || size[0] * size[1] >= area * 0.8;
                return Math.max(level, covers ? 1 : 0);
            }, 0);
        }
        return out;
    }

    readonly property bool videosAllowed: {
        if (!Power.hasBattery)
            return true;
        const profile = Power.profile;
        if (profile === PowerProfile.PowerSaver)
            return false;
        if (profile === PowerProfile.Balanced) {
            const levels = Object.values(coverage);
            return levels.length === 0 || levels.some(level => level < 1);
        }
        return true;
    }

    function videoPlaying(screen: var): bool {
        return videosAllowed && (coverage[screen?.name ?? ""] ?? 0) < 2;
    }

    // --- One player for every monitor ----------------------------------------
    // With the Kirin.Video module (kirin-plugins/video) the video is decoded
    // once and each monitor shows the same frames (SharedPlayer,
    // SharedVideoLayer). Without it, each monitor plays it itself on the
    // shared timeline below (VideoLayer).

    //
    // Two players take turns, so the video being replaced keeps playing
    // until the new wallpaper has covered it (both decode only meanwhile):
    // the new video goes to the free one (or the one not shown), and once
    // the change is over (Background calls transitionDone) the other stops.

    // The video in each player ("" none), and the one shown (-1: a picture).
    property var slots: ["", ""]
    property int slot: -1

    function takeSlot(path: string): void {
        if (!isVideo(path)) {
            slot = -1;
            return;
        }
        let i = slots.indexOf(path);
        if (i < 0) {
            i = slots.indexOf("");
            if (i < 0)
                i = slot === 0 ? 1 : 0;
            const next = slots.slice();
            next[i] = path;
            slots = next;
        }
        slot = i;
    }

    // The new wallpaper covers the old one everywhere: only its player stays.
    function transitionDone(): void {
        if (slots.some((p, i) => p && i !== slot))
            slots = slots.map((p, i) => i === slot ? p : "");
    }

    Loader {
        id: sharedLoader

        source: Qt.resolvedUrl("../modules/background/SharedPlayer.qml")
    }

    // Kirin.Video is there.
    readonly property bool sharedPlayers: sharedLoader.item !== null

    // The player playing this video, if any.
    function playerFor(path: string): var {
        const i = slots.indexOf(path);
        return i < 0 || !path ? null : sharedLoader.item?.players[i] ?? null;
    }

    // --- One timeline for every monitor (without Kirin.Video) ----------------
    // Each monitor plays the video itself (Qt can't hand one player's frames
    // to several windows from QML), so they're kept on a shared clock: where
    // the video should be now. It runs while the video plays anywhere and
    // stands still while it's paused everywhere. Players steer towards it
    // (VideoLayer.qml): slightly faster or slower to catch up, a jump only
    // when coming back from a pause of their own.

    // Paused on every monitor.
    readonly property bool videoStill: !videosAllowed || Quickshell.screens.every(s => (coverage[s.name] ?? 0) >= 2)

    // Wall-clock time the video's timeline started at; while still, how far
    // it had got.
    property real timelineStart: Date.now()
    property real timelineHeld: 0

    onVideoStillChanged: {
        if (videoStill)
            timelineHeld = Date.now() - timelineStart;
        else
            timelineStart = Date.now() - timelineHeld;
    }

    // Where a video of this length (ms) should be now, in ms.
    function videoTime(duration: real): real {
        if (duration <= 0)
            return 0;
        const elapsed = videoStill ? timelineHeld : Date.now() - timelineStart;
        return elapsed % duration;
    }

    // Window states come with the client list, read again when they change.
    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (["fullscreen", "openwindow", "closewindow", "movewindowv2", "changefloatingmode"].includes(event.name))
                Hyprland.refreshToplevels();
        }
    }

    // Floating windows resized from Lua (kirin's maximize, halves), which
    // Hyprland sends no event for: hypr/modules/winmode.lua calls this.
    IpcHandler {
        target: "windows"

        function changed(): void {
            Hyprland.refreshToplevels();
        }
    }

    // Video path -> its copy.
    property var videos: ({})
    // Videos whose copy is known: made, not needed, being made, or not to
    // be made (only looked at in the picker).
    property var decided: ({})
    // Videos a copy has been made for, or tried.
    property var copied: ({})
    // Video path -> { width, height, fps, copyWidth, copyHeight, copyFps }
    // (copy* the same as the original's when no copy is needed).
    property var videoInfo: ({})
    // The video a copy is being made of right now ("" when none).
    property string making: ""

    // Settled a moment after the last change (the frame rate slider moves
    // in steps): only then copies are made anew. A copy being made with the
    // old settings is stopped.
    onCopyParamsChanged: {
        restartTimer.restart();
        cleanupTimer.restart();
    }
    onShrinkingChanged: restartShrinking()

    Timer {
        id: restartTimer

        interval: 1200
        onTriggered: root.restartShrinking()
    }

    // New settings or size: copies are worked out again. What plays now keeps
    // playing (an older copy, or the original) until the new answer is in;
    // only turning shrinking off drops the copies at once.
    function restartShrinking(): void {
        if (!shrinking) {
            videos = {};
            decided = {};
        }
        copied = {};
        shrinker.queue = [];
        if (shrinker.running)
            shrinker.signal(15);
        videoInfo = {};
        shrink(current, true);
        if (displayed !== current)
            shrink(displayed, false);
    }

    // Works out which file a video plays from; with `copy`, makes the copy
    // if it needs one.
    function shrink(path: string, copy: bool): void {
        if (!shrinking || !isVideo(path) || renderSize === "0x0")
            return;
        if (copy ? copied[path] : decided[path])
            return;
        if (shrinker.queue.some(e => e.path === path && (e.copy || !copy)))
            return;
        if (copy)
            copied = Object.assign({}, copied, { [path]: true });
        shrinker.queue = shrinker.queue.concat([{ path, copy }]);
        shrinker.next();
    }

    Process {
        id: shrinker

        property var queue: []
        property string current
        // The settings this run is for.
        property string params

        function next(): void {
            if (running || !queue.length || !root.shrinking)
                return;
            const entry = queue[0];
            queue = queue.slice(1);
            current = entry.path;
            params = root.copyParams;
            const target = `${root.scaledDir}/${Qt.md5(current)}-${root.copyParams}.mp4`;
            byCopy[target] = {
                path: current,
                params
            };
            // Lines are tab-separated, starting with a word and the copy's
            // path (each line names its own file: by the time it's read
            // the next video may be running):
            //   info <copy> w h fps copyW copyH copyFps
            //   ok <copy>: the copy is there; orig <copy>: none needed;
            //   busy <copy>: being made (then ok); skip <copy>: needed, but
            //   not to be made now (only looked at).
            command = ["sh", root.script("wallpaper-shrink.sh"), current, target, root.renderSize, String(root.maxPixels), String(root.maxFps), entry.copy ? "1" : "0"];
            running = true;
        }

        // Copy path -> { video path, settings }, for the lines (see next()).
        property var byCopy: ({})

        stdout: SplitParser {
            onRead: line => {
                const [word, copy, ...rest] = line.split("\t");
                const run = shrinker.byCopy[copy];
                // A run for older settings: its news is no longer wanted.
                if (!run || run.params !== root.copyParams)
                    return;
                const path = run.path;
                if (word === "info") {
                    const [w, h, fps, cw, ch, cf] = rest.map(Number);
                    root.videoInfo = Object.assign({}, root.videoInfo, {
                        [path]: {
                            width: w,
                            height: h,
                            fps,
                            copyWidth: cw,
                            copyHeight: ch,
                            copyFps: cf
                        }
                    });
                    return;
                }
                if (word === "busy")
                    root.making = path;
                if (word === "ok")
                    root.videos = Object.assign({}, root.videos, { [path]: copy });
                // No copy needed (any more): the original.
                if (word === "orig" && root.videos[path]) {
                    const next = Object.assign({}, root.videos);
                    delete next[path];
                    root.videos = next;
                }
                if (!root.decided[path])
                    root.decided = Object.assign({}, root.decided, { [path]: true });
            }
        }

        onExited: {
            root.making = "";
            // Failed or not: play what there is (unless the settings have
            // changed since, and it was stopped for that).
            if (params === root.copyParams && !root.decided[current])
                root.decided = Object.assign({}, root.decided, { [current]: true });
            Qt.callLater(next);
        }
    }

    // The file to draw for this wallpaper (a picture: a video's first frame).
    function fileFor(path: string): string {
        return scaled[path] ?? path;
    }

    function prepare(paths: var): void {
        // Not made at this size yet, nor being made (`current` stays set
        // after a run: only a running one counts).
        const missing = paths.filter((p, i) => p && paths.indexOf(p) === i && scaledSizes[p] !== renderSize && !scaler.queue.includes(p) && !(scaler.running && scaler.current === p && scaler.size === renderSize));
        if (!missing.length || renderSize === "0x0")
            return;
        scaler.queue = scaler.queue.concat(missing);
        scaler.next();
    }

    Process {
        id: scaler

        property var queue: []
        property string current
        property string target
        // The size this run makes.
        property string size

        function next(): void {
            if (running || !queue.length)
                return;
            current = queue[0];
            queue = queue.slice(1);
            size = root.renderSize;
            // Made meanwhile (the size went back and forth).
            if (root.scaledSizes[current] === size) {
                Qt.callLater(next);
                return;
            }
            target = `${root.scaledDir}/${Qt.md5(current)}-${root.renderSize}.jpg`;
            // A video: its first frame, covering the size.
            command = ["sh", root.script("wallpaper-scale.sh"), current, target, root.renderSize];
            running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "ok") {
                    root.scaled = Object.assign({}, root.scaled, { [scaler.current]: scaler.target });
                    root.scaledSizes = Object.assign({}, root.scaledSizes, { [scaler.current]: scaler.size });
                }
                Qt.callLater(scaler.next);
            }
        }
    }

    function set(path: string): void {
        pending = path;
        mkdir.running = true;
    }

    property string pending

    // The state dir may not exist yet; write only after it has been created.
    Process {
        id: mkdir

        command: ["mkdir", "-p", root.stateDir]
        onExited: state.setText(root.pending + "\n")
    }

    FileView {
        id: state

        path: `${root.stateDir}/wallpaper`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    // --- Cache cleanup -----------------------------------------------------------
    // The copies (scaledDir) and the picker's thumbnails pile up: wallpapers
    // removed, canvases no longer used, videos shrunk with other settings.
    // Kept:
    //   - for wallpapers still in the folder (and the current and shown ones),
    //   - pictures at the canvas sizes of the last few monitor setups (so
    //     plugging the TV back in is instant),
    //   - shrunk videos at those sizes, made with the current settings.
    // The rest goes. Copies that came out the same (an original smaller than
    // every canvas isn't enlarged) become hard links to one file. Run a while
    // after starting and after anything that changes what's needed.

    // Canvas sizes of the recent monitor setups, newest first.
    readonly property int keptSizes: 3
    readonly property string thumbDir: `${Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"}/kirin/wallpaper-thumbs-960x540`

    FileView {
        id: sizesFile

        path: `${root.stateDir}/canvas-sizes`
        printErrors: false
    }

    readonly property var recentSizes: sizesFile.text().split("\n").filter(s => /^\d+x\d+$/.test(s))

    function rememberSize(size: string): void {
        if (!/^\d+x\d+$/.test(size) || size === "0x0" || recentSizes[0] === size)
            return;
        const list = [size, ...recentSizes.filter(s => s !== size)].slice(0, keptSizes);
        sizesFile.setText(list.join("\n") + "\n");
    }


    Timer {
        id: cleanupTimer

        running: true
        interval: 30000
        onTriggered: {
            if (cleaner.running) {
                restart();
                return;
            }
            // Sizes still showing (an older copy until the new one is there) too.
            const sizes = [root.renderSize, ...root.recentSizes, ...Object.values(root.scaledSizes)].filter((s, i, a) => /^\d+x\d+$/.test(s) && a.indexOf(s) === i);
            cleaner.command = ["sh", root.script("wallpaper-gc.sh"), root.scaledDir, root.thumbDir, Config.wallpaper.directory.replace(/^~(?=\/|$)/, Quickshell.env("HOME")), sizes.join(" "), `${root.video.resolution}-${root.maxFps}`, root.current, root.displayed];
            cleaner.running = true;
        }
    }


    Process {
        id: cleaner

        stdout: StdioCollector {
            onStreamFinished: {
                const [freed, linked] = text.trim().split(" ").map(Number);
                const mb = ((freed || 0) + (linked || 0)) / 1048576;
                if (mb >= 1)
                    console.info(`kirin: wallpaper cache: ${mb.toFixed(0)} MB freed`);
            }
        }
    }

    IpcHandler {
        target: "wallpaper"

        function get(): string {
            return root.current;
        }

        function set(path: string): void {
            root.set(path);
        }
    }
}
