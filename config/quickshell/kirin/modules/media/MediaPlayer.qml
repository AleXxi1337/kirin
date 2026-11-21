pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.components
import qs.services

// What's playing (Media), at the bottom right of the primary monitor (the
// card itself: MediaCard.qml; the bar has it too, modules/bar/MediaButton).
//   - Nothing over its place (the desktop empty, or its windows elsewhere on
//     the screen): there all the time; paused, for 5 minutes more.
//   - Windows open: for 15 s when the song changes or a media key is
//     pressed (not when it was changed from the bar's media card). The
//     pointer on it keeps it.
//   - Never over a fullscreen window (a game), nor while the screen locks,
//     nor while the bar's media card is open.
// The cover is the background; over it the title, artist and a thin
// progress line. Hovered: play/pause across from the title, the arrows at
// the line's sides, and the line seeks. A badge at the top left says where
// it plays: Spotify or a browser.
Variants {
    model: Quickshell.screens.filter(s => s.name === Monitors.primary?.name)

    PanelWindow {
        id: window

        required property ShellScreen modelData

        readonly property real cardWidth: Theme.sp(480)
        // Room for the shadow and the slide-in.
        readonly property real pad: Theme.sp(48)

        readonly property var monitor: Hyprland.monitors.values.find(m => m.name === modelData.name) ?? null
        // The workspace shown and its windows.
        readonly property var windowsShown: monitor?.activeWorkspace?.toplevels.values ?? []

        // Where the card is (unfolded), in global coordinates, and whether a
        // window on the workspace shown covers any of it (its titlebar too,
        // in windows mode). Windows elsewhere on the screen don't count.
        readonly property rect cardRect: Qt.rect(modelData.x + modelData.width - edgeRight - cardWidth, modelData.y + modelData.height - edgeBottom - card.fullHeight, cardWidth, card.fullHeight)
        // hypr/modules/bars.lua: bar_height.
        readonly property int titlebar: WindowMode.windows ? 32 : 0
        readonly property bool covered: {
            const r = cardRect;
            for (const t of windowsShown) {
                const o = t.lastIpcObject;
                if (!o?.at || !o?.size)
                    continue;
                const x = o.at[0], y = o.at[1] - titlebar, w = o.size[0], h = o.size[1] + titlebar;
                if (x < r.x + r.width && x + w > r.x && y < r.y + r.height && y + h > r.y)
                    return true;
            }
            return false;
        }

        // Hyprland says nothing when a floating window moves or is resized:
        // its place is read again once a second while there are windows.
        Timer {
            running: Config.media.enabled && Config.media.onEmptyDesktop && Media.hasTrack && window.windowsShown.length > 0 && !Panels.locking
            interval: 1000
            repeat: true
            onTriggered: Hyprland.refreshToplevels()
        }
        readonly property bool fullscreen: (Wallpaper.coverage[modelData.name] ?? 0) >= 2

        // Paused for a while: off the empty desktop too.
        property bool stale: false

        Timer {
            id: staleTimer

            // Settings → Media; 0: never (as long as the player is open).
            interval: Math.max(1, Config.media.pausedMinutes) * 60 * 1000
            onTriggered: window.stale = Config.media.pausedMinutes > 0
        }

        Connections {
            target: Media

            function onPlayingChanged(): void {
                window.stale = false;
                if (Media.playing)
                    staleTimer.stop();
                else
                    staleTimer.restart();
            }

            function onFlash(): void {
                // Switched from the bar's media card: it's in sight there.
                if (Panels.mediaCardOpen || barQuiet.running)
                    return;
                flashTimer.restart();
            }
        }

        // The bar's media card just closed: a song changed from it may only
        // come through now.
        Timer {
            id: barQuiet

            interval: 3000
        }

        Connections {
            target: Panels

            function onMediaCardOpenChanged(): void {
                if (!Panels.mediaCardOpen)
                    barQuiet.restart();
            }
        }

        Component.onCompleted: {
            if (!Media.playing)
                staleTimer.start();
        }

        Timer {
            id: flashTimer

            // Settings → Media.
            interval: Math.max(1, Config.media.showSeconds) * 1000
        }

        // Left by the pointer: a moment more, then by the rules again.
        Timer {
            id: linger

            interval: 2000
        }

        readonly property bool hovered: card.pointerIn
        onHoveredChanged: {
            if (!hovered)
                linger.restart();
        }

        // Nothing over its place (the desktop empty, or the windows elsewhere).
        readonly property bool pinned: Config.media.onEmptyDesktop && !covered && (Media.playing || !stale)
        // Away while the bar's media card is open: one card at a time.
        readonly property bool wanted: Config.media.enabled && Media.hasTrack && !fullscreen && !Panels.locking && !Panels.mediaCardOpen && (pinned || flashTimer.running || linger.running || hovered)

        // Pinned on the empty desktop: the bar shows no media icon then.
        Binding {
            target: Panels
            property: "mediaPinned"
            value: Config.media.enabled && Media.hasTrack && !window.fullscreen && !Panels.locking && window.pinned
        }

        screen: modelData
        color: "transparent"
        visible: wanted || card.opacity > 0.001
        anchors.bottom: true
        anchors.right: true
        margins.bottom: 0
        margins.right: 0
        // From the screen's edges: three times Hyprland's outer gaps
        // (gaps_out), as the notifications: well in from the windows' line.
        readonly property real edgeRight: HyprLook.gapsRight * 3
        readonly property real edgeBottom: HyprLook.gapsBottom * 3

        implicitWidth: pad + cardWidth + edgeRight
        // Fixed (the card unfolded and its shadow): resizing the surface as
        // it unfolds would stutter. The mask keeps the rest from clicks.
        implicitHeight: card.fullHeight + pad + edgeBottom

        // Its room, for the notifications above it, coming and going with
        // it. Its height as it is: the notifications stay put (they hang
        // from the top), only where they fade out moves.
        Binding {
            target: Panels
            property: "mediaReserve"
            value: (card.height + window.edgeBottom) * card.opacity
        }

        WlrLayershell.namespace: "kirin-media"
        // Above windows, under the launcher and notifications.
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {
            item: card
        }

        // The shadow as the bar's cards have it (Hyprland's settings).
        WindowShadow {
            target: card
        }

        // Comes and goes as the bar's cards do: fading in, growing a little
        // from its corner.
        MediaCard {
            id: card

            cardWidth: window.cardWidth
            x: window.pad + (window.wanted ? 0 : Theme.sp(12))
            y: window.height - window.edgeBottom - height
            opacity: window.wanted ? 1 : 0
            scale: window.wanted ? 1 : 0.94
            transformOrigin: Item.BottomRight

            Behavior on x {
                Anim {
                    type: Anim.FastSpatial
                }
            }
            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }
            Behavior on scale {
                Anim {
                    type: Anim.FastSpatial
                }
            }
        }
    }
}
