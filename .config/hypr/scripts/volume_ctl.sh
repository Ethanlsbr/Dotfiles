#!/usr/bin/env bash

# You can call this script like this:
# $ ./volumeControl.sh up
# $ ./volumeControl.sh down
# $ ./volumeControl.sh mute

# Script modified from these wonderful people:
# https://github.com/dastorm/volume-notification-dunst/blob/master/volume.sh
# https://gist.github.com/sebastiencs/5d7227f388d93374cebdf72e783fbd6a

function get_volume {
  volume=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | head -n 1 | awk -F'/' '{print $2}' | tr -d ' %')
  echo "${volume:-0}"
}

function is_mute {
  amixer get Master | grep '%' | grep -oE '[^ ]+$' | grep off > /dev/null
}

function send_notification {
  iconSound="audio-volume-high"
  iconMuted="audio-volume-muted"
  if is_mute ; then
    notify-send -i $iconSound -r 2593 -u normal "|$bar$space| $volume%"
  else
    volume=$(get_volume)
    # Make the bar with the special character ─ (it's not dash -)
    # https://en.wikipedia.org/wiki/Box-drawing_character
    bar=$(seq --separator="─" 0 "$(((volume > 0 ? volume - 1 : 0) / 4))" | sed 's/[0-9]//g')
    space=$(seq --separator=" " 0 "$(((100 - volume) / 4))" | sed 's/[0-9]//g')
    # Send the notification
    notify-send -i $iconSound -r 2593 -u normal "|$bar$space| $volume%"
  fi
}

case $1 in
  up)
    # set the volume on (if it was muted)
    amixer -D pipewire set Master on > /dev/null
    # up the volume (+ 5%)
    pactl set-sink-volume @DEFAULT_SINK@ +5% > /dev/null
    send_notification
    ;;
  down)
    amixer -D pipewire set Master on > /dev/null
    pactl set-sink-volume @DEFAULT_SINK@ -5% > /dev/null
    send_notification
    ;;
  mute)
    # toggle mute
    amixer -D pipewire set Master 1+ toggle > /dev/null
    send_notification
    ;;
esac