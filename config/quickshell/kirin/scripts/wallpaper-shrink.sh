#!/bin/sh
# A video wallpaper shrunk for playback (Settings -> Wallpaper -> Animated
# wallpapers): copied once to the size that covers the screens, at most
# `pixels` pixels and `maxfps` frames a second (H.264, decoded in hardware).
#
#   wallpaper-shrink.sh <video> <copy> <WxH> <pixels> <maxfps> <make: 0|1>
#
# Tab-separated lines, each naming its copy:
#   info <copy> w h fps copyW copyH copyFps
#   ok <copy>: the copy is there; orig <copy>: none needed;
#   busy <copy>: being made (then ok); skip <copy>: needed, but not made
#   now (make=0: only looked at).
# Used by services/Wallpaper.qml.

src=$1 dst=$2 W=${3%x*} H=${3#*x} pixels=$4 maxfps=$5 make=$6
say() { printf '%s\t%s' "$1" "$dst"; shift; for x; do printf '\t%s' "$x"; done; printf '\n'; }
mkdir -p "$(dirname "$dst")"
IFS=x; set -- $(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate -of csv=p=0:s=x "$src"); unset IFS
w=${1:-0} h=${2:-0} r=${3:-0/1}
[ "$w" -gt 0 ] && [ "$h" -gt 0 ] || { say orig; exit; }
set -- $(awk -v w="$w" -v h="$h" -v W="$W" -v H="$H" -v P="$pixels" -v r="$r" -v F="$maxfps" 'BEGIN {
    split(r, q, "/"); fps = (q[2] > 0) ? q[1] / q[2] : 0
    a = w / h
    # Covering the screens, in the shape of the video.
    cw = (W / H > a) ? W : H * a; ch = cw / a
    # No more pixels than the resolution picked.
    if (cw * ch > P) { k = sqrt(P / (cw * ch)); cw *= k; ch *= k }
    # Never enlarged.
    if (cw > w) { cw = w; ch = h }
    tf = (fps > 0 && fps < F) ? fps : F
    printf "%d %d %d %d %d", int(cw / 2) * 2, int(ch / 2) * 2, int(fps + 0.5), int(tf + 0.5), (cw < w * 0.97 || fps > F + 0.5) ? 1 : 0
}')
tw=$1 th=$2 fps=$3 tf=$4 need=$5
if [ "$need" = 1 ]; then say info "$w" "$h" "$fps" "$tw" "$th" "$tf"; else say info "$w" "$h" "$fps" "$w" "$h" "$fps"; fi
[ "$need" = 1 ] || { say orig; exit; }
[ "$dst" -nt "$src" ] && { say ok; exit; }
[ "$make" = 1 ] || { say skip; exit; }
say busy
# Stopped (settings changed): ffmpeg and its half-made file go too.
nice -n 19 ffmpeg -v error -y -i "$src" -an -vf "scale=$tw:$th:flags=lanczos" -fpsmax "$maxfps" -c:v libx264 -preset veryfast -crf 21 -pix_fmt yuv420p -movflags +faststart "$dst.tmp.mp4" &
pid=$!
trap 'kill $pid 2>/dev/null; wait $pid; rm -f "$dst.tmp.mp4"; exit 1' TERM
wait $pid && mv "$dst.tmp.mp4" "$dst" && say ok
