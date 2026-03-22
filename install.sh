#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PACKAGES=(
	hyprland
	hyprlang
	hyprshot
	hyprlock
	cava
	kitty
	swaylock-effects
	waybar
	rofi
	otf-font-awesome
	lsd
	wlogout
	bat
	fprintd
	zsh
	waypaper
	swww
	brightnessctl
	ttf-jetbrains-mono-nerd
	ttf-cascadia-code-nerd
	whitesur-gtk-theme
	docker
	xdg-desktop-portal-hyprland
	xdg-desktop-portal-gtk
	swaync
	nwg-look
	oh-my-posh
	tela-icon-theme
	btop
	blueman
	hypridle
	cliphist
	wl-clip-persist
	pamixer
	nautilus
)

log() {
	printf "%s\n" "$1"
}

success() {
	printf "\033[32m%s\033[0m\n" "$1"
}

warn() {
	printf "\033[31m%s\033[0m\n" "$1"
}

ask_yes_no() {
	local prompt="$1"
	local default_answer="${2:-y}"
	local answer

	while true; do
		if [[ "$default_answer" == "y" ]]; then
			read -r -p "$prompt [Y/n]: " answer
			answer="${answer:-y}"
		else
			read -r -p "$prompt [y/N]: " answer
			answer="${answer:-n}"
		fi

		case "$answer" in
			[Yy]|[Yy][Ee][Ss]) return 0 ;;
			[Nn]|[Nn][Oo]) return 1 ;;
			*) warn "Invalid, Type Y or N." ;;
		esac
	done
}

copy_dotfiles() {
	log "Copying Dotfiles..."

	mkdir -p "$HOME/.config"

    cp -r "$SCRIPT_DIR/.config/." "$HOME/.config/"

	success "Copy Successfull"
}

copy_wallpaper()  {
    log "Copying Wallpaper..."

    mkdir -p "$HOME/Pictures"
    mkdir -p "$HOME/Pictures/Wallpaper"

    cp -r "$SCRIPT_DIR/wallpaper/." "$HOME/Pictures/Wallpaper/"

    success "Copy Successfull"
}

copy_shell() {
    log "Copying Shell Prompt..."

    mkdir -p "$HOME/.zsh"
	mkdir -p "$HOME/.config"

    cp .zshrc "$HOME/"
    cp oh-my-posh.toml "$HOME/.config/"
    git clone https://github.com/zsh-users/zsh-autosuggestions
    mv "$SCRIPT_DIR/zsh-autosuggestions/" "$HOME/.zsh/"
    git clone https://github.com/zsh-users/zsh-completions
    mv  "$SCRIPT_DIR/zsh-completions/" "$HOME/.zsh/"
    git clone https://github.com/zsh-users/zsh-syntax-highlighting
    mv "$SCRIPT_DIR/zsh-syntax-highlighting/" "$HOME/.zsh/"
	sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

    success "Copy Successfull"
}

install_packages() {
	local -a install_cmd

	if command -v yay >/dev/null 2>&1; then
		install_cmd=(yay -S --noconfirm --needed)
	else
		warn "Yay packet manager not found, install it to continue further"
        warn "-> https://github.com/jguer/yay"
		return 1
	fi

	log "Downloading package."
	"${install_cmd[@]}" "${PACKAGES[@]}"
	success "Download Successfull."
}



log "Sarting Installation of My Dotfiles"

# -------------- PACKAGE --------------

if ask_yes_no "Install required package ?" y; then
	install_packages || warn "Installation of package failed."
else
    if ask_yes_no "Dotfiles may not work properly without required package. Install required package ?" y; then
    	install_packages || warn "Installation of package failed."
    else
	    warn "Installation of package ignored."
    fi
fi

# -------------- DOTFILES --------------

if ask_yes_no "Copy Dotfiles in ur system (Carefull may delete ur current files) ?" y; then
	copy_dotfiles
else
	warn "Copy of Dotfiles ignored."
fi

# -------------- SHELL PROMPT --------------

if ask_yes_no "Copy Shell Prompt ?" y; then
    copy_shell
else
    warn "Copy of Shell Prompt ignored."
fi

# -------------- WALLPAPER --------------

if ask_yes_no "Copy Wallpaper in Pictures Dir ?" y; then
    copy_wallpaper
else
    warn "Copy of Wallpaper ignored."
fi

log "Installation ended."
