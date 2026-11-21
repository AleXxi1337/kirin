import QtQuick
import QtMultimedia
import qs.services

// A video wallpaper playing, muted and looped, cropped to fill like the
// pictures. Loaded by Background.qml over the video's first frame: it shows
// once it's really playing, so the switch from that frame doesn't show.
// Its own file because QtMultimedia may not be installed: then the Loader
// fails and the first frame stays.
//
// Kept on the shared timeline (Wallpaper.videoTime) with the other
// monitors: a little faster or slower while it's off, a jump to it when it
// starts or comes back from a pause of its own.
Item {
    id: root

    // The wallpaper this slide shows; `file` what plays of it.
    property string path
    property string file: Wallpaper.videoFor(path)
    // Off: paused where it is.
    property bool playing: true

    Video {
        id: video

        anchors.fill: parent
        source: root.file ? `file://${root.file}` : ""
        loops: MediaPlayer.Infinite
        muted: true
        fillMode: VideoOutput.PreserveAspectCrop
        opacity: started ? 1 : 0

        // Frames are coming (the first one may take a moment).
        property bool started: false

        onPositionChanged: {
            if (position > 0)
                started = true;
        }
        onStartedChanged: {
            if (started)
                root.steer(true);
        }
        // A new file (the screen-size copy got ready): the player stops on
        // it, so it's started again here, after the source has changed.
        onSourceChanged: {
            started = false;
            if (root.playing)
                play();
        }
        onErrorOccurred: (error, message) => console.warn(`kirin: video wallpaper: ${message}`)

        Component.onCompleted: {
            if (root.playing)
                play();
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }
    }

    onPlayingChanged: {
        if (playing) {
            video.play();
            Qt.callLater(() => root.steer(true));
        } else {
            video.pause();
            video.playbackRate = 1;
        }
    }

    // Towards the shared timeline: within 40 ms is in step; up to 1.5 s off
    // is caught up by playing up to 10% faster or slower; more (or `jump`,
    // past 100 ms) seeks.
    function steer(jump: bool): void {
        const duration = video.duration;
        if (duration <= 0 || !playing)
            return;
        let diff = Wallpaper.videoTime(duration) - video.position;
        // The shorter way round the loop.
        if (diff > duration / 2)
            diff -= duration;
        else if (diff < -duration / 2)
            diff += duration;
        if ((jump && Math.abs(diff) > 100) || Math.abs(diff) > 1500) {
            video.seek(Wallpaper.videoTime(duration));
            video.playbackRate = 1;
        } else if (Math.abs(diff) < 40) {
            video.playbackRate = 1;
        } else {
            video.playbackRate = 1 + Math.max(-0.1, Math.min(0.1, diff / 2000));
        }
    }

    Timer {
        running: root.playing && video.started
        interval: 1000
        repeat: true
        onTriggered: root.steer(false)
    }
}
