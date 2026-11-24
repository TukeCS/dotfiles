#!/usr/bin/env bash
# Dotfiles installer: Hyprland + Waybar + rofi + ghostty + fastfetch + Firefox, black/white with moss green.
#   ./install.sh            install packages + link configs
#   ./install.sh --no-pkgs  only link configs
set -euo pipefail

DOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/.dotfiles-backup/$(date +%Y-%m-%d_%H-%M-%S)"
say()  { printf '\033[1;38;2;168;191;74m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

PKGS=(
  hyprland hyprpaper hyprlock xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  waybar rofi mako libnotify ghostty fastfetch
  grim slurp wl-clipboard brightnessctl playerctl
  pulsemixer bluetui networkmanager
  dolphin qt5ct qt6ct qt6-wayland breeze breeze-icons
  ttf-jetbrains-mono-nerd python ffmpeg
  firefox
)

install_pkgs() {
  say "Installing packages with pacman"
  sudo pacman -S --needed "${PKGS[@]}"
  if ! command -v asusctl >/dev/null; then
    warn "asusctl not found: the fan-profile module in Waybar needs it (ASUS laptops only)."
    warn "supergfxctl (AUR) is optional: the GPU module stays hidden without it."
  fi
}

# link SRC DEST: back up whatever is at DEST, then symlink
link() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then return; fi
    mkdir -p "$BACKUP/$(dirname "${dest#$HOME/}")"
    mv "$dest" "$BACKUP/${dest#$HOME/}"
  fi
  ln -s "$src" "$dest"
  echo "  linked ${dest/#$HOME/\~}"
}

link_configs() {
  say "Linking configs (old files go to ${BACKUP/#$HOME/\~})"
  local f
  while IFS= read -r -d '' f; do
    rel="${f#$DOT/config/}"
    case "$rel" in *.in) continue ;; esac
    link "$f" "$HOME/.config/$rel"
  done < <(find "$DOT/config" -type f -print0)

  link "$DOT/local/bin/screenshot" "$HOME/.local/bin/screenshot"
  link "$DOT/local/share/color-schemes/Monochrome.colors" "$HOME/.local/share/color-schemes/Monochrome.colors"
  link "$DOT/home/bashrc" "$HOME/.bashrc"

  # Firefox theme: link into the profile Firefox actually uses
  local ffdir="$HOME/.config/mozilla/firefox" ffprof=""
  [ -d "$ffdir" ] || ffdir="$HOME/.mozilla/firefox"
  if [ -f "$ffdir/installs.ini" ]; then
    ffprof="$(grep -m1 '^Default=' "$ffdir/installs.ini" | cut -d= -f2-)"
  fi
  [ -n "$ffprof" ] || ffprof="$(cd "$ffdir" 2>/dev/null && ls -d *.default-release 2>/dev/null | head -1)"
  if [ -n "$ffprof" ] && [ -d "$ffdir/$ffprof" ]; then
    link "$DOT/firefox/user.js"                "$ffdir/$ffprof/user.js"
    link "$DOT/firefox/chrome/userChrome.css"  "$ffdir/$ffprof/chrome/userChrome.css"
    link "$DOT/firefox/chrome/userContent.css" "$ffdir/$ffprof/chrome/userContent.css"
  else
    warn "No Firefox profile found: start Firefox once, then rerun ./install.sh --no-pkgs"
  fi

  # qt5ct/qt6ct need an absolute path, so they are generated rather than linked
  for q in qt5ct qt6ct; do
    [ -e "$HOME/.config/$q/$q.conf" ] && { mkdir -p "$BACKUP/.config/$q"; cp "$HOME/.config/$q/$q.conf" "$BACKUP/.config/$q/"; }
    sed "s|@HOME@|$HOME|g" "$DOT/config/$q/$q.conf.in" > "$HOME/.config/$q/$q.conf"
    echo "  wrote ~/.config/$q/$q.conf"
  done

  chmod +x "$DOT/local/bin/screenshot" "$DOT"/config/waybar/scripts/*.sh
}

extras() {
  mkdir -p "$HOME/Pictures/Screenshots" "$HOME/Pictures/Wallpapers"
  command -v kwriteconfig6 >/dev/null && kwriteconfig6 --file dolphinrc --group UiSettings --key ColorScheme Monochrome || true
  command -v gsettings >/dev/null && gsettings set org.gnome.desktop.interface color-scheme prefer-dark || true
  if [ ! -f "$HOME/Pictures/Wallpapers/wallpaper.jpg" ]; then
    warn "No wallpaper yet: put an image at ~/Pictures/Wallpapers/wallpaper.jpg"
  fi
}

[ "${1:-}" = "--no-pkgs" ] || install_pkgs
link_configs
extras
say "Done. Log out and back in (or run: hyprctl reload; pkill waybar; waybar &)"
