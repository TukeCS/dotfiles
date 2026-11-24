#!/usr/bin/env bash
# Dotfiles installer: Ly + Hyprland + Waybar + rofi + ghostty + fastfetch + Firefox, black/white with moss green.
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
  pulsemixer bluetui networkmanager btop less
  dolphin qt5ct qt6ct qt6-wayland breeze breeze-icons
  ttf-jetbrains-mono-nerd python ffmpeg
  firefox ly neovim
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

# Ly (login screen) reads /etc/ly as root, so its files are copied there instead of linked.
# The background is generated from the wallpaper; rerun ./install.sh --no-pkgs after changing it.
install_ly() {
  local tmp f changed=0 wall="$HOME/Pictures/Wallpapers/wallpaper.jpg"
  tmp="$(mktemp -d)"
  cp "$DOT/system/ly/config.ini" "$DOT/system/ly/startup.sh" "$tmp/"
  if [ -f "$wall" ] && command -v ffmpeg >/dev/null; then
    python3 "$DOT/system/ly/make-ly-art.py" "$wall" "$tmp" >/dev/null
  else
    warn "No wallpaper (or ffmpeg): Ly gets a plain black background"
    sed -i 's/^animation = .*/animation = none/' "$tmp/config.ini"
  fi
  if [ ! -d /etc/ly ]; then
    warn "ly not installed: skipping the login screen theme"
    rm -rf "$tmp"; return
  fi
  for f in "$tmp"/*; do
    cmp -s "$f" "/etc/ly/${f##*/}" || changed=1
  done
  if [ "$changed" = 1 ]; then
    say "Installing the Ly theme to /etc/ly (needs sudo)"
    for f in config.ini startup.sh; do
      [ -e "/etc/ly/$f" ] && sudo cp "/etc/ly/$f" "/etc/ly/$f.bak"
    done
    for f in "$tmp"/*; do
      case "$f" in *.sh) sudo install -m 755 "$f" /etc/ly/ ;; *) sudo install -m 644 "$f" /etc/ly/ ;; esac
    done
  fi
  rm -rf "$tmp"
  if ! systemctl is-enabled --quiet 'ly@tty2.service' 2>/dev/null; then
    warn "Ly is not enabled. To use it: sudo systemctl disable getty@tty2 && sudo systemctl enable ly@tty2"
  fi
}

extras() {
  mkdir -p "$HOME/Pictures/Screenshots" "$HOME/Pictures/Wallpapers"
  command -v kwriteconfig6 >/dev/null && kwriteconfig6 --file dolphinrc --group UiSettings --key ColorScheme Monochrome || true
  # Kdenlive picks its own colour scheme (BreezeDark by default); point it at ours
  command -v kwriteconfig6 >/dev/null && kwriteconfig6 --file kdenliverc --group UiSettings --key ColorScheme Monochrome || true
  command -v gsettings >/dev/null && gsettings set org.gnome.desktop.interface color-scheme prefer-dark || true
  if [ ! -f "$HOME/Pictures/Wallpapers/wallpaper.jpg" ]; then
    warn "No wallpaper yet: put an image at ~/Pictures/Wallpapers/wallpaper.jpg"
  fi
}

[ "${1:-}" = "--no-pkgs" ] || install_pkgs
link_configs
install_ly
extras
say "Done. Log out and back in (or run: hyprctl reload; pkill waybar; waybar &)"
