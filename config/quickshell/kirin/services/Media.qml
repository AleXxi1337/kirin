pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// What's playing, from any MPRIS player (Spotify, browsers, mpv, …), for
// the media card (modules/media). The player shown: one that's playing,
// Spotify first; else the one that played last. Media keys come here too
// (hypr/modules/keybindings.lua), and so does the card's "show yourself".
Singleton {
    id: root

    readonly property var players: Mpris.players.values
    // The one that played last, for when none is playing.
    property MprisPlayer lastPlaying: null

    readonly property MprisPlayer player: {
        const playing = players.filter(p => p.isPlaying);
        const pick = playing.find(p => isSpotify(p)) ?? playing[0];
        if (pick)
            return pick;
        if (lastPlaying && players.includes(lastPlaying))
            return lastPlaying;
        return players.find(p => isSpotify(p)) ?? players[0] ?? null;
    }

    onPlayerChanged: {
        if (player?.isPlaying)
            lastPlaying = player;
    }

    Connections {
        target: root.player

        function onIsPlayingChanged(): void {
            if (root.player.isPlaying)
                root.lastPlaying = root.player;
        }
    }

    readonly property bool hasTrack: !!player && (player.trackTitle ?? "") !== ""
    readonly property bool playing: player?.isPlaying ?? false
    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""
    readonly property string art: player?.trackArtUrl ?? ""
    // Seconds.
    readonly property real length: player?.lengthSupported ? player.length : 0
    readonly property real position: player?.positionSupported ? player.position : 0

    // Where it comes from, for the card's badge: Spotify, a browser, or
    // neither (no badge).
    function isSpotify(p: var): bool {
        return /spotify/i.test(`${p?.desktopEntry ?? ""} ${p?.identity ?? ""}`);
    }

    function isBrowser(p: var): bool {
        return /firefox|librewolf|zen|chrom|brave|vivaldi|opera|edge|epiphany|falkon/i.test(`${p?.desktopEntry ?? ""} ${p?.identity ?? ""}`);
    }

    readonly property string source: isSpotify(player) ? "spotify" : isBrowser(player) ? "browser" : ""
    // The app's id, for its symbol (SymbolIcon).
    readonly property string sourceApp: player?.desktopEntry || (player?.identity ?? "").toLowerCase()

    // MPRIS sends the position only on seeks: asked again while playing.
    Timer {
        running: root.playing && (root.player?.positionSupported ?? false)
        interval: 500
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    // The card shows itself for a while (the song changed, a media key,
    // the song about to end).
    signal flash

    // The song about to end (3 s left): the card comes to see the change.
    property bool endShown: false
    // The position a moment ago.
    property real lastPosition: 0

    // Only as the song really plays into its last 3 s: before, more were
    // left; it moved on a little (not a jump); and it's within the song.
    // Players sometimes report a position past the end (stale, while the
    // window comes into focus, say), which read as the song ending.
    onPositionChanged: {
        const was = lastPosition;
        lastPosition = position;
        if (endShown || !playing || length <= 0)
            return;
        const left = length - position;
        if (left >= 0 && left <= 3 && length - was > 3 && position - was >= 0 && position - was < 2) {
            endShown = true;
            flash();
        }
    }

    // A new song: the card shows it. Not for the songs already there when
    // kirin starts.
    readonly property string trackKey: hasTrack ? `${title}\n${artist}` : ""
    property bool settled: false

    onTrackKeyChanged: {
        endShown = false;
        if (settled && trackKey)
            flash();
    }

    Timer {
        running: true
        interval: 2000
        onTriggered: root.settled = true
    }

    function playPause(): void {
        if (player?.canTogglePlaying)
            player.togglePlaying();
        flash();
    }

    function next(): void {
        if (player?.canGoNext)
            player.next();
        flash();
    }

    function previous(): void {
        if (player?.canGoPrevious)
            player.previous();
        flash();
    }

    function seek(seconds: real): void {
        if (player?.canSeek)
            player.position = Math.max(0, Math.min(seconds, length));
    }

    // Brings up the player's window.
    function raise(): void {
        if (player?.canRaise)
            player.raise();
    }

    function time(seconds: real): string {
        const s = Math.max(0, Math.floor(seconds));
        const m = Math.floor(s / 60);
        return `${m}:${String(s % 60).padStart(2, "0")}`;
    }

    // Media keys (hypr/modules/keybindings.lua).
    IpcHandler {
        target: "media"

        function playPause(): void {
            root.playPause();
        }

        function next(): void {
            root.next();
        }

        function previous(): void {
            root.previous();
        }
    }
}
