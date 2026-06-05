#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PACKAGES=(
	hyprland
	hyprlock
	hypridle
	hyprshot
	quickshell-git
	cava
	kitty
	nautilus
	zen-browser-bin
	awww-git
	pipewire
	wireplumber
	pamixer
	playerctl
	brightnessctl
	cliphist
	wl-clip-persist
	wl-clipboard
	polkit-kde-agent
	xdg-desktop-portal-hyprland
	xdg-desktop-portal-gtk
	libnotify
	blueman
	bluez
	bluez-utils
	fprintd
	nwg-look
	whitesur-gtk-theme
	tela-icon-theme
	otf-font-awesome
	ttf-jetbrains-mono-nerd
	ttf-cascadia-code-nerd
	zsh
	oh-my-posh
	fastfetch
	lsd
	bat
	btop
	neovim
	imagemagick
	docker
	gnome-keyring
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

clone_plugin() {
    local url="$1"
    local dest="$HOME/.zsh/$2"

    if [[ -d "$dest" ]]; then
        log "$2 already present, skipping clone."
    else
        git clone --depth=1 "$url" "$dest"
    fi
}

copy_shell() {
    log "Copying Shell Prompt..."

    mkdir -p "$HOME/.zsh"
	mkdir -p "$HOME/.config"

    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    else
        log "Oh My Zsh already installed, skipping."
    fi

    cp "$SCRIPT_DIR/.zshrc" "$HOME/"
    cp "$SCRIPT_DIR/oh-my-posh.toml" "$HOME/.config/"

    clone_plugin https://github.com/zsh-users/zsh-autosuggestions zsh-autosuggestions
    clone_plugin https://github.com/zsh-users/zsh-completions zsh-completions
    clone_plugin https://github.com/zsh-users/zsh-syntax-highlighting zsh-syntax-highlighting

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



log "Starting Installation of My Dotfiles"

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
