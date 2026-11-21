pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.components
import qs.services

// The cover is the card's background, darkened towards the bottom
// for the text. Over it: the source badge (top left); the title and
// artist with play/pause across from them; under them a thin
// progress line with the arrows at its sides. Hovered, the button
// and the arrows come and the line seeks; it stays thin.
ClippingRectangle {
    id: card

    // Its width; the height is its own (it grows when hovered).
    property real cardWidth: Theme.sp(480)
    // The pointer on it: the controls show.
    readonly property bool pointerIn: hover.hovered

    readonly property real padding: Theme.sp(22)
    readonly property real restHeight: Theme.sp(172)
    // Hovered, it grows upwards (the bottom stays put).
    readonly property real fullHeight: Theme.sp(210)
    // 0 at rest … 1 hovered: the controls.
    property real shown: pointerIn ? 1 : 0
    // The song shown: changes with its cover, once that has loaded,
    // so a new title isn't on the old picture. Shown at once with
    // no cover to wait for (none, or it failed).
    property string shownTitle: ""
    property string shownArtist: ""
    property bool hasArt: false

    function takeTrack(): void {
        if (settleTrack.running)
            return;
        const loading = Media.art !== "" && (art.status === Image.Loading || art.status === Image.Null || String(art.source) !== Media.art);
        if (loading)
            return;
        shownTitle = Media.title;
        shownArtist = Media.artist;
        hasArt = Media.art !== "" && art.status === Image.Ready;
        show(Media.art, Media.title, Media.artist, hasArt);
        if (hasArt)
            palette.look(Media.art);
        else {
            accent = "#ffffff";
            accentEnd = "#ffffff";
            accentInk = "#000000";
            accentInkEnd = "#000000";
        }
    }

    // A song's title and cover come as separate updates, either
    // first: taken once both have come, not the title with the
    // old cover (then the cover swapped in unloaded).
    Connections {
        target: Media

        function onTrackKeyChanged(): void {
            settleTrack.restart();
        }

        function onArtChanged(): void {
            settleTrack.restart();
        }
    }

    Timer {
        id: settleTrack

        interval: 150
        onTriggered: card.takeTrack()
    }

    Connections {
        target: art

        function onStatusChanged(): void {
            card.takeTrack();
        }
    }

    Component.onCompleted: takeTrack()

    // The controls in the cover's colour: its most colourful one,
    // light enough for the darkened cover; white for a grey cover.
    // Taken with the cover (takeTrack), so they change together.
    // The cover's pixels (Quickshell's ColorQuantizer reads local
    // files only; covers come over https): drawn small on a hidden
    // canvas, looked at once per cover.
    Canvas {
        id: palette

        readonly property int side: 32
        property string src: ""
        // [{ h, s, l, weight }] of the cover's colourful pixels.
        property var colours: []

        width: side
        height: side
        visible: false
        renderStrategy: Canvas.Immediate

        function look(url: string): void {
            src = url;
            if (!url)
                return;
            if (isImageLoaded(url))
                requestPaint();
            else
                loadImage(url);
        }

        onImageLoaded: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, side, side);
            if (!src || !isImageLoaded(src))
                return;
            ctx.drawImage(src, 0, 0, side, side);
            const d = ctx.getImageData(0, 0, side, side).data;
            const out = [];
            for (let i = 0; i < d.length; i += 4) {
                const c = Qt.rgba(d[i] / 255, d[i + 1] / 255, d[i + 2] / 255, 1);
                out.push({
                    h: c.hslHue,
                    s: c.hslSaturation,
                    l: c.hslLightness
                });
            }
            colours = out;
            if (src === Media.art && card.hasArt)
                card.takeColours();
        }
    }

    property color accent: "#ffffff"
    // The colour at the song's end: the cover's next one. The
    // controls go from one to the other as the song plays.
    property color accentEnd: "#ffffff"
    property color accentInkEnd: "#000000"
    // Where the song is (0 … 1), and the colours there.
    readonly property real progress: Math.max(0, Math.min(1, Media.position / Math.max(1, Media.length)))
    readonly property color tintNow: mix(accent, accentEnd, progress)
    readonly property color tintInkNow: mix(accentInk, accentInkEnd, progress)
    // What the controls show: follows, smoothed, so a new song (its
    // colours, and the position back to the start) flows over.
    property color tint: tintNow
    property color tintInk: tintInkNow

    Behavior on tint {
        ColorAnimation {
            duration: 700
            easing.type: Easing.InOutCubic
        }
    }
    Behavior on tintInk {
        ColorAnimation {
            duration: 700
            easing.type: Easing.InOutCubic
        }
    }
    // Dark, the accent's hue: on the accent (the play button).
    property color accentInk: "#000000"

    Behavior on accent {
        CAnim {}
    }
    Behavior on accentEnd {
        CAnim {}
    }

    Behavior on accentInkEnd {
        CAnim {}
    }

    function mix(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }
    Behavior on accentInk {
        CAnim {}
    }

    function takeColours(): void {
        // Pixels by hue (12 buckets), each counting by how colourful
        // it is; the strongest hue wins, its average colour taken.
        const buckets = [];
        for (let i = 0; i < 12; i++)
            buckets.push({ weight: 0, s: 0, h: 0 });
        let total = 0;
        for (const c of palette.colours) {
            total++;
            if (c.h < 0 || c.l < 0.12 || c.l > 0.94 || c.s < 0.15)
                continue;
            const w = c.s * (1 - Math.abs(c.l - 0.55));
            const b = buckets[Math.floor(c.h * 12) % 12];
            b.weight += w;
            b.s += c.s * w;
            b.h += c.h * w;
        }
        const best = buckets.reduce((a, b) => b.weight > a.weight ? b : a);
        // Hardly any colour: white.
        if (!total || best.weight < total * 0.03) {
            accent = "#ffffff";
            accentEnd = "#ffffff";
            accentInk = "#000000";
            accentInkEnd = "#000000";
            return;
        }
        const h = best.h / best.weight, sat = best.s / best.weight;
        accent = Qt.hsla(h, Math.min(1, Math.max(sat, 0.5)), 0.74, 1);
        accentInk = Qt.hsla(h, Math.min(1, sat), 0.14, 1);
        // The next strongest hue, well apart from the first (two
        // buckets or more); none: the same, its hue turned a bit.
        const bi = buckets.indexOf(best);
        let second = null;
        buckets.forEach((b, i) => {
            const apart = Math.min(Math.abs(i - bi), 12 - Math.abs(i - bi));
            if (apart >= 2 && b.weight >= best.weight * 0.12 && (!second || b.weight > second.weight))
                second = b;
        });
        const h2 = second ? second.h / second.weight : (h + 0.12) % 1;
        const s2 = second ? second.s / second.weight : sat;
        accentEnd = Qt.hsla(h2, Math.min(1, Math.max(s2, 0.5)), 0.74, 1);
        accentInkEnd = Qt.hsla(h2, Math.min(1, s2), 0.14, 1);
    }

    // Light text over the darkened cover (or the plain card).
    readonly property color ink: "#ffffff"
    readonly property color inkDim: Qt.rgba(1, 1, 1, 0.72)

    Behavior on shown {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    width: cardWidth
    implicitWidth: cardWidth
    implicitHeight: height
    height: restHeight + (fullHeight - restHeight) * shown
    radius: Theme.rounding.card
    color: Theme.m3surfaceContainerHighest

    HoverHandler {
        id: hover
    }

    // No cover: a note on the plain card.
    MaterialIcon {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.sp(14)
        visible: !card.front.hasCover
        text: "music_note"
        fill: true
        size: Math.round(card.height * 0.45)
        color: Theme.m3onSurfaceVariant
        opacity: 0.25
    }

    // Loads the next cover (not shown): the song changes once it's
    // there. The pages show it from the cache, at the same size.
    Image {
        id: art

        readonly property size coverSize: Qt.size(Math.round(card.cardWidth * 2), Math.round(card.cardWidth * 2))

        width: 1
        height: 1
        opacity: 0
        source: Media.art
        sourceSize: coverSize
        asynchronous: true
    }

    // A song's cover with its title and artist; two of them, so the
    // old one slides out as the new one slides in.
    component Page: Item {
        id: page

        property string cover: ""
        property string title: ""
        property string artist: ""
        property bool hasCover: false
        // Its cover is in (or there's none to wait for): it may
        // slide in.
        readonly property bool ready: !hasCover || picture.status === Image.Ready || picture.status === Image.Error

        width: card.width
        height: card.height

        Image {
            id: picture

            anchors.fill: parent
            source: page.hasCover ? page.cover : ""
            sourceSize: art.coverSize
            fillMode: Image.PreserveAspectCrop
            // Covers come over https: loaded in the background
            // whatever this says; the slide waits for it (ready).
            asynchronous: true
            smooth: true
        }

        // Dark from the middle down, a little all over.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.rgba(0, 0, 0, page.hasCover ? 0.15 : 0)
                }
                GradientStop {
                    position: 0.45
                    color: Qt.rgba(0, 0, 0, page.hasCover ? 0.3 : 0)
                }
                GradientStop {
                    position: 1
                    color: Qt.rgba(0, 0, 0, page.hasCover ? 0.78 : 0.35)
                }
            }
        }

        // Where the title goes (textSlot, next to the play button).
        Column {
            x: textSlot.x + texts.x
            y: textSlot.y + texts.y
            width: texts.width
            spacing: texts.spacing

            StyledText {
                width: parent.width
                text: page.title
                font.pixelSize: Theme.size.titleMedium
                font.weight: Font.Bold
                color: card.ink
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: page.artist
                font.pixelSize: Theme.size.bodyMedium
                color: card.inkDim
                elide: Text.ElideRight
            }
        }
    }

    // The pages in a layer of their own: which is on top of the
    // other (z) stays among them, under the controls.
    Item {
        anchors.fill: parent

        Page {
            id: pageA
        }

        Page {
            id: pageB

            opacity: 0
        }
    }

    // The page on show; the other one waits off to the side.
    property Item front: pageA

    // A new song: the other page gets it and fades in over the shown
    // one. The first one (or a cover changing on the same song) just
    // shows.
    function show(cover: string, title: string, artist: string, hasCover: bool): void {
        const same = front.title === title && front.artist === artist && front.cover === cover && front.hasCover === hasCover;
        // Back to what's on show before the waiting one came in.
        if (same && pending) {
            giveUp.stop();
            pending = null;
        }
        // The first song: shown as is. The same song with another
        // cover crossfades like a new one (its cover loaded first).
        if (!front.title || same) {
            slide.complete();
            Object.assign(front, { cover, title, artist, hasCover });
            return;
        }
        slide.complete();
        const back = front === pageA ? pageB : pageA;
        // Hidden, its cover loads; it fades in once it has (go()),
        // or after a while without it.
        back.opacity = 0;
        Object.assign(back, { cover, title, artist, hasCover });
        pending = back;
        if (back.ready)
            go();
        else
            giveUp.restart();
    }

    // The page waiting for its cover.
    property Item pending: null

    function go(): void {
        giveUp.stop();
        const back = pending;
        pending = null;
        if (!back || back === front)
            return;
        // Over the old one, it fades in and settles from a little
        // larger; then the old one goes.
        back.z = 1;
        front.z = 0;
        fadeIn.target = back;
        settle.target = back;
        fadeOut.target = front;
        front = back;
        slide.start();
    }

    Connections {
        target: card.pending

        function onReadyChanged(): void {
            if (card.pending?.ready)
                card.go();
        }
    }

    // The cover never came: in without it.
    Timer {
        id: giveUp

        interval: 5000
        onTriggered: card.go()
    }

    // The song change: a crossfade.
    SequentialAnimation {
        id: slide

        ParallelAnimation {
            NumberAnimation {
                id: fadeIn

                property: "opacity"
                from: 0
                to: 1
                duration: 600
                easing.type: Easing.InOutCubic
            }
            NumberAnimation {
                id: settle

                property: "scale"
                from: 1.06
                to: 1
                duration: 800
                easing.type: Easing.OutCubic
            }
        }
        NumberAnimation {
            id: fadeOut

            property: "opacity"
            to: 0
            duration: 0
        }
    }

    // Click on the picture: the player's window.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Media.raise()
    }

    // Where it plays: Spotify or a browser; nothing for others.
    Rectangle {
        visible: Media.source !== ""
        x: card.padding - Theme.sp(6)
        y: card.padding - Theme.sp(6)
        width: Theme.sp(36)
        height: width
        radius: width / 2
        color: Qt.rgba(0, 0, 0, 0.35)

        // Symbols are drawn with a margin (the shape about 3/4 of
        // the box): a box a little past the disc leaves the shape
        // close to its edge.
        SymbolIcon {
            anchors.centerIn: parent
            width: Math.round(parent.width * 1.08)
            height: width
            appId: Media.sourceApp
            entry: {
                DesktopEntries.applications.values;
                return DesktopEntries.heuristicLookup(Media.sourceApp);
            }
            // In the controls' colour, flowing with the song.
            color: card.tint
        }
    }

    // The progress line, with the arrows at its sides.
    Item {
        id: progressRow

        readonly property real arrow: Theme.sp(28)

        x: card.padding
        width: card.width - card.padding * 2
        height: arrow
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.sp(14)

        // Pressed it shrinks; clicked it jumps its way (-1 back,
        // 1 on) and springs back.
        component Arrow: Item {
            id: arrowButton

            required property string icon
            property int direction: 1
            property bool active: true
            signal clicked

            property real press: arrowMouse.pressed && active ? 0.78 : 1
            property real nudge: 0

            Behavior on press {
                NumberAnimation {
                    duration: arrowMouse.pressed ? 90 : 420
                    easing.type: arrowMouse.pressed ? Easing.OutCubic : Easing.OutBack
                    easing.overshoot: 3
                }
            }

            SequentialAnimation {
                id: jump

                NumberAnimation {
                    target: arrowButton
                    property: "nudge"
                    to: arrowButton.direction * Theme.sp(6)
                    duration: 90
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: arrowButton
                    property: "nudge"
                    to: 0
                    duration: 420
                    easing.type: Easing.OutBack
                    easing.overshoot: 2.5
                }
            }

            width: progressRow.arrow * card.shown
            height: progressRow.arrow
            opacity: card.shown * (active ? 1 : 0.38)
            visible: card.shown > 0.01
            // Only while it unfolds: the jump goes past its edge.
            clip: card.shown < 0.99

            MaterialIcon {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: arrowButton.nudge
                text: arrowButton.icon
                fill: true
                size: 22
                color: card.tint
                scale: arrowButton.press
            }

            MouseArea {
                id: arrowMouse

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!arrowButton.active)
                        return;
                    jump.restart();
                    arrowButton.clicked();
                }
            }
        }

        Arrow {
            id: prev

            anchors.left: parent.left
            icon: "skip_previous"
            direction: -1
            active: Media.player?.canGoPrevious ?? false
            onClicked: Media.previous()
        }

        Arrow {
            id: nextArrow

            anchors.right: parent.right
            icon: "skip_next"
            active: Media.player?.canGoNext ?? false
            onClicked: Media.next()
        }

        // Thin, hovered or not. Click or drag on it: seek.
        Item {
            id: line

            readonly property real ratio: Math.max(0, Math.min(1, (seekArea.pressed ? seekArea.at : Media.position) / Math.max(1, Media.length)))

            anchors.left: prev.right
            anchors.right: nextArrow.left
            anchors.leftMargin: Theme.sp(8) * card.shown
            anchors.rightMargin: Theme.sp(8) * card.shown
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            visible: Media.length > 0

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 3
                radius: 1.5
                color: Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.28)

                Rectangle {
                    width: parent.width * line.ratio
                    height: parent.height
                    radius: parent.radius
                    color: card.tint
                }
            }

            // Unfolded: a mark where it's at, to see where to drag.
            // Pressed it grows; let go (sought) it springs back.
            Rectangle {
                property real press: seekArea.pressed ? 1.5 : 1

                Behavior on press {
                    NumberAnimation {
                        duration: seekArea.pressed ? 100 : 420
                        easing.type: seekArea.pressed ? Easing.OutCubic : Easing.OutBack
                        easing.overshoot: 3
                    }
                }

                anchors.verticalCenter: parent.verticalCenter
                x: Math.round(parent.width * line.ratio - width / 2)
                width: 3
                height: Math.round(Theme.sp(14) * card.shown * press)
                radius: 1.5
                color: card.tint
                opacity: card.shown
                visible: card.shown > 0.01
            }

            MouseArea {
                id: seekArea

                // Seconds under the pointer while pressed.
                property real at: 0

                anchors.fill: parent
                enabled: card.shown > 0.5 && (Media.player?.canSeek ?? false)
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                onPressed: mouse => at = Math.max(0, Math.min(1, mouse.x / width)) * Media.length
                onPositionChanged: mouse => at = Math.max(0, Math.min(1, mouse.x / width)) * Media.length
                onReleased: Media.seek(at)
            }
        }
    }

    // Title and artist, play/pause across from them. The text itself
    // is drawn by the pages (it slides with the cover); this lays
    // out where.
    Item {
        id: textSlot

        x: card.padding
        width: card.width - card.padding * 2
        height: Math.max(texts.implicitHeight, playButton.height)
        anchors.bottom: progressRow.top
        // Unfolded: more room above the line.
        anchors.bottomMargin: Theme.sp(2) + Theme.sp(26) * card.shown

        Column {
            id: texts

            opacity: 0
            anchors.left: parent.left
            anchors.right: playButton.left
            anchors.rightMargin: Theme.sp(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.sp(2)

            StyledText {
                width: parent.width
                text: card.shownTitle
                font.pixelSize: Theme.size.titleMedium
                font.weight: Font.Bold
                color: card.ink
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: card.shownArtist
                font.pixelSize: Theme.size.bodyMedium
                color: card.inkDim
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: playButton

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.sp(44)
            height: width
            radius: width / 2
            color: card.tint
            opacity: card.shown * ((Media.player?.canTogglePlaying ?? false) ? 1 : 0.38)
            // Pressed it sinks; let go it springs back past its size.
            property real press: playMouse.pressed ? 0.84 : 1
            scale: (0.8 + 0.2 * card.shown) * press
            visible: card.shown > 0.01

            Behavior on press {
                NumberAnimation {
                    duration: playMouse.pressed ? 90 : 460
                    easing.type: playMouse.pressed ? Easing.OutCubic : Easing.OutBack
                    easing.overshoot: 3.5
                }
            }

            // Clicked: a ring of its colour goes out from it.
            Rectangle {
                id: ring

                anchors.centerIn: parent
                width: parent.width
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: card.tint
                opacity: 0

                ParallelAnimation {
                    id: ripple

                    NumberAnimation {
                        target: ring
                        property: "scale"
                        from: 1
                        to: 1.7
                        duration: 520
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: ring
                        property: "opacity"
                        from: 0.7
                        to: 0
                        duration: 520
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // The other icon comes in with a pop.
            MaterialIcon {
                id: playIcon

                anchors.centerIn: parent
                text: Media.playing ? "pause" : "play_arrow"
                fill: true
                size: 26
                color: card.tintInk

                onTextChanged: pop.restart()

                NumberAnimation {
                    id: pop

                    target: playIcon
                    property: "scale"
                    from: 0.4
                    to: 1
                    duration: 380
                    easing.type: Easing.OutBack
                    easing.overshoot: 2.5
                }
            }

            MouseArea {
                id: playMouse

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    ripple.restart();
                    Media.playPause();
                }
            }
        }
    }
}
