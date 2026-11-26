#!/usr/bin/env bash
# Installs the "pixel" GRUB theme and /etc/default/grub, then regenerates grub.cfg.
# Run:  sudo ~/dotfiles/system/grub/install.sh
# (The older "golden" theme is still in golden/; point GRUB_THEME in ./grub at it to switch back.)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
theme=/boot/grub/themes/pixel

install -d "$theme"
install -m 644 "$here"/pixel/*.png "$here"/pixel/*.pf2 "$here"/pixel/theme.txt "$theme"/

# GRUB background = your current wallpaper as pixel art (the same art the Ly login shows,
# made by ../ly/make-ly-art.py), dimmed to 55% so the menu stays easy on the eyes.
# Not kept in the repo; rerun this after changing the wallpaper.
home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
wall="$home/Pictures/Wallpapers/current.png"
if [ -f "$wall" ] && command -v ffmpeg >/dev/null; then
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  python3 "$here/../ly/make-ly-art.py" "$wall" "$tmp" --png "$tmp/art.png" 2560x1600 >/dev/null
  ffmpeg -v error -y -i "$tmp/art.png" \
    -vf "format=gbrp,geq=r='r(X,Y)*0.55':g='g(X,Y)*0.55':b='b(X,Y)*0.55',format=rgb24" "$theme/background.png"
else
  echo "no wallpaper at $wall: GRUB gets a plain black background"
fi

[ -f /etc/default/grub.bak ] || cp /etc/default/grub /etc/default/grub.bak   # keep the original once
install -m 644 "$here/grub" /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg
echo "done. original config saved as /etc/default/grub.bak"
