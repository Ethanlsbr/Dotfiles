#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
ASSUME_YES=0

PACKAGES=(
	# Hyprland
	hyprland
	hypridle
	hyprshot
	xdg-desktop-portal-hyprland
	xdg-desktop-portal-gtk
	polkit-kde-agent

	# Shell
	quickshell-git
	awww-git
	cava
	python
	zenity
	imagemagick
	curl
	pciutils
	upower
	libnotify
	xdg-utils

	# Audio / media
	pipewire
	pipewire-pulse
	wireplumber
	pamixer
	pavucontrol
	playerctl

	# Network / bluetooth
	networkmanager
	blueman
	bluez
	bluez-utils

	# Hardware
	brightnessctl
	fprintd

	# Clipboard
	cliphist
	wl-clip-persist
	wl-clipboard

	# Apps
	kitty
	nautilus
	zen-browser-bin
	neovim
	btop
	docker
	gnome-keyring

	# Theme / fonts
	nwg-look
	whitesur-gtk-theme
	tela-icon-theme
	otf-font-awesome
	ttf-jetbrains-mono-nerd
	ttf-cascadia-code-nerd

	# Terminal
	git
	zsh
	oh-my-posh
	fastfetch
	lsd
	bat
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

	if (( ASSUME_YES )); then
		return 0
	fi

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

# Move an existing file/dir into BACKUP_DIR (keeping its path relative to $HOME)
backup() {
	local target="$1"
	local rel="${target#"$HOME"/}"

	[[ -e "$target" || -L "$target" ]] || return 0

	mkdir -p "$BACKUP_DIR/$(dirname -- "$rel")"
	mv -- "$target" "$BACKUP_DIR/$rel"
	log "Backed up $target -> $BACKUP_DIR/$rel"
}

install_yay() {
	log "Installing yay..."

	sudo pacman -S --needed --noconfirm git base-devel

	local tmp
	tmp="$(mktemp -d)"
	git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
	(cd "$tmp/yay-bin" && makepkg -si --noconfirm)
	rm -rf "$tmp"

	success "yay installed."
}

install_packages() {
	if ! command -v yay >/dev/null 2>&1; then
		warn "Yay package manager not found."
		if ask_yes_no "Install yay now ?" y; then
			install_yay || return 1
		else
			warn "-> https://github.com/Jguer/yay"
			return 1
		fi
	fi

	log "Installing packages..."
	yay -S --noconfirm --needed "${PACKAGES[@]}"
	success "Packages installed."
}

copy_dotfiles() {
	log "Copying Dotfiles..."

	mkdir -p "$HOME/.config"

	local src name
	for src in "$SCRIPT_DIR/.config"/* "$SCRIPT_DIR/.config"/.[!.]*; do
		[[ -e "$src" ]] || continue
		name="$(basename -- "$src")"

		# Editor settings for this repo, not a real config
		[[ "$name" == ".vscode" ]] && continue

		# Replace instead of merging so files removed from the repo don't linger
		backup "$HOME/.config/$name"
		cp -r -- "$src" "$HOME/.config/$name"
	done

	find "$HOME/.config/hypr" "$HOME/.config/quickshell" -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
	find "$HOME/.config/hypr" "$HOME/.config/quickshell" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +

	success "Copy Successful."
}

copy_wallpaper() {
	log "Copying Wallpaper..."

	# Quickshell reads wallpapers from ~/Pictures/wallpaper
	mkdir -p "$HOME/Pictures/wallpaper" "$HOME/Pictures/Screenshots"
	cp -r -- "$SCRIPT_DIR/wallpaper/." "$HOME/Pictures/wallpaper/"

	success "Copy Successful."
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

	mkdir -p "$HOME/.zsh" "$HOME/.config"

	if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
		local omz_installer
		omz_installer="$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
		RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$omz_installer"
	else
		log "Oh My Zsh already installed, skipping."
	fi

	backup "$HOME/.zshrc"
	cp -- "$SCRIPT_DIR/.zshrc" "$HOME/.zshrc"
	cp -- "$SCRIPT_DIR/oh-my-posh.toml" "$HOME/.config/oh-my-posh.toml"

	clone_plugin https://github.com/zsh-users/zsh-autosuggestions zsh-autosuggestions
	clone_plugin https://github.com/zsh-users/zsh-completions zsh-completions
	clone_plugin https://github.com/zsh-users/zsh-syntax-highlighting zsh-syntax-highlighting

	local zsh_path
	zsh_path="$(command -v zsh || true)"
	if [[ -n "$zsh_path" && "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh_path" ]]; then
		if ask_yes_no "Set zsh as default shell ?" y; then
			chsh -s "$zsh_path" || warn "Could not change default shell."
		fi
	fi

	success "Copy Successful."
}

enable_services() {
	log "Enabling services..."

	local service
	for service in NetworkManager bluetooth; do
		if systemctl list-unit-files "$service.service" >/dev/null 2>&1; then
			sudo systemctl enable --now "$service.service" || warn "Could not enable $service."
		else
			warn "$service not installed, skipping."
		fi
	done

	success "Services enabled."
}

usage() {
	printf "Usage: %s [-y|--yes]\n" "$(basename -- "$0")"
	printf "  -y, --yes   Answer yes to every prompt\n"
}

while (( $# )); do
	case "$1" in
		-y|--yes) ASSUME_YES=1 ;;
		-h|--help) usage; exit 0 ;;
		*) usage; exit 1 ;;
	esac
	shift
done

if [[ $EUID -eq 0 ]]; then
	warn "Do not run this script as root, it will ask for sudo when needed."
	exit 1
fi

if ! command -v pacman >/dev/null 2>&1; then
	warn "pacman not found, these dotfiles are only meant for Arch based distros."
	exit 1
fi

log "Starting Installation of My Dotfiles"

# -------------- PACKAGE --------------

if ask_yes_no "Install required packages ?" y; then
	install_packages || warn "Installation of packages failed."
else
	if ask_yes_no "Dotfiles may not work properly without required packages. Install required packages ?" y; then
		install_packages || warn "Installation of packages failed."
	else
		warn "Installation of packages ignored."
	fi
fi

# -------------- SERVICES --------------

if ask_yes_no "Enable NetworkManager and Bluetooth services ?" y; then
	enable_services
else
	warn "Services ignored."
fi

# -------------- DOTFILES --------------

if ask_yes_no "Copy Dotfiles in ur system (existing configs are backed up to $BACKUP_DIR) ?" y; then
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

if [[ -d "$BACKUP_DIR" ]]; then
	log "Previous files were backed up to $BACKUP_DIR"
fi

log "Installation ended. Log out and back in (or reboot) to start Hyprland."
