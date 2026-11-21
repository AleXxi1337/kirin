pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Window decoration settings of Hyprland (gaps, border, rounding, shadow), so
// shell surfaces that look like windows (bar, launcher, cards) match them. Read again whenever
// the Hyprland config reloads.
Singleton {
    id: root

    // Outer gaps in logical px.
    property int gapsTop: 10
    property int gapsRight: 10
    property int gapsBottom: 10
    property int gapsLeft: 10
    property int borderSize: 1
    property int rounding: 16

    // decoration:shadow
    property bool shadowEnabled: true
    property int shadowRange: 25
    property int shadowRenderPower: 3
    property bool shadowSharp: false
    property color shadowColor: "#30000000"
    // Falls back to shadowColor when not set in Hyprland.
    property color shadowColorInactive: shadowColor
    property point shadowOffset: Qt.point(0, 4)
    property real shadowScale: 1

    // How far a shadow reaches past its surface, for sizing windows.
    readonly property real shadowExtent: shadowEnabled ? Math.ceil(shadowRange * shadowScale + Math.max(Math.abs(shadowOffset.x), Math.abs(shadowOffset.y))) : 0

    // "30000000 0deg" (Hyprland gradient, AARRGGBB) → "#30000000".
    function gradientColor(o: var): var {
        const hex = /^([0-9a-fA-F]{8})/.exec((o.gradient ?? "").trim());
        return hex ? `#${hex[1]}` : null;
    }

    function refresh(): void {
        if (proc.running)
            proc.again = true;
        else
            proc.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: proc

        property bool again: false

        // One JSON object per line.
        command: ["sh", "-c", "for o in general:gaps_out general:border_size decoration:rounding decoration:shadow:enabled decoration:shadow:range decoration:shadow:render_power decoration:shadow:sharp decoration:shadow:color decoration:shadow:color_inactive decoration:shadow:offset decoration:shadow:scale; do hyprctl getoption $o -j | tr -d '\\n'; echo; done"]
        onRunningChanged: {
            if (!running && again) {
                again = false;
                running = true;
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    try {
                        const o = JSON.parse(line);
                        if (o.option === "general:gaps_out") {
                            // css: "top right bottom left"
                            const g = (o.css ?? "").trim().split(/\s+/).map(Number);
                            if (g.length === 4 && g.every(n => n >= 0))
                                [root.gapsTop, root.gapsRight, root.gapsBottom, root.gapsLeft] = g;
                        } else if (o.option === "general:border_size") {
                            root.borderSize = o.int;
                        } else if (o.option === "decoration:rounding") {
                            root.rounding = o.int;
                        } else if (o.option === "decoration:shadow:enabled") {
                            root.shadowEnabled = o.bool;
                        } else if (o.option === "decoration:shadow:range") {
                            root.shadowRange = o.int;
                        } else if (o.option === "decoration:shadow:render_power") {
                            root.shadowRenderPower = o.int;
                        } else if (o.option === "decoration:shadow:sharp") {
                            root.shadowSharp = o.bool;
                        } else if (o.option === "decoration:shadow:color") {
                            root.shadowColor = root.gradientColor(o) ?? root.shadowColor;
                        } else if (o.option === "decoration:shadow:color_inactive") {
                            const c = o.set ? root.gradientColor(o) : null;
                            if (c)
                                root.shadowColorInactive = c;
                            else
                                root.shadowColorInactive = Qt.binding(() => root.shadowColor);
                        } else if (o.option === "decoration:shadow:offset") {
                            if (o.vec2?.length === 2)
                                root.shadowOffset = Qt.point(o.vec2[0], o.vec2[1]);
                        } else if (o.option === "decoration:shadow:scale") {
                            root.shadowScale = o.float;
                        }
                    } catch (e) {}
                }
            }
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "configreloaded")
                root.refresh();
        }
    }
}
