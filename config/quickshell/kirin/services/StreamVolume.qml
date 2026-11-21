pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Every app's playback stream at full "volume", the multiplier no mixer
// shows (scripts/stream-volume.sh): Spotify starts its at 0.01 and played
// at 1% with everything at 100%. The volume apps and mixers set, per
// channel, isn't touched.
Singleton {
    id: root

    readonly property bool running: watcher.running

    Process {
        id: watcher

        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "sh", `${Quickshell.shellDir}/scripts/stream-volume.sh`]
        stdout: SplitParser {
            onRead: line => {
                const [id, was, ...app] = line.split(" ");
                console.info(`kirin: ${app.join(" ")}: stream volume ${was} -> 1`);
            }
        }
        // Stopped (PipeWire restarted, say): again a moment later.
        onExited: restartTimer.start()
    }

    Timer {
        id: restartTimer

        interval: 3000
        onTriggered: watcher.running = true
    }
}
