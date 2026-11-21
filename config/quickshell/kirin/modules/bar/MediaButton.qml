pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.modules.media
import qs.services

// What's playing, in the bar: a note; hovered, a card with the media player
// (the same as at the bottom right: modules/media/MediaCard.qml). The card
// at the bottom right goes away while this one is open: one card at a time.
// A click plays or pauses.
// Only when the player isn't pinned at the bottom right: with nothing over
// its place it's there already; with a window over it, it goes, and the
// note comes.
Item {
    id: root

    property real cardOffset: 0
    // The card stays within this item (the bar).
    property Item bounds: null

    visible: Config.media.enabled && Media.hasTrack && !Panels.mediaPinned
    implicitWidth: icon.restWidth
    implicitHeight: icon.restHeight

    // Its card on screen: the bottom right one steps aside.
    Binding {
        target: Panels
        property: "mediaCardOpen"
        value: card.open && root.visible
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: "music_note"
        fill: true
        size: Math.round(19 * Theme.fontScale)
        color: Media.playing ? Theme.m3onSurface : Theme.m3onSurfaceVariant
        opacity: Media.playing ? 1 : 0.6
        grow: card.open ? 1.1 : 1

        Behavior on color {
            CAnim {}
        }
        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        anchors.margins: -Theme.sp(8)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Media.playPause()
    }

    BarCard {
        id: card

        owner: root
        ownerHovered: mouse.containsMouse
        cardOffset: root.cardOffset
        bounds: root.bounds
        // The player is the card: no padding round it, its own height
        // (it grows when hovered, from the bottom).
        padding: 0
        animateHeight: false
        maxHeight: player.fullHeight
        centerHeight: player.restHeight

        MediaCard {
            id: player

            cardWidth: Theme.sp(420)
            radius: HyprLook.rounding
        }
    }
}
