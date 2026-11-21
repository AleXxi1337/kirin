pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Qt.labs.qmlmodels
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.services

// Vertical bar on the left of the primary monitor (Settings → Display),
// floating like a window: Hyprland's outer gaps around it, its rounding and
// border (HyprLook). The gap to the screen edge still belongs to the bar, so
// the cursor pushed against the edge reaches it.
// Top: the distribution's logo (click: the session menu). Bottom: the clock.
Variants {
    // Recreated on the new primary monitor when it changes.
    model: Quickshell.screens.filter(s => s.name === Monitors.primary?.name)

    PanelWindow {
        id: bar

        required property ShellScreen modelData

        // Width of the bar itself, without the gap around it.
        readonly property int barWidth: Theme.sp(56)
        // Space between the bar's ends and its contents.
        // Fixed: the module gap (Settings → Bar) and the spacing setting
        // don't move the bar's ends.
        readonly property int padding: 22

        // The edge gap plus the bar: what's reserved and takes input.
        readonly property int reserved: HyprLook.gapsLeft + barWidth

        screen: modelData
        color: "transparent"
        // Room on the right for the shadow, which windows may cover.
        implicitWidth: reserved + HyprLook.shadowExtent
        // Hyprland adds its outer gap after the reserved zone, so windows end
        // up as far from the bar as from each other.
        exclusiveZone: reserved
        mask: Region {
            width: bar.reserved
            height: bar.height
        }

        WlrLayershell.namespace: "kirin-bar"
        WlrLayershell.layer: WlrLayer.Top

        anchors {
            top: true
            bottom: true
            left: true
        }

        WindowShadow {
            target: panel
        }

        // 0 … 1 as the bar slides off to the left before the lock screen
        // (and back after it). The reserved zone stays, so windows don't
        // resize under it.
        property real away: Panels.locking ? 1 : 0

        Behavior on away {
            NumberAnimation {
                duration: 420
                easing.type: Panels.locking ? Easing.InCubic : Easing.OutCubic
            }
        }

        Rectangle {
            id: panel

            x: HyprLook.gapsLeft - bar.away * (bar.barWidth + HyprLook.gapsLeft + HyprLook.shadowExtent + 8)
            y: HyprLook.gapsTop
            width: bar.barWidth
            height: bar.height - HyprLook.gapsTop - HyprLook.gapsBottom
            radius: HyprLook.rounding
            color: Theme.m3surface
            // Like an inactive window's border (hypr/modules/colors.lua).
            border.width: HyprLook.borderSize
            border.color: Qt.alpha(Theme.m3outlineVariant, 0x66 / 255)

            Behavior on color {
                CAnim {}
            }

            // The distribution's logo as a Nerd Font glyph (by ID= in
            // /etc/os-release), so it's sharp at any size. Drawn in the text
            // colour; on hover it grows and fades into a gradient of the two
            // accent colours.
            FileView {
                id: osRelease

                path: "/etc/os-release"
                readonly property string id: /^ID="?([^"\n]*)"?$/m.exec(text())?.[1] ?? ""
                // Derivatives (CachyOS, Pop!_OS, Zorin…) name their parents here.
                readonly property var like: (/^ID_LIKE="?([^"\n]*)"?$/m.exec(text())?.[1] ?? "").split(" ").filter(x => x)
            }

            Item {
                id: logo

                // Nerd Fonts "linux" glyphs; Tux for anything else.
                readonly property var glyphs: ({
                        nixos: "\uf313",
                        arch: "\uf303",
                        debian: "\uf306",
                        fedora: "\uf30a",
                        gentoo: "\uf30d",
                        linuxmint: "\uf30e",
                        manjaro: "\uf312",
                        opensuse: "\uf314",
                        "opensuse-tumbleweed": "\uf314",
                        ubuntu: "\uf31b",
                        alpine: "\uf300",
                        endeavouros: "\uf322",
                        void: "\uf32e"
                    })
                readonly property string glyph: glyphs[osRelease.id] ?? osRelease.like.map(x => glyphs[x]).find(g => g) ?? "\uf17c"
                // Lit while its menu is open too (and kept its size, which the
                // card is placed by).
                readonly property bool hovered: logoMouse.containsMouse || power.open
                // Any installed Nerd Font has the glyphs; the symbols-only one first.
                readonly property string fontFamily: {
                    const families = Qt.fontFamilies();
                    return ["Symbols Nerd Font", "Symbols Nerd Font Mono"].find(f => families.includes(f)) ?? families.find(f => / Nerd Font( Propo)?$/.test(f)) ?? "";
                }

                // Grows by its real size, not `scale`, so the glyph is redrawn sharp.
                readonly property real base: Math.round(22 * Theme.fontScale)
                property real grow: hovered ? 1.35 : 1
                // 0 → text colour, 1 → gradient.
                property real tint: hovered ? 1 : 0

                // Grows around its centre.
                anchors.top: parent.top
                anchors.topMargin: bar.padding - (width - base) / 2
                anchors.horizontalCenter: parent.horizontalCenter
                width: base * grow
                height: width

                Behavior on grow {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }
                Behavior on tint {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                // Centred by the glyph's ink, not its advance and line box: Nerd
                // Font logos sit off-centre in those.
                component Glyph: Text {
                    id: glyph

                    TextMetrics {
                        id: ink

                        font: glyph.font
                        text: glyph.text
                    }
                    FontMetrics {
                        id: metrics

                        font: glyph.font
                    }

                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: implicitWidth / 2 - (ink.tightBoundingRect.x + ink.tightBoundingRect.width / 2)
                    anchors.verticalCenterOffset: implicitHeight / 2 - (metrics.ascent + ink.tightBoundingRect.y + ink.tightBoundingRect.height / 2)
                    text: logo.glyph
                    font.family: logo.fontFamily
                    font.pixelSize: logo.width
                }

                // Plain: native text rendering, as sharp as text gets.
                Glyph {
                    color: Theme.m3onSurface
                    opacity: 1 - logo.tint
                }

                // Hover: the gradient cut out by the glyph's shape.
                // Same size as the gradient, so the mask lines up with it.
                Item {
                    id: logoMask

                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    // Supersampled, so the cut-out edges stay smooth.
                    layer.textureSize: Qt.size(width * 4, height * 4)
                    layer.smooth: true

                    Glyph {}
                }

                Rectangle {
                    id: logoFill

                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: Theme.m3primary
                        }
                        GradientStop {
                            position: 1
                            color: Theme.m3tertiary
                        }
                    }
                }

                MultiEffect {
                    anchors.fill: parent
                    visible: logo.tint > 0
                    opacity: logo.tint
                    source: logoFill
                    maskEnabled: true
                    maskSource: logoMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }

                // From the screen's corner to a bit below the logo, so it
                // also reacts with the cursor pushed into the corner.
                MouseArea {
                    id: logoMouse

                    x: -logo.x - panel.x
                    y: -logo.y - panel.y
                    width: bar.reserved
                    height: panel.y + logo.y + logo.height + Theme.sp(8)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: power.toggle()
                }

                // Click: the session menu (lock, suspend, reboot, shut down).
                PowerMenu {
                    id: power

                    owner: logo
                    ownerHovered: logoMouse.containsMouse
                    cardOffset: (bar.barWidth - logo.width) / 2 + HyprLook.gapsLeft
                    bounds: panel
                }
            }

            // Middle: the workspaces, centred, kept clear of the logo and of
            // the modules below (past that they scroll inside).
            // In windows mode (WindowMode): the taskbar in their place.
            Item {
                id: middle

                anchors.fill: parent

                readonly property real room: {
                    const gap = Theme.sp(24);
                    const above = parent.height / 2 - (logo.y + logo.base) - gap;
                    // Follows the controls plate growing: it doesn't run
                    // into the workspaces, they make room (scrolling).
                    const below = bottomModules.y - parent.height / 2 - gap;
                    return Math.max(0, 2 * Math.min(above, below));
                }

                Workspaces {
                    visible: !WindowMode.windows
                    anchors.centerIn: parent
                    maxHeight: middle.room
                }

                Taskbar {
                    visible: WindowMode.windows
                    // On whole pixels (centring could put it between two).
                    x: Math.round((parent.width - width) / 2)
                    y: Math.round((parent.height - height) / 2)
                    maxHeight: middle.room
                    cardOffset: (bar.barWidth - width) / 2 + HyprLook.gapsLeft
                    bounds: panel
                }
            }

            // Bottom: the modules (notifications, tray, brightness, sound,
            // network, Bluetooth, battery, keyboard layout, clock) in the
            // order set in Settings → Bar.
            Column {
                id: bottomModules

                anchors.bottom: parent.bottom
                anchors.bottomMargin: bar.padding
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Config.bar.moduleSpacing

                Repeater {
                    model: BarModules.rows

                    delegate: DelegateChooser {
                        DelegateChoice {
                            roleValue: "controls"

                            Controls {
                                anchors.horizontalCenter: parent?.horizontalCenter
                                barWidth: bar.barWidth
                                bounds: panel
                            }
                        }

                        DelegateChoice {
                            roleValue: "tray"

                            Tray {
                                anchors.horizontalCenter: parent?.horizontalCenter
                                cardOffset: (bar.barWidth - width) / 2 + HyprLook.gapsLeft
                                bounds: panel
                            }
                        }

                        DelegateChoice {
                            roleValue: "brightness"

                            Brightness {
                                anchors.horizontalCenter: parent?.horizontalCenter
                                cardOffset: (bar.barWidth - width) / 2 + HyprLook.gapsLeft
                                bounds: panel
                            }
                        }

                        DelegateChoice {
                            roleValue: "volume"

                            Volume {
                                anchors.horizontalCenter: parent?.horizontalCenter
                                cardOffset: (bar.barWidth - width) / 2 + HyprLook.gapsLeft
                                bounds: panel
                            }
                        }

                        DelegateChoice {
                            roleValue: "wifi"

                            Wifi {
                                anchors.horizontalCenter: parent?.horizontalCenter
                                cardOffset: (bar.barWidth - width) / 2 + HyprLook.gapsLeft
                                bounds: panel
                            }
                        }

                        DelegateChoice {
                            roleValue: "bluetooth"

                            Bluetooth {
                                anchors.horizontalCenter: parent?.horizontalCenter
                                cardOffset: (bar.barWidth - width) / 2 + HyprLook.gapsLeft
                                bounds: panel
                            }
                        }

                        DelegateChoice {
                            roleValue: "battery"

                            Battery {
                                anchors.horizontalCenter: parent?.horizontalCenter
                                cardOffset: (bar.barWidth - width) / 2 + HyprLook.gapsLeft
                                bounds: panel
                            }
                        }

                        DelegateChoice {
                            roleValue: "clock"

                            Clock {
                                anchors.horizontalCenter: parent?.horizontalCenter
                                cardOffset: (bar.barWidth - width) / 2 + HyprLook.gapsLeft
                                bounds: panel
                            }
                        }

                        DelegateChoice {
                            roleValue: "notifications"

                            Notifications {
                                anchors.horizontalCenter: parent?.horizontalCenter
                                cardOffset: (bar.barWidth - width) / 2 + HyprLook.gapsLeft
                                bounds: panel
                            }
                        }

                        DelegateChoice {
                            roleValue: "media"

                            MediaButton {
                                anchors.horizontalCenter: parent?.horizontalCenter
                                cardOffset: (bar.barWidth - width) / 2 + HyprLook.gapsLeft
                                bounds: panel
                            }
                        }

                        DelegateChoice {
                            roleValue: "keyboard"

                            Keyboard {
                                anchors.horizontalCenter: parent?.horizontalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
