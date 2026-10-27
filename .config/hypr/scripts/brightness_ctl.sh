#!/bin/bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Script for Monitor backlights (if supported) using brightnessctl

iDIR="$HOME/.config/swaync/icons"
notification_timeout=1000

# Get brightness
get_backlight() {
	echo $(brightnessctl -m | cut -d, -f4)
}

# Get icons
get_icon() {
	current=$(get_backlight | sed 's/%//')
	if   [ "$current" -le "20" ]; then
		icon="$iDIR/brightness-20.png"
	elif [ "$current" -le "40" ]; then
		icon="$iDIR/brightness-40.png"
	elif [ "$current" -le "60" ]; then
		icon="$iDIR/brightness-60.png"
	elif [ "$current" -le "80" ]; then
		icon="$iDIR/brightness-80.png"
	else
		icon="$iDIR/brightness-100.png"
	fi
}

# Notify
notify_user() {
	notify-send -e -h string:x-canonical-private-synchronous:brightness_notif -h int:value:$current -u low -i "$icon" "Brightness : $current%"
}

# Set brightness to an absolute percentage (clamped to 1..100, never 0 → black)
set_backlight() {
	local target="$1"
	[ "$target" -lt 1 ]   && target=1
	[ "$target" -gt 100 ] && target=100
	brightnessctl set "${target}%" && get_icon && notify_user
}

# Step to the next/previous multiple of 10 (e.g. 55 → 60 → 70 up, 55 → 50 → 40 down)
step_backlight() {
	local cur next
	cur=$(get_backlight | sed 's/%//')
	if [ "$1" = "inc" ]; then
		next=$(( (cur / 10 + 1) * 10 ))
	else
		# round up to the next multiple of 10, then drop one step
		next=$(( ( (cur + 9) / 10 - 1) * 10 ))
	fi
	set_backlight "$next"
}

# Execute accordingly
case "$1" in
	"--get")
		get_backlight
		;;
	"--inc")
		step_backlight inc
		;;
	"--dec")
		step_backlight dec
		;;
	*)
		get_backlight
		;;
esac