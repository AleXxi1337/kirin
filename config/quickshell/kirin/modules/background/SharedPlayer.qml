import QtQuick
import Kirin.Video
import qs.services

// The players of video wallpapers for all monitors (Kirin.Video, a C++
// module from kirin-plugins/video): each video decoded once, every frame to
// each monitor's SharedVideoLayer. Two, taking turns (Wallpaper.slots), so
// the video being replaced plays on until the new one covers it. Loaded by
// Wallpaper; without the module the load fails and each monitor plays the
// video itself (VideoLayer.qml).
//
// A player exists only while its slot has a video: emptied, it's destroyed,
// and its decoder's buffers (hundreds of MB of video memory for a 4K video)
// with it. One left with no source kept them.
Item {
    // The player of each slot, or null.
    readonly property var players: [first.item, second.item]

    component Player: SharedVideo {
        required property string path

        source: {
            const file = path ? Wallpaper.videoFor(path) : "";
            return file ? `file://${file}` : "";
        }
        onErrorStringChanged: {
            if (errorString)
                console.warn(`kirin: video wallpaper: ${errorString}`);
        }
    }

    component Slot: Loader {
        id: slot

        required property int index
        readonly property string path: Wallpaper.slots[index] ?? ""

        active: path !== ""
        sourceComponent: Player {
            path: slot.path
        }
    }

    Slot {
        id: first

        index: 0
    }

    Slot {
        id: second

        index: 1
    }
}
