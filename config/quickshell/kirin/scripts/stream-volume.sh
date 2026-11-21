#!/bin/sh
# Keeps every app's playback stream at full "volume" (the stream's own
# multiplier, apart from the per-channel volume mixers show and move): some
# apps (Spotify) start theirs at 0.01, so they play at 1% while everything
# shows 100%. Watches PipeWire and sets it back to 1.0 on each new or
# changed stream below it; prints "<id> <was> <app>" for each. Left alone:
# kirin's own sounds and pw-play/pw-cat, whose --volume is this multiplier.
#
# Used by services/StreamVolume.qml. Each part goes when this script does
# (--pdeathsig): kirin killed, nothing's left running.

setpriv --pdeathsig TERM pw-dump --monitor --no-colors |
    setpriv --pdeathsig TERM jq --unbuffered -r '
        .[]? | select(type == "object" and .type == "PipeWire:Interface:Node")
        | select(.info.props["media.class"]? == "Stream/Output/Audio")
        | select(.info.props["application.name"]? as $a | ["kirin-sounds", "pw-play", "pw-cat"] | index($a) | not)
        | (.info.params.Props[0].volume? // 1) as $v
        | select($v < 0.999)
        | "\(.id) \($v) \(.info.props["application.name"] // "?")"' |
    while read -r id volume app; do
        # PipeWire tells the old value a few times before the new one takes:
        # once per stream (and again only if it's lowered later).
        [ "$id $volume" = "$last" ] && continue
        last="$id $volume"
        pw-cli set-param "$id" Props '{ volume: 1.0 }' >/dev/null 2>&1 && echo "$id $volume $app"
    done
