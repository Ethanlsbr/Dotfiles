#!/usr/bin/env bash

APP_DIRS=(
    /usr/share/applications
    ~/.local/share/applications
)

declare -A CMDS

while IFS= read -r file; do
    name=$(grep -m1 "^Name=" "$file" | cut -d= -f2-)
    exec_cmd=$(grep -m1 "^Exec=" "$file" | cut -d= -f2-)

    exec_cmd=$(echo "$exec_cmd" | sed 's/%.//g')

    if [[ -n "$name" && -n "$exec_cmd" ]]; then
        CMDS["$name"]="$exec_cmd"
    fi
done < <(find "${APP_DIRS[@]}" -type f -name "*.desktop" 2>/dev/null)

choice=$(printf '%s\n' "${!CMDS[@]}" | sort | rofi -dmenu -i -p "Launch with Arc")

[ -z "$choice" ] && exit 0

DRI_PRIME=1 ${CMDS[$choice]} &
