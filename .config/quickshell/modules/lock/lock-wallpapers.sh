#!/bin/sh
# Screen-sized copies of each output's current wallpaper for the lockscreen,
# so locking decodes a ~1 MB JPEG instead of the (often huge) original.
#
# Usage: lock-wallpapers.sh <cache-dir>
# Prints "<output>\t<image>" per output: the cached copy, or the original if
# scaling failed. Copies are only rebuilt when missing or older than the
# source, so runs at lock time are just stat checks.

CACHE="$1"
mkdir -p "$CACHE" || exit 1

# ": eDP-1: 1920x1200, scale: 1, currently displaying: image: /path"
awww query 2>/dev/null \
| sed -nE 's/^[: ]*([^: ]+): ([0-9]+)x([0-9]+),.*image: *(.+)$/\1\t\2\t\3\t\4/p' \
| while IFS="$(printf '\t')" read -r out w h img; do
    [ -f "$img" ] || continue
    name="$out@${w}x${h}@$(basename "$img").jpg"
    dst="$CACHE/$name"
    if [ ! -f "$dst" ] || [ "$img" -nt "$dst" ]; then
        case "$img" in
            *.gif|*.GIF|*.webp|*.WEBP) src="$img[0]" ;;
            *)                         src="$img"    ;;
        esac
        # Cover-crop to the output so nothing is rescaled at lock time.
        magick "$src" -auto-orient -resize "${w}x${h}^" -gravity center \
            -extent "${w}x${h}" -strip -quality 92 "$dst.tmp" 2>/dev/null \
            && mv -f "$dst.tmp" "$dst" || { rm -f "$dst.tmp"; dst="$img"; }
    fi
    # Drop this output's copies of previous wallpapers.
    find "$CACHE" -maxdepth 1 -name "$out@*" ! -name "$name" -delete
    printf '%s\t%s\n' "$out" "$dst"
done
