#!/bin/sh
# Cleans the wallpaper caches: copies (wallpaper-scale.sh,
# wallpaper-shrink.sh) and thumbnails (wallpaper-thumbs.sh) no longer
# needed. Kept: those of wallpapers in the folder or given, pictures at the
# given canvas sizes, shrunk videos at those sizes with the given settings.
# Copies that came out the same become hard links. Prints the bytes freed
# and the bytes saved by linking.
#
#   wallpaper-gc.sh <copies dir> <thumbnail dir> <folder> "<WxH> ..." <res-fps> [wallpaper...]
#
# Used by services/Wallpaper.qml and `kirin cache --clean`.

scaled=$1 thumbs=$2 dir=$3 sizes=$4 params=$5; shift 5
keep=$(mktemp); trap 'rm -f "$keep"' EXIT
{ for f in "$dir"/* "$@"; do [ -n "$f" ] && [ -e "$f" ] && printf %s "$f" | md5sum | cut -c1-32; done; } | sort -u > "$keep"
# Keeping nothing would mean the folder is gone or unreadable: leave all.
[ -s "$keep" ] || exit 0
freed=0
drop() { freed=$((freed + $(stat -c %s "$1" 2>/dev/null || echo 0))); rm -f "$1"; }
for f in "$scaled"/*; do
    [ -f "$f" ] || continue
    b=${f##*/}
    case "$b" in
    *.tmp.*) [ -n "$(find "$f" -mmin +30)" ] && drop "$f"; continue ;;
    esac
    h=${b%%-*}; rest=${b#*-}
    grep -qx "$h" "$keep" || { drop "$f"; continue; }
    case "$b" in
    *.jpg) size=${rest%.jpg}
        case " $sizes " in *" $size "*) ;; *) drop "$f" ;; esac ;;
    *.mp4) p=${rest%.mp4}; size=${p%%-*}
        case " $sizes " in *" $size "*) [ "${p#*-}" = "$params" ] || drop "$f" ;; *) drop "$f" ;; esac ;;
    esac
done
for f in "$thumbs"/*.jpg; do
    [ -f "$f" ] || continue
    b=${f##*/}
    grep -qx "${b%.jpg}" "$keep" || drop "$f"
done
# Same picture under several sizes: one file, hard links.
linked=0
while read -r h; do
    set -- "$scaled/$h"-*.jpg
    [ $# -gt 1 ] && [ -f "$1" ] || continue
    first=$1; sum=$(md5sum < "$first"); shift
    for f in "$@"; do
        [ "$f" -ef "$first" ] && continue
        [ "$(md5sum < "$f")" = "$sum" ] && { linked=$((linked + $(stat -c %s "$f"))); ln -f "$first" "$f"; }
    done
done < "$keep"
echo "$freed $linked"
