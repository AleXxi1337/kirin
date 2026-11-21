import QtQuick
import qs.components
import qs.services

// M3 (expressive) slider: thick track split by a thin handle.
// Controlled: emits moved(), the owner updates `value`.
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: 0
    signal moved(real value)

    readonly property real handleWidth: mouse.pressed ? 2 : 4
    readonly property real gap: 6
    // Drawn value: glides to `value` when it changes from outside (keys,
    // scrolling), follows the pointer directly while dragging. Each frame it
    // covers a share of the remaining distance, so it keeps up with a value
    // that changes many times a second (a held key); an animation restarted
    // on every change barely moved until the key was let go.
    property real shownValue: 0
    Component.onCompleted: shownValue = value
    readonly property real ratio: Math.max(0, Math.min(1, (shownValue - from) / (to - from)))

    FrameAnimation {
        running: Math.abs(root.shownValue - root.value) > 1e-4
        onTriggered: {
            if (mouse.pressed) {
                root.shownValue = root.value;
                return;
            }
            // Time constant 50 ms: about 95% of the way in 150 ms.
            const k = 1 - Math.exp(-frameTime / 0.05);
            const next = root.shownValue + (root.value - root.shownValue) * k;
            root.shownValue = Math.abs(root.value - next) < 1e-3 * (root.to - root.from) ? root.value : next;
        }
    }

    readonly property real handleX: ratio * (width - 4) + 2 - handleWidth / 2

    implicitWidth: 240
    implicitHeight: 44

    function valueAt(x: real): real {
        const r = Math.max(0, Math.min(1, x / width));
        let v = from + r * (to - from);
        if (stepSize > 0)
            v = Math.round(v / stepSize) * stepSize;
        return Math.max(from, Math.min(to, v));
    }

    function update(x: real): void {
        const v = valueAt(x);
        if (v !== value)
            moved(v);
    }

    // Active part of the track.
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 0
        width: Math.max(0, root.handleX - root.gap)
        height: 16
        color: Theme.m3primary
        topLeftRadius: 8
        bottomLeftRadius: 8
        topRightRadius: 2
        bottomRightRadius: 2
    }

    // Inactive part of the track.
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: root.handleX + root.handleWidth + root.gap
        width: Math.max(0, root.width - x)
        height: 16
        color: Theme.m3secondaryContainer
        topLeftRadius: 2
        bottomLeftRadius: 2
        topRightRadius: 8
        bottomRightRadius: 8
    }

    Rectangle {
        x: root.handleX
        width: root.handleWidth
        height: parent.height
        radius: width / 2
        color: Theme.m3primary

        Behavior on width {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: e => root.update(e.x)
        onPositionChanged: e => {
            if (pressed)
                root.update(e.x);
        }
        onWheel: e => {
            const step = root.stepSize > 0 ? root.stepSize : (root.to - root.from) / 20;
            const v = Math.max(root.from, Math.min(root.to, root.value + (e.angleDelta.y > 0 ? step : -step)));
            if (v !== root.value)
                root.moved(v);
        }
    }
}
