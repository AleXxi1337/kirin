import QtQuick
import QtQuick.Effects
import qs.services

// The shadow Hyprland gives windows (decoration:shadow, read by HyprLook), for
// shell surfaces Hyprland doesn't decorate: layers (bar, launcher) and popups
// (bar cards, menus). Declare it as a sibling right before `target`; it
// follows the target's geometry, corners, opacity and scale.
//
// Hyprland's shadow reaches `range` px past the window; render_power makes
// it fall off faster (more of it close to the edge). Approximated with a
// blur over the range plus a little spread that grows with the power.
RectangularShadow {
    id: root

    required property Item target
    // Focused-window colour (decoration:shadow:color) instead of the inactive one.
    property bool active: false

    readonly property real range: HyprLook.shadowRange * HyprLook.shadowScale

    x: target.x
    y: target.y
    width: target.width
    height: target.height
    radius: target.radius ?? 0
    opacity: target.opacity
    scale: target.scale
    transformOrigin: target.transformOrigin
    visible: HyprLook.shadowEnabled && target.visible && range > 0

    offset: Qt.vector2d(HyprLook.shadowOffset.x, HyprLook.shadowOffset.y)
    color: active ? HyprLook.shadowColor : HyprLook.shadowColorInactive
    blur: HyprLook.shadowSharp ? 0 : range
    spread: HyprLook.shadowSharp ? range : range * Math.max(0, HyprLook.shadowRenderPower - 1) / 10
}
