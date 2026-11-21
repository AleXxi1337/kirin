pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Shell settings in ~/.config/kirin/config.json.
// The file is created with defaults on first run, edits to it apply live,
// and changes made from the UI are written back.
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/kirin`
    readonly property string path: `${dir}/config.json`

    property alias wallpaper: adapter.wallpaper
    property alias appearance: adapter.appearance
    property alias launcher: adapter.launcher
    property alias display: adapter.display
    property alias power: adapter.power
    property alias bar: adapter.bar
    property alias notifications: adapter.notifications
    property alias sounds: adapter.sounds
    property alias media: adapter.media
    property alias input: adapter.input

    // True once the file has been read (or created), so consumers don't act on
    // defaults that are about to be replaced by the user's values.
    property bool loaded: false

    // Named easings that can be stored in the config.
    readonly property var easings: ({
            Linear: Easing.Linear,
            OutCubic: Easing.OutCubic,
            InOutCubic: Easing.InOutCubic,
            InOutQuint: Easing.InOutQuint,
            OutExpo: Easing.OutExpo,
            OutBack: Easing.OutBack
        })

    function easing(name: string): int {
        return easings[name] ?? Easing.InOutCubic;
    }

    FileView {
        id: file

        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        // Batch rapid changes (dragging a slider) into one write.
        onAdapterUpdated: saveTimer.restart()

        onLoaded: {
            // Once per run, write the file back so settings added in newer
            // versions of kirin show up in it with their defaults.
            if (!root.loaded)
                writeAdapter();
            root.loaded = true;
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                mkdir.running = true;
            else
                root.loaded = true;
        }

        JsonAdapter {
            id: adapter

            property JsonObject appearance: JsonObject {
                // Where the colour scheme comes from: wallpaper | color
                property string source: "wallpaper"
                // Seed colour when source is "color".
                property string color: "#6750a4"
                // dark | light
                property string mode: "dark"
                // matugen scheme type without the "scheme-" prefix.
                property string variant: "tonal-spot"
                // Font for shell windows; "sans-serif" follows the system default.
                property string fontFamily: "sans-serif"
                // Body text size in points; other text scales with it.
                property real fontSize: 10.5
                // Multipliers for paddings/gaps and corner radii, 1 = 100%.
                property real spacing: 1
                property real rounding: 1
                // Shape of icon backgrounds (notifications, launcher): 0 square,
                // 1 round.
                property real iconRoundness: 1
                // Animation speed for the shell and Hyprland: 2 = twice as fast,
                // 0 turns animations off.
                property real animationSpeed: 1
            }

            property JsonObject display: JsonObject {
                // Hyprland scale for all monitors (the primary one's, when
                // physicalSizes is on).
                property real scale: 1
                // Take the monitors' real sizes into account: the others' scale
                // follows the primary one's so things are the same physical
                // size on every screen, and they're arranged in millimetres.
                // Off: one scale for all, arranged by their pixels.
                property bool physicalSizes: false
                // Arrangements per combination of monitors (see services/Monitors.qml):
                // { "<id> + <id>": { monitors: { "<id>": { x, y } } } }, logical px.
                property var profiles: ({})
                // Physical sizes entered by hand when EDID is wrong (TVs often are):
                // { "<description>": { width: mm, height: mm } }.
                property var physical: ({})
            }

            property JsonObject power: JsonObject {
                // Switch to the power saver profile when unplugged; the previous
                // profile comes back when plugged in again.
                property bool saverOnBattery: true
                // Switch to the power saver profile when the battery runs low.
                property bool saverWhenLow: true
                // "Low", in percent.
                property int lowLevel: 20

                // Asleep for less than this (minutes), waking needs no
                // password: the lock screen (always on before sleep, so
                // nothing shows on waking) goes by itself. 0: always ask.
                property int passwordAfterSleep: 5
                // "Charge to 100% once": the charge limit lifted until the
                // charger is unplugged, then back (Power.chargeFullOnce).
                property bool fullChargeOnce: false
                // No password at all: the lock screen still comes (on
                // logging in, the power menu, before sleep), with its clock, and a
                // key or a click opens it.
                property bool noPassword: false

                // On battery, while idle (services/Idle.qml), in minutes
                // each after the one before: the screen dims, turns off,
                // then the machine locks and sleeps. 0: that step is left
                // out. On mains, none of it.
                property JsonObject idle: JsonObject {
                    property real dimAfter: 15
                    property real offAfter: 5
                    property real sleepAfter: 15
                    // On mains too (for trying the steps out).
                    property bool onMains: false
                    // Brightness while dimmed.
                    property real dimLevel: 0.3
                }
            }

            property JsonObject bar: JsonObject {
                // Bottom modules, top to bottom, by id (see BarModules); ones
                // missing here are added at the end.
                property var modules: ["media", "tray", "keyboard", "brightness", "volume", "wifi", "bluetooth", "battery", "clock", "notifications"]
                // Modules turned off, by id.
                property var hiddenModules: []
                // Brightness, sound, network and Bluetooth together behind a
                // gear (BarModules.grouped), moved as one.
                property bool groupControls: true
                // App id -> symbol name (Papirus symbolic, e.g.
                // "web-browser-symbolic") for the workspaces, instead of the
                // one found.
                property var appSymbols: ({})
                // Tray apps shown in the bar; with more, they all go into a
                // card behind "⋯". 0: all in the bar.
                property int trayVisible: 2
                // Gap between the bottom modules, in px (Settings → Bar).
                property int moduleSpacing: 6
                // Tray apps not shown, by their id (StatusNotifierItem id,
                // usually the app's name).
                property var trayHidden: ["udiskie"]
                // App id -> icon name to show in the tray instead of its own.
                property var trayIcons: ({})
            }

            property JsonObject sounds: JsonObject {
                // Sound theme: folder name in share/sounds (Settings → Sounds).
                property string theme: "Yaru"
                // 0–1, for all of kirin's sounds.
                property real volume: 0.6
                // All of them off, the volume kept (the mixer's mute).
                property bool muted: false
                // Events turned on or off, by id (see SoundFx.events); missing
                // ones use the event's default.
                property var events: ({})
                // Sound picked per event (a theme sound name or a file's
                // path); missing ones use the event's default.
                property var choice: ({})
            }

            // Keyboard, mouse and touchpad (Settings → Input), passed to
            // Hyprland's input section (services/HyprSync.qml). Defaults as
            // hypr/modules/input.lua has them.
            property JsonObject input: JsonObject {
                // xkb layouts in order; the first is on at start.
                property var layouts: ["us", "ru"]
                // xkb option switching between them.
                property string switchKeys: "grp:alt_shift_toggle"
                // Key repeat: per second, and after how long (ms).
                property int repeatRate: 25
                property int repeatDelay: 600
                property bool numlock: false

                // -1 … 1.
                property real mouseSensitivity: 1
                // Pointer acceleration (adaptive) or none (flat).
                property bool mouseAcceleration: false
                property bool mouseNaturalScroll: false
                property bool leftHanded: false
                // Focus follows the pointer (else a click focuses).
                property bool focusFollowsMouse: true

                property bool touchpadNaturalScroll: true
                property real touchpadScrollSpeed: 0.3
                property bool tapToClick: true
                property bool disableWhileTyping: true
                // A click with two fingers is a right click (else: the bottom
                // right corner).
                property bool twoFingerRightClick: true

                // Hyprland shortcuts changed from their defaults (Settings →
                // Shortcuts, services/Shortcuts.qml): { id: "MODS + key" },
                // "" for off.
                property var shortcuts: ({})
            }

            property JsonObject media: JsonObject {
                // The media card at the bottom right (modules/media).
                property bool enabled: true
                // Always there on a desktop with no windows.
                property bool onEmptyDesktop: true
                // Paused, it stays on the empty desktop this many minutes
                // (0: as long as the player is open).
                property int pausedMinutes: 5
                // With windows open, it shows this many seconds when the song
                // changes or a media key is pressed.
                property int showSeconds: 15
                // The song on the lock screen, under the clock.
                property bool lockScreen: true
            }

            property JsonObject notifications: JsonObject {
                // Do not disturb: no popups (critical ones still show); they
                // still go to the notification centre.
                property bool dnd: false
                // Seconds a popup stays when the app doesn't say.
                property int timeout: 6
                // Apps that play their own sound, by app name (as shown on the
                // notification, any case), so it isn't heard twice.
                property var silentApps: ["Telegram Desktop", "Telegram", "Discord"]
            }

            property JsonObject launcher: JsonObject {
                // Search files in the home directory (fd + fzf).
                property bool files: true
                // Web search fallback: google | duckduckgo | none
                property string webSearch: "google"
            }

            property JsonObject wallpaper: JsonObject {
                // Folder the launcher's /wallpaper picker lists (recursively).
                property string directory: "~/Pictures/Wallpapers"

                // One image stretched over all monitors instead of one per monitor.
                property bool span: true

                property JsonObject transition: JsonObject {
                    // circle | fade | none
                    property string type: "circle"
                    property int duration: 900
                    property string easing: "InOutCubic"
                }

                // Video wallpapers (Settings → Wallpaper → Animated wallpapers).
                property JsonObject video: JsonObject {
                    // Play a smaller copy (made once) instead of the original.
                    property bool shrink: true
                    // Its size in pixels: hd | fhd | qhd | uhd (see Wallpaper).
                    property string resolution: "fhd"
                    // Frames per second, at most.
                    property int fps: 30
                }
            }
        }
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: file.writeAdapter()
    }

    Process {
        id: mkdir

        command: ["mkdir", "-p", root.dir]
        onExited: {
            file.writeAdapter();
            root.loaded = true;
        }
    }
}
