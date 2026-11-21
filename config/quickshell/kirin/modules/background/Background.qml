pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.services

// One background layer per monitor; a single wallpaper spans all of them.
// A new wallpaper grows out of a circle at a random point over the old one.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win

        required property ShellScreen modelData

        screen: modelData
        color: "black"

        // At logging in: black until the lock screen is up over it.
        Rectangle {
            anchors.fill: parent
            z: 1000
            color: "black"
            visible: Panels.loginHold
        }

        WlrLayershell.namespace: "kirin-background"
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        property Item shown

        function show(path: string): void {
            if (!path) {
                if (shown)
                    shown.destroy();
                shown = null;
                return;
            }
            // The very first wallpaper just fades in; later ones use the configured transition.
            const type = shown ? Config.wallpaper.transition.type : "fade";
            shown = slideComponent.createObject(win.contentItem, {
                path,
                file: Wallpaper.isVideo(path) ? Wallpaper.imageFor(path) : Wallpaper.fileFor(path),
                type
            });
            // A video's first frame may still be being made: the slide waits
            // for it (nothing to reveal before).
            if (Wallpaper.isVideo(path))
                shown.file = Qt.binding(() => Wallpaper.imageFor(path));
        }


        Component.onCompleted: show(Wallpaper.displayed)

        Connections {
            target: Wallpaper

            function onDisplayedChanged(): void {
                win.show(Wallpaper.displayed);
            }

            function onReplayRequested(): void {
                win.show(Wallpaper.displayed);
            }
        }

        Component {
            id: slideComponent

            Item {
                id: slide

                required property string path
                // What's drawn: the cached copy at screen size if there is one.
                required property string file
                // circle | fade | none
                required property string type
                readonly property bool reveal: type === "circle"
                readonly property int duration: Config.wallpaper.transition.duration
                readonly property int easing: Config.easing(Config.wallpaper.transition.easing)

                property real progress: reveal ? 0 : 1
                // Covering: loaded and fully revealed, so the old wallpaper underneath can go.
                property bool loaded: false
                readonly property bool done: loaded && progress === 1 && opacity === 1

                // Circle geometry in desktop coordinates, shared by all monitors.
                readonly property real cx: Wallpaper.revealPoint.x * width
                readonly property real cy: Wallpaper.revealPoint.y * height
                readonly property real maxRadius: Math.hypot(Math.max(cx, width - cx), Math.max(cy, height - cy))

                // Spanning: covers the whole desktop, shifted so this monitor shows its slice.
                // Otherwise: just this monitor.
                readonly property bool span: Config.wallpaper.span
                x: span ? Wallpaper.desktop.x - (win.modelData?.x ?? 0) : 0
                y: span ? Wallpaper.desktop.y - (win.modelData?.y ?? 0) : 0
                width: span ? Wallpaper.desktop.width : win.width
                height: span ? Wallpaper.desktop.height : win.height
                opacity: type === "fade" ? 0 : 1

                // The picture, and a video over it. While the circle grows it's
                // drawn through the mask instead, video frames and all.
                Item {
                    id: content

                    anchors.fill: parent
                    visible: slide.progress === 1

                    Image {
                        id: image

                        anchors.fill: parent
                        source: slide.file ? `file://${slide.file}` : ""
                        fillMode: Image.PreserveAspectCrop
                        // modelData is briefly null while a monitor is being removed.
                        readonly property real dpr: win.modelData?.devicePixelRatio ?? 1
                        sourceSize: Qt.size(width * dpr, height * dpr)
                        asynchronous: true
                        // Kept in Qt's image cache: the lock screen draws the same
                        // file at the same size and gets it from there at once,
                        // with no blank frame.
                        cache: true

                        onStatusChanged: {
                            if (status !== Image.Ready)
                                return;
                            slide.loaded = true;
                            if (slide.type === "circle")
                                grow.start();
                            else if (slide.type === "fade")
                                fadeIn.start();
                        }
                    }

                    // A video: plays over its first frame (the image above),
                    // from the start, inside the growing circle too.
                    Loader {
                        anchors.fill: parent
                        active: Wallpaper.isVideo(slide.path)
                        // The shared player when Kirin.Video is there, else one of
                        // its own.
                        source: Wallpaper.sharedPlayers ? "SharedVideoLayer.qml" : "VideoLayer.qml"
                        onLoaded: {
                            item.path = slide.path;
                            // Paused by the rules in Wallpaper (fullscreen windows,
                            // the power profile).
                            item.playing = Qt.binding(() => Wallpaper.videoPlaying(win.modelData));
                        }
                    }
                }

                Item {
                    id: mask

                    anchors.fill: parent
                    visible: false
                    layer.enabled: true

                    Rectangle {
                        readonly property real r: slide.progress * slide.maxRadius

                        x: slide.cx - r
                        y: slide.cy - r
                        width: r * 2
                        height: r * 2
                        radius: r
                        antialiasing: true
                    }
                }

                Loader {
                    anchors.fill: parent
                    active: slide.progress < 1

                    sourceComponent: MultiEffect {
                        source: content
                        maskEnabled: true
                        maskSource: mask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }
                }

                NumberAnimation on progress {
                    id: grow

                    running: false
                    to: 1
                    duration: slide.duration
                    easing.type: slide.easing
                }

                NumberAnimation on opacity {
                    id: fadeIn

                    running: false
                    to: 1
                    duration: slide.duration
                    easing.type: slide.easing
                }

                // Drop the previous wallpaper once the new one has covered it.
                Timer {
                    running: win.shown !== slide && (win.shown?.done ?? false)
                    interval: 0
                    onTriggered: {
                        // The old video's player can stop (Wallpaper).
                        Wallpaper.transitionDone();
                        slide.destroy();
                    }
                }
            }
        }
    }
}
