pragma Singleton

import QtQuick
import Quickshell

// Material 3 design tokens.
Singleton {
    id: root

    // Colours come from Scheme (matugen); the M3 dark baseline is the fallback.
    // Every role animates when the scheme changes.
    function role(name: string, fallback: color): color {
        return Scheme.colors[name] ?? fallback;
    }

    // A scheme change: every role animates to the new one over
    // shiftDuration. Meanwhile elements' own colour animations (CAnim) step
    // aside and follow the roles as they are, so everything changes in step
    // (an animation restarted on every frame lagged behind), and Hyprland's
    // borders and bars are pushed the same in-between colours.
    readonly property int shiftDuration: 600
    readonly property bool shifting: shiftTimer.running

    Timer {
        id: shiftTimer

        interval: root.shiftDuration + 50
    }

    // Hyprland's borders and title bars, a frame of the shift at a time
    // (see colors.lua); the scheme's own colors.lua lands when it ends.
    property bool started: false

    Connections {
        target: Scheme

        function onColorsChanged(): void {
            // The first scheme read at start isn't a change: Hyprland
            // already has it, and shouldn't be walked from the fallback.
            if (!root.started) {
                root.started = true;
                return;
            }
            shiftTimer.restart();
            hyprStep.restart();
        }
    }

    Timer {
        id: hyprStep

        interval: 50
        repeat: true
        onTriggered: {
            if (!root.shifting) {
                stop();
                Scheme.applyToHyprland();
                return;
            }
            const hex = c => c.toString().slice(1, 7);
            const roles = {
                primary: root.m3primary,
                on_primary: root.m3onPrimary,
                tertiary: root.m3tertiary,
                on_tertiary: root.m3onTertiary,
                error: root.m3error,
                on_error: root.m3onError,
                surface_container: root.m3surfaceContainer,
                on_surface: root.m3onSurface,
                outline_variant: root.m3outlineVariant
            };
            const table = Object.entries(roles).map(([k, v]) => `${k}="${hex(v)}"`).join(",");
            Quickshell.execDetached(["hyprctl", "eval", `kirin_apply_colors({${table}})`]);
        }
    }

    property color m3primary: role("primary", "#d0bcff")
    property color m3onPrimary: role("on_primary", "#381e72")
    property color m3primaryContainer: role("primary_container", "#4f378b")
    property color m3onPrimaryContainer: role("on_primary_container", "#eaddff")
    property color m3secondary: role("secondary", "#ccc2dc")
    property color m3onSecondary: role("on_secondary", "#332d41")
    property color m3secondaryContainer: role("secondary_container", "#4a4458")
    property color m3onSecondaryContainer: role("on_secondary_container", "#e8def8")
    property color m3tertiary: role("tertiary", "#efb8c8")
    property color m3onTertiary: role("on_tertiary", "#492532")
    property color m3tertiaryContainer: role("tertiary_container", "#633b48")
    property color m3onTertiaryContainer: role("on_tertiary_container", "#ffd8e4")
    property color m3error: role("error", "#f2b8b5")
    property color m3onError: role("on_error", "#601410")
    property color m3surface: role("surface", "#141218")
    property color m3surfaceContainerLowest: role("surface_container_lowest", "#0f0d13")
    property color m3surfaceContainerLow: role("surface_container_low", "#1d1b20")
    property color m3surfaceContainer: role("surface_container", "#211f26")
    property color m3surfaceContainerHigh: role("surface_container_high", "#2b2930")
    property color m3surfaceContainerHighest: role("surface_container_highest", "#36343b")
    property color m3onSurface: role("on_surface", "#e6e0e9")
    property color m3onSurfaceVariant: role("on_surface_variant", "#cac4d0")
    property color m3inverseSurface: role("inverse_surface", "#e6e0e9")
    property color m3inverseOnSurface: role("inverse_on_surface", "#322f35")
    property color m3outline: role("outline", "#938f99")
    property color m3outlineVariant: role("outline_variant", "#49454f")
    property color m3shadow: role("shadow", "#000000")
    property color m3scrim: role("scrim", "#000000")

    Behavior on m3primary {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3onPrimary {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3primaryContainer {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3onPrimaryContainer {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3secondary {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3onSecondary {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3secondaryContainer {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3onSecondaryContainer {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3tertiary {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3onTertiary {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3tertiaryContainer {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3onTertiaryContainer {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3error {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3onError {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3surface {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3surfaceContainerLowest {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3surfaceContainerLow {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3surfaceContainer {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3surfaceContainerHigh {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3surfaceContainerHighest {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3onSurface {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3onSurfaceVariant {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3inverseSurface {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3inverseOnSurface {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3outline {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3outlineVariant {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3shadow {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }
    Behavior on m3scrim {
        ColorAnimation {
            duration: root.shiftDuration
            easing.type: Easing.OutCubic
        }
    }

    readonly property QtObject font: QtObject {
        readonly property string family: Config.appearance.fontFamily || "sans-serif"
        readonly property string icons: "Material Symbols Rounded"
    }

    // The lock screen's clock face (Google Sans Flex, rounded: kirin's own
    // copy in assets/fonts), loaded once here rather than by each lock
    // screen as it opens (parsing it stalled the screen locking).
    FontLoader {
        id: clockLoader

        source: Qt.resolvedUrl("../assets/fonts/GoogleSansFlex.ttf")
    }

    readonly property string clockFamily: clockLoader.status === FontLoader.Ready ? clockLoader.name : font.family

    // Body text is 10.5pt (14px at 96 dpi) by default; the type scale follows
    // the font size setting.
    readonly property real fontScale: Math.max(6, Config.appearance.fontSize || 10.5) / 10.5
    readonly property real spacingScale: Math.max(0, Config.appearance.spacing ?? 1)
    readonly property real roundingScale: Math.max(0, Config.appearance.rounding ?? 1)

    // A padding/gap of `n` px at 100%, scaled by the spacing setting.
    function sp(n: real): int {
        return Math.round(n * spacingScale);
    }

    // Type scale in px.
    readonly property QtObject size: QtObject {
        readonly property real scale: fontScale

        readonly property int display: Math.round(20 * scale)
        readonly property int headlineSmall: Math.round(24 * scale)
        readonly property int titleLarge: Math.round(22 * scale)
        readonly property int titleMedium: Math.round(16 * scale)
        readonly property int titleSmall: Math.round(14 * scale)
        readonly property int bodyLarge: Math.round(16 * scale)
        readonly property int bodyMedium: Math.round(14 * scale)
        readonly property int labelLarge: Math.round(14 * scale)
        readonly property int labelMedium: Math.round(12 * scale)
        readonly property int labelSmall: Math.round(11 * scale)
    }

    // Corner radius of an icon background of the given size (Settings →
    // Appearance → Icon shape): square at 0, a circle at 1.
    readonly property real iconRoundness: Math.max(0, Math.min(1, Config.appearance.iconRoundness ?? 1))

    function iconRadius(size: real): real {
        return size / 2 * iconRoundness;
    }

    readonly property QtObject rounding: QtObject {
        readonly property int small: Math.round(8 * roundingScale)
        readonly property int medium: Math.round(12 * roundingScale)
        readonly property int large: Math.round(16 * roundingScale)
        readonly property int card: Math.round(20 * roundingScale)
        readonly property int extraLarge: Math.round(28 * roundingScale)
    }

    // Material 3 (Expressive) motion tokens, as in Hyprstack. Curves are cubic
    // bezier segments for Easing.BezierSpline: c1x, c1y, c2x, c2y, endX, endY, ...
    // "Spatial" curves overshoot (springy movement and size), "effects" curves
    // don't (opacity, colour). Durations are divided by the animation speed
    // setting (2× = twice as fast); speed 0 turns animations off.
    readonly property real animationSpeed: Math.max(0, Config.appearance.animationSpeed ?? 1)
    readonly property real animScale: animationSpeed > 0 ? 1 / animationSpeed : 0

    readonly property QtObject anim: QtObject {
        readonly property QtObject curves: QtObject {
            readonly property var emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
            readonly property var emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
            readonly property var emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
            readonly property var standard: [0.2, 0, 0, 1, 1, 1]
            readonly property var standardAccel: [0.3, 0, 1, 1, 1, 1]
            readonly property var standardDecel: [0, 0, 0, 1, 1, 1]
            readonly property var expressiveFastSpatial: [0.42, 1.67, 0.21, 0.9, 1, 1]
            readonly property var expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1, 1, 1]
            readonly property var expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1]
            readonly property var expressiveFastEffects: [0.31, 0.94, 0.34, 1, 1, 1]
            readonly property var expressiveDefaultEffects: [0.34, 0.8, 0.34, 1, 1, 1]
            readonly property var expressiveSlowEffects: [0.34, 0.88, 0.34, 1, 1, 1]
        }

        readonly property QtObject durations: QtObject {
            readonly property int small: Math.round(200 * animScale)
            readonly property int normal: Math.round(400 * animScale)
            readonly property int large: Math.round(600 * animScale)
            readonly property int extraLarge: Math.round(1000 * animScale)
            readonly property int expressiveFastSpatial: Math.round(350 * animScale)
            readonly property int expressiveDefaultSpatial: Math.round(500 * animScale)
            readonly property int expressiveSlowSpatial: Math.round(650 * animScale)
            readonly property int expressiveFastEffects: Math.round(150 * animScale)
            readonly property int expressiveDefaultEffects: Math.round(200 * animScale)
            readonly property int expressiveSlowEffects: Math.round(300 * animScale)
        }

        // Older names, kept for simple fades.
        readonly property int fast: durations.expressiveFastEffects
        readonly property int normal: durations.expressiveDefaultEffects + 50
        readonly property int slow: durations.normal
    }
}
