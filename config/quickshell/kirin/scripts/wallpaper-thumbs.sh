#!/bin/sh
# The wallpaper picker's list and thumbnails (960x540, cropped; a video's
# first frame), made when missing or older than the file.
#
#   wallpaper-thumbs.sh <folder> <thumbnail dir>
#
# Prints "F<tab>file" for each wallpaper, then "E", then per file
# "T<tab>file<tab>thumbnail" (or "X<tab>file" if it couldn't be made).
# Used by modules/launcher/WallpaperGrid.qml.

dir=$1 cache=$2
mkdir -p "$cache"
list=$(fd . "$dir" --type f --follow -e jpg -e jpeg -e png -e webp -e bmp -e gif -e mp4 -e m4v -e webm -e mkv -e mov | sort)
[ -n "$list" ] || exit 0
printf '%s\n' "$list" | while IFS= read -r f; do printf 'F\t%s\n' "$f"; done
echo E
printf '%s\n' "$list" | while IFS= read -r f; do
    t="$cache/$(printf %s "$f" | md5sum | cut -c1-32).jpg"
    if [ ! "$t" -nt "$f" ]; then
        # A video: its first frame.
        case "$f" in
            *.mp4|*.MP4|*.m4v|*.webm|*.mkv|*.mov|*.MOV) ffmpeg -v error -y -i "$f" -frames:v 1 -vf "scale=960:540:force_original_aspect_ratio=increase:flags=lanczos,crop=960:540" -q:v 2 "$t.tmp.jpg" ;;
            *) magick "$f[0]" -auto-orient -thumbnail '960x540^' -gravity center -extent 960x540 -strip -quality 90 "$t.tmp.jpg" 2>/dev/null ;;
        esac && mv "$t.tmp.jpg" "$t" || { rm -f "$t.tmp.jpg"; printf 'X\t%s\n' "$f"; continue; }
    fi
    printf 'T\t%s\t%s\n' "$f" "$t"
done
