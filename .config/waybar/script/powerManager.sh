
#!/usr/bin/env bash

if ! command -v powerprofilesctl >/dev/null 2>&1; then
    notify-send "Erreur" "powerprofilesctl non trouvé"
    exit 1
fi

# Liste des profils
options="performance\nbalanced\npower-saver"

# Profil actuel
current=$(powerprofilesctl get)

# Menu rofi (dmenu mode)
choice=$(echo -e "$options" | rofi -dmenu -p "Power profile (current: $current)")

# Si vide → quitter
[ -z "$choice" ] && exit 0

# Appliquer le profil
powerprofilesctl set "$choice"

# Notification
notify-send "Power profile" "Profile changed to → $choice"
