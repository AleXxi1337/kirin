pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
import qs.components
import qs.services

// A tray app's icon (Tray): the theme's panel icon when there is one, light
// one-colour icons in the text colour, others greyscale until hovered.
Item {
    id: trayItem

    required property SystemTrayItem item
    property bool hovered: false

    implicitWidth: size
    implicitHeight: size

    // Tray icons are drawn for 16, 22 or 24 px; at sizes in between
    // they come out soft. 16: the theme has panel icons for it, and
    // big app pictures (64 px) scale down to it evenly.
    readonly property int size: 16
    readonly property int inset: 0

    // The icon theme's panel icon for the app, when it has one: drawn
    // for tray sizes, and monochrome like the rest of the bar (what
    // apps send is often a picture at some other size). Telegram's
    // icon names say when there's something unread ("attention").
    // Config: bar.trayIcons maps an app id to an icon name of choice.
    readonly property string themed: {
        const base = (item.id ?? "").toLowerCase().replace(/_status_icon(_\d+)?$/, "").replace(/desktop$/, "");
        const attention = /attention/.test(item.icon ?? "");
        const names = [(Config.bar.trayIcons ?? {})[item.id], attention ? `${base}-attention-panel` : "", `${base}-panel`];
        return names.find(n => n && Quickshell.iconPath(n, true) !== "") ?? "";
    }
    // A symbol of one's own for the app (~/.local/share/kirin/symbols,
    // "<id>-symbolic.svg"), as for the bar's workspaces: for apps whose
    // icon the theme lacks (Spotify). Drawn in the text colour.
    readonly property string ownSymbol: {
        const base = (item.id ?? "").toLowerCase();
        const path = base ? Symbols.find(`${base}-symbolic`) : "";
        const mine = `${Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"}/kirin/symbols/`;
        return path && path.startsWith(mine) ? path : "";
    }
    readonly property string source: themed ? `image://icon/${themed}` : ownSymbol ? `file://${ownSymbol}` : item.icon ?? ""
    // Themed icons ("image://icon/<name>") the theme lacks: a generic one.
    // Not those that come with their own folder ("?path=", Spotify's):
    // the theme can't tell, and the icon is there. Nor any the image
    // loads anyway.
    readonly property bool missing: {
        if (!source)
            return true;
        if (iconImage.status === Image.Ready)
            return false;
        const m = /^image:\/\/icon\/([^?]+)(\?path=)?/.exec(source);
        return !!m && !m[2] && Quickshell.iconPath(m[1], true) === "";
    }

    Image {
        id: iconImage

        anchors.fill: parent
        // One's own symbols are made like the bar's (a 22 px grid with a
        // margin round the shape): drawn at the bar's icon size, so the
        // shape comes out as big as the tray's other icons.
        anchors.margins: trayItem.ownSymbol ? -Math.round((Math.round(22 * Theme.fontScale) - trayItem.size) / 2) : trayItem.inset
        source: trayItem.source
        // Decoded at exactly the size drawn, in device pixels, so it
        // isn't scaled again (twice the size plus mipmaps blurred it).
        readonly property real dpr: trayItem.QsWindow.window?.devicePixelRatio ?? 1
        sourceSize: Qt.size(width * dpr, height * dpr)
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: false
    }

    // Light one-colour icons (Discord's, the theme's panel icons) are
    // made for dark panels and vanish on a light bar. Those are drawn
    // as a shape in the bar's text colour instead; others keep their
    // own look. Found by looking at the icon's pixels once loaded.
    property bool lightMono: false
    // Drawn as a shape in the text colour: those, and one's own symbols
    // (dark as made, they'd vanish on a dark bar otherwise).
    readonly property bool mono: lightMono || ownSymbol !== ""

    Canvas {
        id: probe

        readonly property string src: trayItem.source
        readonly property int side: 16

        width: side
        height: side
        opacity: 0
        renderStrategy: Canvas.Immediate

        function check(): void {
            if (!src)
                return;
            if (isImageLoaded(src))
                requestPaint();
            else
                loadImage(src);
        }

        onSrcChanged: check()
        Component.onCompleted: check()
        onImageLoaded: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, side, side);
            if (!isImageLoaded(src))
                return;
            ctx.drawImage(src, 0, 0, side, side);
            const d = ctx.getImageData(0, 0, side, side).data;
            let n = 0, light = 0, sat = 0;
            for (let i = 0; i < d.length; i += 4) {
                const a = d[i + 3] / 255;
                if (a < 0.5)
                    continue;
                const max = Math.max(d[i], d[i + 1], d[i + 2]), min = Math.min(d[i], d[i + 1], d[i + 2]);
                n++;
                light += (max + min) / 510;
                sat += (max - min) / 255;
            }
            trayItem.lightMono = n > 0 && light / n > 0.6 && sat / n < 0.15;
        }
    }

    MaterialIcon {
        visible: trayItem.missing
        anchors.centerIn: parent
        text: "apps"
        size: trayItem.size
        color: trayItem.hovered ? Theme.m3primary : Theme.m3onSurfaceVariant
    }

    // Light one-colour icons: their shape, in the text colour (the
    // accent on hover).
    Rectangle {
        id: ink

        anchors.fill: iconImage
        color: trayItem.hovered ? Theme.m3primary : Theme.m3onSurface
        visible: false
        layer.enabled: true

        Behavior on color {
            CAnim {}
        }
    }

    MultiEffect {
        visible: !trayItem.missing && trayItem.mono
        anchors.fill: iconImage
        source: ink
        maskEnabled: true
        maskSource: iconImage
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
        opacity: trayItem.hovered ? 1 : 0.85
        scale: trayItem.hovered ? 1.1 : 1

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    // Other icons: greyscale at rest, the app's own colours on hover.
    MultiEffect {
        visible: !trayItem.missing && !trayItem.mono
        anchors.fill: parent
        anchors.margins: trayItem.inset
        source: iconImage
        saturation: trayItem.hovered ? 0 : -1
        // No lift at rest: icons drawn on a dark square of their own
        // (Happ) turned into a light grey box on the bar.
        brightness: 0
        opacity: trayItem.hovered ? 1 : 0.85
        scale: trayItem.hovered ? 1.1 : 1

        Behavior on saturation {
            Anim {
                type: Anim.DefaultEffects
            }
        }
        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }
}
