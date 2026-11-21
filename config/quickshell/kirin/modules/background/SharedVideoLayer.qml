import QtQuick
import QtMultimedia
import Kirin.Video
import qs.services

// A video wallpaper on one monitor, from its shared player (SharedPlayer):
// the same frame as every other monitor. Paused here (`playing` off), it
// keeps its last frame and takes none; back on, it shows the current one.
// Loaded by Background.qml over the video's first frame, shown once frames
// come.
Item {
    id: root

    // The wallpaper this slide shows.
    property string path
    // Off: paused here (a fullscreen window, the power profile).
    property bool playing: true

    // The player of this slide's video; a slide being replaced keeps its
    // until the new wallpaper covers it, then the last frame.
    readonly property var player: Wallpaper.playerFor(path)
    readonly property bool started: player?.started ?? false
    // Frames have been shown: stays, so a slide being replaced keeps its
    // last frame rather than going back to the first.
    property bool seen: false
    // Fades in over the first frame only for a video just starting; one
    // already playing (the lock screen opening over the desktop) shows at
    // once, or its first frame would blink in between.
    property bool fade: false

    onPlayerChanged: {
        if (player?.started) {
            fade = false;
            seen = true;
        } else {
            fade = true;
        }
    }
    onStartedChanged: {
        if (started)
            seen = true;
    }

    VideoOutput {
        id: output

        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        opacity: root.seen ? 1 : 0

        Behavior on opacity {
            enabled: root.fade

            NumberAnimation {
                duration: 200
            }
        }
    }

    VideoFeed {
        video: root.player
        output: output
        active: root.playing && root.player !== null
    }
}
