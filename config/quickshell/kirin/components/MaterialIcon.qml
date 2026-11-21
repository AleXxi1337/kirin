import QtQuick
import qs.services

// Material Symbols glyph by ligature name, e.g. `text: "wallpaper"`.
Text {
    id: root

    property bool fill: false
    property int size: 24
    // Grown (e.g. 1.1 while its card is open). The glyph is drawn at the
    // grown size and `scale` only bridges the animation to it, so at rest
    // it's sharp, not a stretched texture.
    property real grow: 1
    property real shownGrow: grow

    Behavior on shownGrow {
        Anim {
            type: Anim.FastSpatial
        }
    }

    // Size at grow 1, for laying out: growing doesn't push the neighbours.
    property real restWidth: 0
    property real restHeight: 0
    // The size it's drawn at.
    readonly property int drawSize: Math.round(size * grow)
    readonly property bool resting: drawSize === size

    // From the font's size, not `resting`: that binding may not have caught
    // up yet when these change, and the grown size got taken for the rest.
    onImplicitWidthChanged: if (font.pixelSize === size)
        restWidth = implicitWidth
    onImplicitHeightChanged: if (font.pixelSize === size)
        restHeight = implicitHeight
    Component.onCompleted: {
        restWidth = implicitWidth;
        restHeight = implicitHeight;
        restY = y;
    }

    // Where the glyph's ink is centred (from the top) at rest. A grown
    // glyph's ink sits differently in its box (the font's line metrics
    // don't scale evenly), so it's moved back onto this centre.
    // Measured large (TextMetrics gives whole pixels) and scaled down.
    readonly property real inkCentre: baselineOffset + (ink.tightBoundingRect.y + ink.tightBoundingRect.height / 2) * drawSize / ink.font.pixelSize
    property real restInkCentre: 0
    // Taken from where the box actually is: anchors round its position as
    // it grows.
    property real restY: 0
    readonly property real inkShift: resting ? 0 : restY + restInkCentre - (y + inkCentre)

    onInkCentreChanged: if (font.pixelSize === size)
        restInkCentre = inkCentre
    onYChanged: if (font.pixelSize === size)
        restY = y

    transform: Translate {
        y: root.inkShift
    }

    TextMetrics {
        id: ink

        font.family: root.font.family
        font.pixelSize: 240
        font.variableAxes: ({ FILL: root.fill ? 1 : 0, opsz: 48, wght: 400 })
        text: root.text
    }

    color: Theme.m3onSurface
    font.family: Theme.font.icons
    font.pixelSize: drawSize
    // Unhinted: hinting snaps the outlines to whole pixels differently at
    // each size, which threw a grown glyph off its centre by a pixel.
    font.hintingPreference: Font.PreferNoHinting
    font.variableAxes: ({ FILL: fill ? 1 : 0, opsz: drawSize, wght: 400 })
    scale: size * shownGrow / drawSize
    // Filled symbols are drawn from overlapping outlines, which Qt's default
    // (distance field) text rendering leaves holes in; FreeType fills them.
    renderType: Text.NativeRendering
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
