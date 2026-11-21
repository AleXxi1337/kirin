pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.services
import "../../services/layout.js" as Layout

// Drag-and-drop monitor arrangement. Monitors are drawn at their physical size
// (millimetres), so they look like they do on the desk; a dragged one snaps to
// the others: flush against their sides, aligned with their edges, or centred
// on them. Applying converts the arrangement to Hyprland's logical pixels,
// keeping who touches whom and how they're aligned (layout.js).
Item {
    id: root

    // [{ key, name, x, y, w, h (mm), px: { w, h } (logical), inches }]
    property var items: []
    property bool dirty: false

    property int dragging: -1
    property var dragStart: null
    // Snap guides of the current drag, in mm: { x: [...], y: [...] }.
    property var guides: ({
            x: [],
            y: []
        })

    // mm → canvas mapping. Frozen while dragging so the view doesn't shift.
    property var frozenView: null
    readonly property var view: frozenView ?? fit(items)

    implicitHeight: Theme.sp(260)

    Component.onCompleted: reload()

    // Re-read when monitors change, or the primary monitor or saved layout does.
    readonly property var source: [Monitors.list, Monitors.primaryId, Monitors.profile]

    onSourceChanged: {
        if (!dirty && dragging < 0)
            reload();
    }

    // Hyprland doesn't announce position changes; re-read after applying.
    Timer {
        id: refreshTimer

        interval: 400
        onTriggered: Monitors.refresh()
    }

    // The arrangement in millimetres: the profile's saved one when it fits the
    // monitors' current physical sizes, else Hyprland's converted from pixels.
    // (Pixels can't always tell how monitors were arranged physically: with
    // equal pixel widths, centred and edge-aligned are the same position.)
    function reload(): void {
        // Monitors as kirin sets them up (chosen mode and rotation), so a
        // rotated monitor is drawn rotated right away.
        const list = Monitors.extended.filter(m => m.width > 0).map(m => {
            const t = Monitors.target(m);
            const mm = Monitors.physicalExtent(t);
            return {
                key: Monitors.idOf(m),
                name: m.name,
                primary: Monitors.idOf(m) === Monitors.primaryId,
                rotation: t.transform * 90,
                px: Monitors.logicalSize(t, Monitors.scaleFor(m)),
                pxNow: Monitors.logicalSize(m),
                w: mm.w,
                h: mm.h,
                inches: Math.hypot(mm.w, mm.h) / 25.4,
                lx: m.x,
                ly: m.y
            };
        });

        // Saved layout (each monitor keeps its centre if its size changed),
        // as in HyprSync; else Hyprland's, converted from pixels.
        const pos = Monitors.placePhysical(list.map(i => i.key), list) ?? Layout.relayout(list.map(i => ({
                        x: i.lx,
                        y: i.ly,
                        w: i.pxNow.w,
                        h: i.pxNow.h,
                        W: i.w,
                        H: i.h
                    })), 2);
        items = list.map((i, n) => Object.assign(i, {
                x: pos[n].x,
                y: pos[n].y
            }));
        dirty = false;
    }

    function bounds(list: var): var {
        if (!list.length)
            return {
                x: 0,
                y: 0,
                w: 1,
                h: 1
            };
        const x1 = Math.min(...list.map(m => m.x)), y1 = Math.min(...list.map(m => m.y));
        const x2 = Math.max(...list.map(m => m.x + m.w)), y2 = Math.max(...list.map(m => m.y + m.h));
        return {
            x: x1,
            y: y1,
            w: x2 - x1,
            h: y2 - y1
        };
    }

    function fit(list: var): var {
        const b = bounds(list);
        const pad = Theme.sp(32);
        const f = Math.max(0.01, Math.min((width - pad * 2) / b.w, (height - pad * 2) / b.h));
        return {
            f,
            ox: (width - b.w * f) / 2 - b.x * f,
            oy: (height - b.h * f) / 2 - b.y * f
        };
    }

    // Best snap of a 1-D position against candidate positions within `threshold`.
    function nearest(value: real, candidates: var, threshold: real): var {
        let best = null;
        for (const c of candidates) {
            const d = Math.abs(c.pos - value);
            if (d <= threshold && (!best || d < best.d))
                best = {
                    d,
                    pos: c.pos,
                    guide: c.guide
                };
        }
        return best;
    }

    function snap(index: int, x: real, y: real): var {
        const a = items[index];
        const threshold = Theme.sp(12) / view.f;
        const xs = [], ys = [];
        items.forEach((o, i) => {
            if (i === index)
                return;
            // Flush against a side, edges aligned, centres aligned. `guide` is
            // where the line is drawn when that snap wins.
            xs.push({ pos: o.x + o.w, guide: o.x + o.w }, { pos: o.x - a.w, guide: o.x }, { pos: o.x, guide: o.x }, { pos: o.x + o.w - a.w, guide: o.x + o.w }, { pos: o.x + (o.w - a.w) / 2, guide: o.x + o.w / 2 });
            ys.push({ pos: o.y + o.h, guide: o.y + o.h }, { pos: o.y - a.h, guide: o.y }, { pos: o.y, guide: o.y }, { pos: o.y + o.h - a.h, guide: o.y + o.h }, { pos: o.y + (o.h - a.h) / 2, guide: o.y + o.h / 2 });
        });
        const sx = nearest(x, xs, threshold);
        const sy = nearest(y, ys, threshold);
        return {
            x: Math.round(sx ? sx.pos : x),
            y: Math.round(sy ? sy.pos : y),
            guides: {
                x: sx ? [sx.guide] : [],
                y: sy ? [sy.guide] : []
            }
        };
    }

    function overlaps(a: var, b: var): bool {
        return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
    }

    // Pushes a dropped monitor out of any monitor it overlaps, the shortest way.
    function separate(index: int): void {
        const list = items.slice();
        const a = Object.assign({}, list[index]);
        for (let pass = 0; pass < 8; pass++) {
            const other = list.find((o, i) => i !== index && overlaps(a, o));
            if (!other)
                break;
            const moves = [
                { x: other.x + other.w, y: a.y },
                { x: other.x - a.w, y: a.y },
                { x: a.x, y: other.y + other.h },
                { x: a.x, y: other.y - a.h }
            ];
            moves.sort((p, q) => Math.hypot(p.x - a.x, p.y - a.y) - Math.hypot(q.x - a.x, q.y - a.y));
            a.x = moves[0].x;
            a.y = moves[0].y;
        }
        list[index] = a;
        items = list;
    }

    function moveTo(index: int, x: real, y: real): void {
        const list = items.slice();
        list[index] = Object.assign({}, list[index], { x, y });
        items = list;
    }

    // Saves the millimetre arrangement as the layout of the connected
    // combination of monitors. HyprSync converts it to logical pixels at the
    // monitors' scales and applies it.
    function apply(): void {
        // Mirroring monitors aren't shown; they keep their saved place for
        // when they extend the desktop again. (Same coordinates as the saved
        // layout; HyprSync normalizes.)
        // In the arrangement of the current mode: real sizes or pixels
        // (Monitors.layoutKey).
        const key = Monitors.layoutKey;
        const layout = Object.assign({}, Monitors.profile?.[key] ?? {});
        for (const m of items)
            layout[m.key] = {
                x: m.x,
                y: m.y,
                w: m.w,
                h: m.h
            };
        const profiles = Object.assign({}, Config.display.profiles);
        profiles[Monitors.profileKey] = Object.assign({}, profiles[Monitors.profileKey] ?? {}, {
            [key]: layout
        });
        // Pixel positions from before millimetre layouts existed.
        delete profiles[Monitors.profileKey].monitors;
        Config.display.profiles = profiles;
        dirty = false;
        refreshTimer.restart();
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.rounding.large
        color: Theme.m3surfaceContainerHighest
    }

    // Snap guides.
    Repeater {
        model: root.guides.x

        Rectangle {
            required property real modelData

            x: root.view.ox + modelData * root.view.f
            width: 1
            height: root.height
            color: Theme.m3tertiary
        }
    }

    Repeater {
        model: root.guides.y

        Rectangle {
            required property real modelData

            y: root.view.oy + modelData * root.view.f
            height: 1
            width: root.width
            color: Theme.m3tertiary
        }
    }

    Repeater {
        model: root.items.length

        Rectangle {
            id: monitor

            required property int index
            readonly property var mon: root.items[index]
            readonly property bool active: root.dragging === index

            x: root.view.ox + mon.x * root.view.f
            y: root.view.oy + mon.y * root.view.f
            width: mon.w * root.view.f
            height: mon.h * root.view.f
            radius: Theme.rounding.small
            color: active ? Theme.m3primary : Theme.m3primaryContainer
            border.width: 2
            border.color: active ? Theme.m3primary : Theme.m3outline
            z: active ? 1 : 0

            // Settle into place after a drop instead of jumping.
            Behavior on x {
                enabled: !monitor.active
                Anim {
                    type: Anim.FastSpatial
                }
            }
            Behavior on y {
                enabled: !monitor.active
                Anim {
                    type: Anim.FastSpatial
                }
            }
            // Turns portrait/landscape smoothly when rotated.
            Behavior on width {
                enabled: !monitor.active
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
            Behavior on height {
                enabled: !monitor.active
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
            Behavior on color {
                CAnim {}
            }

            Column {
                anchors.centerIn: parent
                spacing: 2

                MaterialIcon {
                    visible: monitor.mon.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "star"
                    fill: true
                    size: Theme.size.titleSmall + 2
                    color: monitor.active ? Theme.m3onPrimary : Theme.m3onPrimaryContainer
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, monitor.width - Theme.sp(8))
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    text: monitor.mon.name
                    font.pixelSize: Theme.size.titleSmall
                    font.weight: Font.Medium
                    color: monitor.active ? Theme.m3onPrimary : Theme.m3onPrimaryContainer
                }

                // Details only when they fit; small monitors just show the name.
                StyledText {
                    visible: implicitWidth + Theme.sp(12) <= monitor.width && monitor.height > Theme.size.titleSmall * 3
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: `${monitor.mon.inches.toFixed(1)}″ · ${monitor.mon.px.w}×${monitor.mon.px.h}${monitor.mon.rotation ? ` · ${monitor.mon.rotation}°` : ""}`
                    font.pixelSize: Theme.size.labelMedium
                    color: monitor.active ? Theme.m3onPrimary : Theme.m3onPrimaryContainer
                    opacity: 0.8
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true

                onPressed: mouse => {
                    const p = mapToItem(root, mouse.x, mouse.y);
                    root.frozenView = root.view;
                    root.dragging = monitor.index;
                    root.dragStart = {
                        mx: p.x,
                        my: p.y,
                        x: monitor.mon.x,
                        y: monitor.mon.y
                    };
                }
                onPositionChanged: mouse => {
                    if (root.dragging !== monitor.index)
                        return;
                    const p = mapToItem(root, mouse.x, mouse.y);
                    const s = root.snap(monitor.index, root.dragStart.x + (p.x - root.dragStart.mx) / root.view.f, root.dragStart.y + (p.y - root.dragStart.my) / root.view.f);
                    root.guides = s.guides;
                    root.moveTo(monitor.index, s.x, s.y);
                }
                onReleased: {
                    const moved = monitor.mon.x !== root.dragStart.x || monitor.mon.y !== root.dragStart.y;
                    root.separate(monitor.index);
                    root.dragging = -1;
                    root.frozenView = null;
                    root.guides = {
                        x: [],
                        y: []
                    };
                    if (moved)
                        root.dirty = true;
                }
            }
        }
    }
}
