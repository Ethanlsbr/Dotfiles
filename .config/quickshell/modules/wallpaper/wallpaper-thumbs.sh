#!/bin/sh
# Generate small thumbnails for the wallpaper grid so the settings selector
# doesn't have to decode full-resolution (often multi-MB) images per cell.
#
# Usage: wallpaper-thumbs.sh <wallpaper-dir> <cache-dir> [width]
#
# Thumb naming mirrors the source basename (unique within one folder) with a
# .jpg suffix, e.g. "alya02.png" -> "<cache>/alya02.png.jpg". Only missing or
# stale (source newer than thumb) thumbnails are regenerated, so re-runs are
# cheap stat checks.

SRC="$1"
CACHE="$2"
SIZE="${3:-400}"

[ -d "$SRC" ] || exit 0
mkdir -p "$CACHE" || exit 1

find "$SRC" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
       -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \) \
| while IFS= read -r f; do
    thumb="$CACHE/$(basename "$f").jpg"
    if [ ! -f "$thumb" ] || [ "$f" -nt "$thumb" ]; then
        # Only animated formats need the [0] first-frame selector; using it on
        # PNG/JPG trips an ImageMagick decode error. -thumbnail strips metadata
        # and resizes fast.
        case "$f" in
            *.gif|*.GIF|*.webp|*.WEBP) src="$f[0]" ;;
            *)                         src="$f"    ;;
        esac
        magick "$src" -auto-orient -thumbnail "${SIZE}x" -strip "$thumb" 2>/dev/null
    fi
done
