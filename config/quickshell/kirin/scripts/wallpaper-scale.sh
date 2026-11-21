#!/bin/sh
# A wallpaper's copy at the screens' size: a picture scaled down to cover
# it (never enlarged); a video, its first frame covering it. A high quality
# JPEG, quick to load. Prints "ok" once it's there (made now or before).
#
#   wallpaper-scale.sh <wallpaper> <copy.jpg> <WxH>
#
# Used by services/Wallpaper.qml.

src=$1 dst=$2 size=$3
mkdir -p "$(dirname "$dst")" || exit 1
if [ ! "$dst" -nt "$src" ]; then
    case "$src" in
    *.mp4|*.MP4|*.m4v|*.webm|*.mkv|*.mov|*.MOV)
        ffmpeg -v error -y -i "$src" -frames:v 1 -vf "scale=${size%x*}:${size#*x}:force_original_aspect_ratio=increase:flags=lanczos" -q:v 2 "$dst.tmp.jpg" ;;
    *)
        magick "$src[0]" -auto-orient -resize "$size^>" -strip -quality 92 -sampling-factor 4:4:4 "$dst.tmp.jpg" ;;
    esac && mv "$dst.tmp.jpg" "$dst" || { rm -f "$dst.tmp.jpg"; exit 1; }
fi
echo ok
