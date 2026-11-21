import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property var transition: Config.wallpaper.transition
    readonly property bool animated: transition.type !== "none"

    // Video wallpapers and the smaller copies they play from
    // (services/Wallpaper.qml).
    readonly property var video: Config.wallpaper.video
    readonly property bool shrinking: video.shrink
    readonly property bool isVideo: Wallpaper.isVideo(Wallpaper.current)
    readonly property var info: Wallpaper.videoInfo[Wallpaper.current] ?? null
    readonly property bool copyNeeded: info !== null && (info.copyWidth !== info.width || info.copyFps !== info.fps)

    function describe(w: int, h: int, fps: int): string {
        return `${w} × ${h}${fps > 0 ? ` · ${fps} fps` : ""}`;
    }

    // What the current video plays as, and whether its copy is there yet.
    readonly property string playsAs: {
        if (!shrinking)
            return "The original (shrinking is off)";
        if (!info)
            return "Checking…";
        if (!copyNeeded)
            return "The original: it's within the settings below";
        const size = describe(info.copyWidth, info.copyHeight, info.copyFps);
        if (Wallpaper.videos[Wallpaper.current])
            return `${size} · copy ready`;
        if (Wallpaper.making === Wallpaper.current)
            return `${size} · making the copy, the original plays meanwhile…`;
        return `${size} · copy waiting to be made`;
    }

    spacing: Theme.sp(24)

    // Current wallpaper.
    ClippingRectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: width * 9 / 16
        Layout.maximumHeight: 320
        radius: Theme.rounding.card
        color: Theme.m3surfaceContainerHigh

        Image {
            anchors.fill: parent
            // A video: its first frame.
            source: Wallpaper.imageFor(Wallpaper.current) ? `file://${Wallpaper.imageFor(Wallpaper.current)}` : ""
            sourceSize.width: width * 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        StyledText {
            visible: !Wallpaper.current
            anchors.centerIn: parent
            text: "No wallpaper set"
            color: Theme.m3onSurfaceVariant
        }

        // Path caption over the picture.
        Rectangle {
            visible: Wallpaper.current
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Theme.sp(12)
            width: Math.min(caption.implicitWidth + Theme.sp(24), parent.width - Theme.sp(24))
            height: 32
            radius: 16
            color: Qt.alpha(Theme.m3surface, 0.8)

            StyledText {
                id: caption

                anchors.fill: parent
                anchors.leftMargin: Theme.sp(12)
                anchors.rightMargin: Theme.sp(12)
                text: Wallpaper.current
                elide: Text.ElideMiddle
                color: Theme.m3onSurfaceVariant
                font.pixelSize: Theme.size.labelMedium
            }
        }
    }

    SettingsSection {
        title: "Library"

        SettingsRow {
            icon: "folder"
            title: "Wallpaper folder"
            subtitle: "Listed by /wallpaper in the launcher, including subfolders"

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: folderInput.implicitHeight + Theme.sp(24)
                radius: Theme.rounding.medium
                color: Theme.m3surfaceContainerHighest
                border.width: folderInput.activeFocus ? 2 : 0
                border.color: Theme.m3primary

                TextInput {
                    id: folderInput

                    anchors.fill: parent
                    anchors.leftMargin: Theme.sp(16)
                    anchors.rightMargin: Theme.sp(16)
                    verticalAlignment: TextInput.AlignVCenter
                    text: Config.wallpaper.directory
                    color: Theme.m3onSurface
                    selectionColor: Theme.m3primary
                    selectedTextColor: Theme.m3onPrimary
                    font.family: Theme.font.family
                    font.pixelSize: Theme.size.bodyLarge
                    clip: true
                    selectByMouse: true
                    onEditingFinished: {
                        const path = text.trim();
                        if (path)
                            Config.wallpaper.directory = path;
                        else
                            text = Config.wallpaper.directory;
                    }
                }
            }
        }
    }

    SettingsSection {
        title: "Monitors"

        SettingsRow {
            icon: "desktop_windows"
            title: "Span across monitors"
            subtitle: "Stretch one image over all screens, each monitor shows its own part"
            trailing: ToggleSwitch {
                checked: Config.wallpaper.span
                onToggled: checked => Config.wallpaper.span = checked
            }
        }
    }

    SettingsSection {
        title: "Transition"

        SettingsRow {
            icon: "animation"
            title: "Animation"
            trailing: FilledButton {
                icon: "play_arrow"
                text: "Preview"
                visible: Wallpaper.current
                onClicked: Wallpaper.replay()
            }

            SegmentedButtons {
                current: root.transition.type
                options: [
                    {
                        value: "circle",
                        label: "Circle"
                    },
                    {
                        value: "fade",
                        label: "Fade"
                    },
                    {
                        value: "none",
                        label: "None"
                    }
                ]
                onSelected: value => root.transition.type = value
            }
        }

        SettingsRow {
            icon: "timer"
            title: "Duration"
            enabled: root.animated
            opacity: enabled ? 1 : 0.38
            trailing: StyledText {
                text: `${root.transition.duration} ms`
                color: Theme.m3onSurfaceVariant
            }

            ValueSlider {
                Layout.fillWidth: true
                from: 100
                to: 3000
                stepSize: 50
                value: root.transition.duration
                onMoved: value => root.transition.duration = value
            }
        }

        SettingsRow {
            icon: "show_chart"
            title: "Easing"
            enabled: root.animated
            opacity: enabled ? 1 : 0.38

            ChipGroup {
                Layout.fillWidth: true
                current: root.transition.easing
                options: [
                    {
                        value: "InOutCubic",
                        label: "Smooth"
                    },
                    {
                        value: "OutCubic",
                        label: "Ease out"
                    },
                    {
                        value: "InOutQuint",
                        label: "Sharp"
                    },
                    {
                        value: "OutExpo",
                        label: "Exponential"
                    },
                    {
                        value: "OutBack",
                        label: "Overshoot"
                    },
                    {
                        value: "Linear",
                        label: "Linear"
                    }
                ]
                onSelected: value => root.transition.easing = value
            }
        }
    }

    SettingsSection {
        title: "Animated wallpapers"

        // The current wallpaper, when it's a video: what it is and what plays.
        SettingsRow {
            visible: root.isVideo
            icon: "movie"
            title: "Original"
            subtitle: root.info ? root.describe(root.info.width, root.info.height, root.info.fps) : root.shrinking ? "Checking…" : "Size known when shrinking is on"
        }

        SettingsRow {
            visible: root.isVideo
            icon: "play_circle"
            title: "Plays as"
            subtitle: root.playsAs
        }

        SettingsRow {
            icon: "compress"
            title: "Shrink videos"
            subtitle: "Play a smaller copy, made once in the background: less work for the processor and the battery, smoother everything else"
            trailing: ToggleSwitch {
                checked: root.shrinking
                onToggled: checked => root.video.shrink = checked
            }
        }

        SettingsRow {
            icon: "aspect_ratio"
            title: "Resolution"
            subtitle: "At most this many pixels. Videos of other shapes (4:3, ultrawide, vertical) keep their shape with the same number of pixels. Never bigger than your screens need, or than the video itself"
            enabled: root.shrinking
            opacity: enabled ? 1 : 0.38

            SegmentedButtons {
                current: root.video.resolution
                options: [
                    {
                        value: "hd",
                        label: "HD"
                    },
                    {
                        value: "fhd",
                        label: "Full HD"
                    },
                    {
                        value: "qhd",
                        label: "2K"
                    },
                    {
                        value: "uhd",
                        label: "4K"
                    }
                ]
                onSelected: value => root.video.resolution = value
            }
        }

        SettingsRow {
            icon: "speed"
            title: "Frame rate"
            subtitle: "At most; videos slower than this keep their own"
            enabled: root.shrinking
            opacity: enabled ? 1 : 0.38
            trailing: StyledText {
                text: `${root.video.fps} fps`
                color: Theme.m3onSurfaceVariant
                font.features: {
                    "tnum": 1
                }
            }

            ValueSlider {
                Layout.fillWidth: true
                from: 10
                to: 60
                stepSize: 5
                value: root.video.fps
                onMoved: value => root.video.fps = Math.round(value)
            }
        }
    }
}
